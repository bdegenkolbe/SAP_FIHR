# -*- coding: utf-8 -*-
"""Lernende Wissensschicht des Live-Analyse-MCP (lokal, SQLite, kein Egress).

Zwei Quellen werden zusammengefuehrt:

STATISCH (Repo, bei jedem Start neu indiziert, nur gelesen):
  - config/tables.yaml        PK, FHIR-Ziel, Tier, verifizierte Notizen je Tabelle
  - config/columns/<T>.yaml   Spaltenprojektion mit Kommentaren
  - docs/*.md (Auswahl)       Methode, Verify-Log, Datenkatalog — abschnittsweise

GELERNT (data/knowledge/live.sqlite, waechst mit jeder Nutzung):
  - queries   jede Abfrage (Literale entfernt!), Tabellen, Erfolg, Dauer, Fehler
  - joins     Join-Paare aus erfolgreichen Abfragen (T1.F1 = T2.F2) mit Zaehler
  - pitfalls  Fehlermuster aus gescheiterten Abfragen (z.B. "Invalid column name")
  - schema    Spalten/Typen/PK je Tabelle (aus tabelle_beschreiben)
  - stats     Zeilenzahl, Fuellgrade, Werteverteilungen (nur Aggregate!)
  - facts     explizit gemerkte Erkenntnisse (hypothese -> verifiziert/widerlegt)
  - saved     benannte, bewaehrte Abfragen
  - fts       Volltextindex (FTS5/BM25) ueber alles Obige

Datenschutz: Es werden NIE Ergebnis-Zeilen gespeichert. SQL-Texte nur ohne
Literalinhalte (ausser bei ausdruecklich gespeicherten Abfragen, die den Guard
passiert haben). Werteverteilungen nur fuer nicht verkryptungspflichtige Felder.

Rueckfuehrung ins Repo (CLAUDE.md-Arbeitsregel): export_markdown() erzeugt einen
Vorschlag fuer config/tables.yaml + VERIFY_LOG — uebernommen wird nur nach
menschlicher Pruefung, nie automatisch.
"""
from __future__ import annotations
import json
import os
import re
import sqlite3
import time

_SCHEMA = """
CREATE TABLE IF NOT EXISTS queries(
  id INTEGER PRIMARY KEY, ts TEXT, sql_norm TEXT, sql_hash TEXT, tables TEXT,
  ok INTEGER, rows INTEGER, dur REAL, err TEXT, zweck TEXT);
CREATE INDEX IF NOT EXISTS ix_q_hash ON queries(sql_hash);
CREATE TABLE IF NOT EXISTS joins(
  t1 TEXT, f1 TEXT, t2 TEXT, f2 TEXT, n INTEGER, last_ts TEXT,
  PRIMARY KEY(t1, f1, t2, f2));
CREATE TABLE IF NOT EXISTS pitfalls(
  tabelle TEXT, muster TEXT, meldung TEXT, n INTEGER, last_ts TEXT,
  PRIMARY KEY(tabelle, muster));
CREATE TABLE IF NOT EXISTS schema_cols(
  tabelle TEXT, spalte TEXT, typ TEXT, laenge INTEGER, nullable INTEGER,
  ordinal INTEGER, pk INTEGER, ts TEXT, PRIMARY KEY(tabelle, spalte));
CREATE TABLE IF NOT EXISTS stats(
  tabelle TEXT, schluessel TEXT, wert TEXT, ts TEXT, PRIMARY KEY(tabelle, schluessel));
CREATE TABLE IF NOT EXISTS facts(
  id INTEGER PRIMARY KEY, ts TEXT, tabelle TEXT, feld TEXT, aussage TEXT,
  status TEXT, beleg TEXT, geaendert TEXT);
CREATE TABLE IF NOT EXISTS saved(
  name TEXT PRIMARY KEY, sql TEXT, zweck TEXT, tabellen TEXT, ts TEXT, uses INTEGER);
"""

FACT_STATUS = ("hypothese", "verifiziert", "widerlegt")

_ERR_PATTERNS = [
    (re.compile(r"Invalid column name '([^']+)'", re.I), "spalte_fehlt:{0}",
     "Spalte {0} existiert nicht"),
    (re.compile(r"Ungültiger Spaltenname '([^']+)'", re.I), "spalte_fehlt:{0}",
     "Spalte {0} existiert nicht"),
    (re.compile(r"Invalid object name '([^']+)'", re.I), "objekt_fehlt:{0}",
     "Objekt {0} existiert nicht / nicht repliziert"),
    (re.compile(r"Ungültiger Objektname '([^']+)'", re.I), "objekt_fehlt:{0}",
     "Objekt {0} existiert nicht / nicht repliziert"),
    (re.compile(r"Conversion failed[^.]*", re.I), "konvertierung",
     "Typkonvertierung scheitert (SAP-Felder sind oft varchar — CAST pruefen)"),
    (re.compile(r"timeout|abgebrochen|Zeitlimit", re.I), "timeout",
     "Abfrage timeoutet — Schluesselfilter/TOP verwenden oder ins Lastfenster"),
    (re.compile(r"Ambiguous column name '([^']+)'", re.I), "mehrdeutig:{0}",
     "Spalte {0} ist mehrdeutig — Alias-qualifizieren"),
]


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S")


class Knowledge:
    def __init__(self, path: str = "data/knowledge/live.sqlite", repo_root: str = ".",
                 doc_files: tuple = (), timeout: float = 30):
        if path != ":memory:":
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        # timeout: mehrere Server-Instanzen (Desktop-Chat, Cowork/Code-Pool,
        # Claude Code) teilen sich die Datei -> auf Sperren warten statt scheitern.
        self.db = sqlite3.connect(path, check_same_thread=False, timeout=timeout)
        self.db.row_factory = sqlite3.Row
        if path != ":memory:":
            try:
                self.db.execute("PRAGMA journal_mode=WAL")
            except sqlite3.OperationalError:
                pass
        self.db.executescript(_SCHEMA)
        self.root = repo_root
        self.doc_files = doc_files
        self.registry: dict = {}
        self.projections: dict = {}
        self.fts = self._init_fts()
        self.reload_static()

    # -- Volltext ---------------------------------------------------------
    def _init_fts(self) -> bool:
        try:
            self.db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts USING "
                            "fts5(quelle, tabelle, titel, text, tokenize='unicode61')")
            return True
        except sqlite3.OperationalError:
            self.db.execute("CREATE TABLE IF NOT EXISTS fts(quelle, tabelle, titel, text)")
            return False

    def _fts_add(self, quelle: str, tabelle: str, titel: str, text: str):
        self.db.execute("INSERT INTO fts(quelle, tabelle, titel, text) VALUES(?,?,?,?)",
                        (quelle, tabelle or "", titel or "", text or ""))

    def reload_static(self):
        """Repo-Wissen neu einlesen (statischer Teil des FTS-Index).

        Erst alles in den Speicher lesen, dann in EINER kurzen Transaktion
        schreiben. Scheitert das Schreiben (DB gesperrt durch eine parallel
        startende Server-Instanz, z.B. Claude Desktop Chat + Cowork/Code-Pool,
        oder schreibgeschuetzt), laeuft der Server mit dem vorhandenen Index
        weiter statt abzustuerzen (Vorfall R36)."""
        import sys
        import yaml
        rows = []
        p = os.path.join(self.root, "config", "tables.yaml")
        if os.path.exists(p):
            with open(p, encoding="utf-8") as f:
                self.registry = (yaml.safe_load(f) or {}).get("tables", {}) or {}
        for t, reg in self.registry.items():
            txt = " ".join(str(reg.get(k, "")) for k in ("fhir", "notes", "pk"))
            rows.append(("registry", t.upper(), f"tables.yaml {t}", txt))
        cdir = os.path.join(self.root, "config", "columns")
        if os.path.isdir(cdir):
            for fn in sorted(os.listdir(cdir)):
                if not fn.endswith(".yaml"):
                    continue
                with open(os.path.join(cdir, fn), encoding="utf-8") as f:
                    raw = f.read()
                t = fn[:-5].upper()
                self.projections[t] = raw
                rows.append(("spalten", t, f"config/columns/{fn}", raw))
        for rel in self.doc_files:
            fp = os.path.join(self.root, rel)
            if not os.path.exists(fp):
                continue
            with open(fp, encoding="utf-8") as f:
                text = f.read()
            for sec in re.split(r"\n(?=#{2,3} )", text):
                title = sec.strip().splitlines()[0][:120] if sec.strip() else rel
                rows.append(("doku", "", f"{rel} — {title}", sec[:8000]))
        try:
            self.db.execute("DELETE FROM fts WHERE quelle IN ('registry','spalten','doku')")
            for r in rows:
                self._fts_add(*r)
            self.db.commit()
        except sqlite3.OperationalError as e:
            try:
                self.db.rollback()
            except sqlite3.Error:
                pass
            print(f"[sapfhir-live] WARNUNG: Wissensindex nicht aktualisiert ({e}); "
                  "arbeite mit vorhandenem Index weiter.", file=sys.stderr)

    # -- Lernen aus Abfragen ------------------------------------------------
    def log_query(self, sql_norm: str, tables: list, ok: bool, rows: int, dur: float,
                  err: str | None = None, zweck: str = "", join_pairs=()):
        import hashlib
        h = hashlib.sha256(sql_norm.encode()).hexdigest()[:16]
        self.db.execute(
            "INSERT INTO queries(ts, sql_norm, sql_hash, tables, ok, rows, dur, err, zweck)"
            " VALUES(?,?,?,?,?,?,?,?,?)",
            (_now(), sql_norm, h, ",".join(tables), int(ok), rows, round(dur, 3),
             (err or "")[:500], zweck[:300]))
        if ok:
            for t1, f1, t2, f2 in join_pairs:
                a, b = sorted([(t1, f1), (t2, f2)])
                self.db.execute(
                    "INSERT INTO joins VALUES(?,?,?,?,1,?) ON CONFLICT(t1,f1,t2,f2) "
                    "DO UPDATE SET n=n+1, last_ts=excluded.last_ts",
                    (a[0], a[1], b[0], b[1], _now()))
            if zweck:
                self._fts_add("abfrage", ",".join(tables), zweck, sql_norm)
        elif err:
            self._learn_error(err, tables)
        self.db.commit()
        return h

    def _learn_error(self, err: str, tables: list):
        for rx, key, text in _ERR_PATTERNS:
            m = rx.search(err)
            if not m:
                continue
            args = m.groups() or ("",)
            muster = key.format(*[a.upper() for a in args])
            meldung = text.format(*args)
            for t in (tables or [""]):
                self.db.execute(
                    "INSERT INTO pitfalls VALUES(?,?,?,1,?) ON CONFLICT(tabelle, muster) "
                    "DO UPDATE SET n=n+1, last_ts=excluded.last_ts",
                    (t, muster, meldung, _now()))
            return

    # -- Schema/Statistik-Cache -------------------------------------------
    def put_schema(self, tabelle: str, cols: list[dict]):
        t = tabelle.upper()
        self.db.execute("DELETE FROM schema_cols WHERE tabelle=?", (t,))
        for c in cols:
            self.db.execute(
                "INSERT INTO schema_cols VALUES(?,?,?,?,?,?,?,?)",
                (t, c["spalte"].upper(), c.get("typ"), c.get("laenge"),
                 int(bool(c.get("nullable"))), c.get("ordinal"), int(bool(c.get("pk"))),
                 _now()))
        self.db.commit()

    def get_schema(self, tabelle: str) -> list[dict]:
        return [dict(r) for r in self.db.execute(
            "SELECT spalte, typ, laenge, nullable, pk FROM schema_cols WHERE tabelle=? "
            "ORDER BY ordinal", (tabelle.upper(),))]

    def put_stat(self, tabelle: str, schluessel: str, wert):
        self.db.execute(
            "INSERT INTO stats VALUES(?,?,?,?) ON CONFLICT(tabelle, schluessel) "
            "DO UPDATE SET wert=excluded.wert, ts=excluded.ts",
            (tabelle.upper(), schluessel, json.dumps(wert, default=str), _now()))
        self.db.commit()

    def get_stats(self, tabelle: str) -> dict:
        return {r["schluessel"]: {"wert": json.loads(r["wert"]), "stand": r["ts"]}
                for r in self.db.execute(
                    "SELECT schluessel, wert, ts FROM stats WHERE tabelle=?",
                    (tabelle.upper(),))}

    def rowcount(self, tabelle: str) -> int | None:
        r = self.db.execute("SELECT wert FROM stats WHERE tabelle=? AND schluessel='zeilen'",
                            (tabelle.upper(),)).fetchone()
        return json.loads(r["wert"]) if r else None

    def learned_mass_tables(self, threshold: int) -> set:
        out = set()
        for r in self.db.execute("SELECT tabelle, wert FROM stats WHERE schluessel='zeilen'"):
            try:
                if int(json.loads(r["wert"])) > threshold:
                    out.add(r["tabelle"])
            except (TypeError, ValueError):
                pass
        return out

    # -- Fakten -------------------------------------------------------------
    def add_fact(self, aussage: str, tabelle: str = "", feld: str = "",
                 status: str = "hypothese", beleg: str = "") -> int:
        if status not in FACT_STATUS:
            raise ValueError(f"status muss einer von {FACT_STATUS} sein")
        if not aussage.strip():
            raise ValueError("Leere Aussage.")
        cur = self.db.execute(
            "INSERT INTO facts(ts, tabelle, feld, aussage, status, beleg, geaendert) "
            "VALUES(?,?,?,?,?,?,?)",
            (_now(), tabelle.upper(), feld.upper(), aussage.strip(), status, beleg, _now()))
        self._fts_add("fakt", tabelle.upper(), f"Fakt #{cur.lastrowid} [{status}]",
                      f"{feld} {aussage}")
        self.db.commit()
        return cur.lastrowid

    def set_fact_status(self, fid: int, status: str, beleg: str = "") -> dict:
        if status not in FACT_STATUS:
            raise ValueError(f"status muss einer von {FACT_STATUS} sein")
        r = self.db.execute("SELECT * FROM facts WHERE id=?", (fid,)).fetchone()
        if not r:
            raise ValueError(f"Fakt #{fid} unbekannt")
        neu_beleg = (r["beleg"] + "\n" if r["beleg"] else "") + beleg if beleg else r["beleg"]
        self.db.execute("UPDATE facts SET status=?, beleg=?, geaendert=? WHERE id=?",
                        (status, neu_beleg, _now(), fid))
        self.db.commit()
        return dict(self.db.execute("SELECT * FROM facts WHERE id=?", (fid,)).fetchone())

    def facts(self, tabelle: str = "", status: str = "") -> list[dict]:
        q, p = "SELECT * FROM facts WHERE 1=1", []
        if tabelle:
            q += " AND tabelle=?"
            p.append(tabelle.upper())
        if status:
            q += " AND status=?"
            p.append(status)
        return [dict(r) for r in self.db.execute(q + " ORDER BY id", p)]

    # -- gespeicherte Abfragen ---------------------------------------------
    def save_query(self, name: str, sql: str, zweck: str, tabellen: list):
        self.db.execute(
            "INSERT INTO saved VALUES(?,?,?,?,?,0) ON CONFLICT(name) DO UPDATE SET "
            "sql=excluded.sql, zweck=excluded.zweck, tabellen=excluded.tabellen, ts=excluded.ts",
            (name, sql, zweck, ",".join(tabellen), _now()))
        self._fts_add("gespeichert", ",".join(tabellen), name, f"{zweck}\n{sql}")
        self.db.commit()

    def saved(self, tabelle: str = "") -> list[dict]:
        rows = [dict(r) for r in self.db.execute("SELECT * FROM saved ORDER BY uses DESC, name")]
        if tabelle:
            rows = [r for r in rows if tabelle.upper() in r["tabellen"].split(",")]
        return rows

    def get_saved(self, name: str) -> dict | None:
        r = self.db.execute("SELECT * FROM saved WHERE name=?", (name,)).fetchone()
        if r:
            self.db.execute("UPDATE saved SET uses=uses+1 WHERE name=?", (name,))
            self.db.commit()
        return dict(r) if r else None

    # -- Kontext & Suche ------------------------------------------------------
    def joins_for(self, tabelle: str) -> list[dict]:
        t = tabelle.upper()
        return [dict(r) for r in self.db.execute(
            "SELECT * FROM joins WHERE t1=? OR t2=? ORDER BY n DESC LIMIT 30", (t, t))]

    def pitfalls_for(self, tabelle: str) -> list[dict]:
        return [dict(r) for r in self.db.execute(
            "SELECT muster, meldung, n, last_ts FROM pitfalls WHERE tabelle=? "
            "ORDER BY n DESC", (tabelle.upper(),))]

    def proven_queries(self, tabelle: str, limit: int = 8) -> list[dict]:
        t = tabelle.upper()
        return [dict(r) for r in self.db.execute(
            "SELECT sql_norm, MAX(zweck) AS zweck, COUNT(*) AS n, MAX(ts) AS zuletzt "
            "FROM queries WHERE ok=1 AND (','||tables||',') LIKE ? "
            "GROUP BY sql_hash ORDER BY n DESC, zuletzt DESC LIMIT ?",
            (f"%,{t},%", limit))]

    def context(self, tabelle: str, pii: list | None = None, mass: bool = False) -> dict:
        t = tabelle.upper()
        reg = self.registry.get(t) or self.registry.get(tabelle) or {}
        return {
            "tabelle": t,
            "registry": {k: reg.get(k) for k in ("schema", "fhir", "tier", "pk", "cdc",
                                                  "storno", "notes") if k in reg},
            "spaltenprojektion": self.projections.get(t),
            "verkryptungspflichtig": sorted(pii or []),
            "massentabelle": mass,
            "schema_cache": self.get_schema(t),
            "statistik": self.get_stats(t),
            "fakten": self.facts(t),
            "fallstricke": self.pitfalls_for(t),
            "gelernte_joins": self.joins_for(t),
            "gespeicherte_abfragen": self.saved(t),
            "bewaehrte_abfragen": self.proven_queries(t),
        }

    def search(self, text: str, limit: int = 15) -> list[dict]:
        text = (text or "").strip()
        if not text:
            return []
        if self.fts:
            toks = [w for w in re.findall(r"\w+", text) if len(w) > 1]
            if not toks:
                return []
            q = " OR ".join(f'"{w}"' for w in toks)
            rows = self.db.execute(
                "SELECT quelle, tabelle, titel, snippet(fts, 3, '»', '«', ' … ', 24) AS auszug "
                "FROM fts WHERE fts MATCH ? ORDER BY bm25(fts) LIMIT ?", (q, limit))
        else:
            rows = self.db.execute(
                "SELECT quelle, tabelle, titel, substr(text, 1, 300) AS auszug FROM fts "
                "WHERE text LIKE ? OR titel LIKE ? LIMIT ?",
                (f"%{text}%", f"%{text}%", limit))
        return [dict(r) for r in rows]

    # -- Export fuer menschliche Uebernahme ins Repo -------------------------
    def export_markdown(self) -> str:
        lines = [f"# Wissens-Export Live-MCP ({_now()})", "",
                 "Vorschlag zur Uebernahme in `config/tables.yaml` (notes, 'verifiziert Rx') "
                 "und `docs/VERIFY_LOG_R8-R13.md`. Nur nach Pruefung uebernehmen.", ""]
        for status in ("verifiziert", "widerlegt", "hypothese"):
            fs = self.facts(status=status)
            if not fs:
                continue
            lines += [f"## Fakten: {status} ({len(fs)})", ""]
            for f in fs:
                ref = ".".join(x for x in (f["tabelle"], f["feld"]) if x) or "allgemein"
                lines.append(f"- **#{f['id']} {ref}:** {f['aussage']}")
                if f["beleg"]:
                    lines.append(f"  - Beleg: `{f['beleg'][:400]}`")
            lines.append("")
        pf = [dict(r) for r in self.db.execute(
            "SELECT * FROM pitfalls ORDER BY tabelle, n DESC")]
        if pf:
            lines += ["## Fallstricke (aus Fehlern gelernt)", ""]
            lines += [f"- {p['tabelle'] or '?'}: {p['meldung']} ({p['n']}x)" for p in pf]
            lines.append("")
        js = [dict(r) for r in self.db.execute("SELECT * FROM joins ORDER BY n DESC LIMIT 50")]
        if js:
            lines += ["## Gelernte Join-Pfade", ""]
            lines += [f"- {j['t1']}.{j['f1']} = {j['t2']}.{j['f2']} ({j['n']}x)" for j in js]
            lines.append("")
        rc = [dict(r) for r in self.db.execute(
            "SELECT tabelle, wert, ts FROM stats WHERE schluessel='zeilen' ORDER BY tabelle")]
        if rc:
            lines += ["## Zeilenzahlen", ""]
            lines += [f"- {r['tabelle']}: {json.loads(r['wert']):,} (Stand {r['ts']})"
                      .replace(",", ".") for r in rc]
        return "\n".join(lines) + "\n"
