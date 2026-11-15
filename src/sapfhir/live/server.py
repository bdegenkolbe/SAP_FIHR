# -*- coding: utf-8 -*-
"""sapfhir-live — Analyse-MCP direkt auf der IS-H-Replika (MSSQL, read-only)
mit lernender Wissensschicht.

Unterschied zum bestehenden sapfhir.mcp.server: dieser arbeitet NICHT auf dem
lokalen DuckDB-Warehouse (mcp.*-Schicht), sondern LIVE gegen Replicate.sap.* —
fuer die Datenbank-Erschliessung nach Analyse_Datenbank.md (Dreiklang: Schema
live, Daten live) und Ad-hoc-Fragen (z.B. RKT/ZNRKT, §301, Bewegungsketten).

Schutz (Defense-in-Depth, die harte Grenze ist der db_datareader-Login):
  - tsql_guard: ein SELECT/WITH, keine Kommentare/Variablen/DML/EXEC/INTO,
    nur freigegebene Schemas, Verkryptungspflicht (PSEUDO/LEN/LEFT/COUNT),
    Massentabellen nur mit WHERE
  - Serverseitig: READ UNCOMMITTED (Replika schonen), LOCK_TIMEOUT, Query-Timeout,
    Zeilenlimit (max. 1000), Nachmaskierung gleichnamiger PII-Spalten
  - Audit-Log mit Hash-Kette (Parameter nur als Hash)

Lernen: jede Abfrage (ohne Literale), Join-Pfade, Fehlermuster, Schema,
Zeilenzahlen, Fuellgrade und explizit gemerkte Fakten landen in
data/knowledge/live.sqlite und fliessen in kontext()/wissen_suchen() zurueck.

Start:  python -m sapfhir.live.server   (im Repo-Root; liest config/connection.yaml
        + config/live_mcp.yaml)
"""
from __future__ import annotations
import os
import re
import secrets
import time

import yaml

from . import tsql_guard as G
from .knowledge import Knowledge
from ..mcp.audit import Audit

_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_/]{0,63}$")

INSTRUCTIONS = """\
Live-Analyse der SAP IS-H/i.s.h.med-Replika (MSSQL, DB Replicate, Schema sap; \
MANDT='100', EINRI='0001'). Arbeitsweise (docs/Analyse_Datenbank.md):
1. ZUERST kontext(tabelle) bzw. wissen_suchen(frage): liefert verifizierte Fakten, \
PK, Fallstricke, gelernte Joins und bewaehrte Abfragen. Nicht raten, was schon bekannt ist.
2. Dreiklang: tabelle_beschreiben (Schema, PK) -> pk_pruefen -> fuellgrade / \
werteverteilung -> stichprobe. Schema-Wahrheit != Daten-Wahrheit.
3. Freie Abfragen mit sql_lesen (T-SQL, ein SELECT/WITH, Tabellen als sap.<T>). \
Gib immer einen kurzen 'zweck' an — daraus lernt der Server.
4. VERKRYPTUNG: Namen, Adressen, VERNR/KVNR, EDIFACT-Inhalte, Freitexte nie im \
Klartext; nur PSEUDO(f), LEN(f), LEFT(f,1), COUNT(f), f IS NULL; GBDAT nur YEAR().
5. Neue Erkenntnisse mit merken() festhalten (status hypothese), nach Beleg per \
fakt_bewerten() auf verifiziert/widerlegt setzen. Nie Patientendaten in Fakten schreiben.
6. Massentabellen (NLEI, N2LABOR001, >50 Mio) nur mit Schluesselfilter.
7. Unbekannte Codes nie raten — als Rohcode benennen.
"""


def _load_yaml(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


# ---------------------------------------------------------------------------
# Datenbankzugriff
# ---------------------------------------------------------------------------
class LiveDB:
    """Duenne Schicht ueber extract.dbsource.Source: Session-Settings, Salt als
    Parameter, Zeilenlimit, Reconnect."""

    def __init__(self, source_cfg: dict, timeout_s: int, lock_timeout_ms: int):
        self.cfg = {**source_cfg, "query_timeout": timeout_s}
        self.lock_timeout_ms = int(lock_timeout_ms)
        self._src = None

    def _source(self):
        if self._src is None:
            if not self.cfg.get("host"):
                raise RuntimeError("Keine Quell-DB konfiguriert — config/connection.yaml "
                                   "(Block 'source') anlegen, siehe connection.example.yaml.")
            from ..extract.dbsource import Source
            self._src = Source(self.cfg).connect()
        return self._src

    def close(self):
        if self._src:
            self._src.close()
            self._src = None

    def run(self, sql: str, salt: str | None = None, params: tuple = (),
            max_rows: int = 500) -> tuple[list, list, bool]:
        """Fuehrt sql aus. salt != None -> @__salt wird als Parameter deklariert.
        Liefert (spalten, zeilen[dict], abgeschnitten)."""
        for attempt in (1, 2):
            try:
                return self._run(sql, salt, params, max_rows)
            except Exception as e:  # Verbindung weg -> einmal neu verbinden
                if attempt == 2 or not _is_conn_error(e):
                    raise
                self.close()

    def _run(self, sql, salt, params, max_rows):
        from ..extract.dbsource import to_iso
        src = self._source()
        pyformat = getattr(src, "_paramstyle", "qmark") == "pyformat"
        ph = "%s" if pyformat else "?"
        prefix = ("SET NOCOUNT ON; SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; "
                  f"SET LOCK_TIMEOUT {self.lock_timeout_ms}; ")
        allp = list(params)
        if salt is not None:
            prefix += f"DECLARE @__salt nvarchar(256) = {ph}; "
            allp = [salt] + allp
        body = sql
        if pyformat and allp:
            body = body.replace("%", "%%")
            prefix = prefix.replace("%", "%%").replace("%%s", "%s")
        cur = src._conn.cursor()
        try:
            if allp:
                cur.execute(prefix + body, tuple(allp))
            else:
                cur.execute(prefix + body)
            while cur.description is None:
                if not cur.nextset():
                    return [], [], False
            cols = [d[0] for d in cur.description]
            raw = cur.fetchmany(max_rows + 1)
        finally:
            try:
                cur.close()
            except Exception:
                pass
        trunc = len(raw) > max_rows
        rows = []
        for r in raw[:max_rows]:
            d = {}
            for c, v in zip(cols, r):
                if isinstance(v, (bytes, bytearray)):
                    v = v.hex().upper()
                d[c] = to_iso(v)
            rows.append(d)
        return cols, rows, trunc


def _is_conn_error(e: Exception) -> bool:
    s = str(e).lower()
    return any(k in s for k in ("connection", "communication link", "closed", "reset",
                                "broken pipe", "08s01"))


# ---------------------------------------------------------------------------
# Service (MCP-unabhaengig, testbar)
# ---------------------------------------------------------------------------
class LiveService:
    def __init__(self, policy_cfg: dict, knowledge: Knowledge, db, audit: Audit | None,
                 salt: str | None = None):
        self.pcfg = policy_cfg
        lim = policy_cfg.get("limits", {})
        self.row_limit = int(lim.get("row_limit", 500))
        self.row_limit_max = int(lim.get("row_limit_max", 1000))
        self.mass_threshold = int(lim.get("mass_threshold", 50_000_000))
        self.k = knowledge
        self.db = db
        self.audit = audit
        self.salt = salt or os.environ.get("SAPFHIR_PRIVACY_SECRET") or ""
        self.salt_stable = bool(self.salt)
        if not self.salt:
            # ohne Secret: pro Prozess zufaellig -> Hashes nur innerhalb der Sitzung vergleichbar
            self.salt = secrets.token_hex(16)
        self._pii_raw = {k.upper(): v for k, v in (policy_cfg.get("pii") or {}).items()}
        self._pii_resolved: dict[str, set] = {}
        self._keep = {c.upper() for c in policy_cfg.get("pii_keep", [])}

    # -- Policy -----------------------------------------------------------
    def _pii_cols(self, table: str) -> set:
        t = table.upper()
        v = self._pii_raw.get(t)
        if v is None:
            return set()
        if v != "*":
            return {c.upper() for c in v}
        if t not in self._pii_resolved:
            cols = [c["spalte"] for c in self.k.get_schema(t)] or self._live_columns(t)
            if not cols:
                # Spalten unbekannt -> konservativ: Tabelle nicht freigeben
                raise G.GuardError(f"{t} ist komplett verkryptungspflichtig, Spalten "
                                   f"aber unbekannt — erst tabelle_beschreiben('{t}').")
            self._pii_resolved[t] = {c.upper() for c in cols} - self._keep
        return self._pii_resolved[t]

    def _live_columns(self, t: str) -> list:
        try:
            _, rows, _ = self.db.run(
                "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS "
                f"WHERE TABLE_SCHEMA='sap' AND TABLE_NAME='{t}'", max_rows=2000)
            return [r["COLUMN_NAME"] for r in rows]
        except Exception:
            return []

    def policy(self, tables=None) -> G.Policy:
        tables = tables if tables is not None else list(self._pii_raw)
        pii = {}
        for t in tables:
            cols = self._pii_cols(t)
            if cols:
                pii[t.upper()] = cols
        mass = {t.upper() for t in self.pcfg.get("mass_tables", [])}
        mass |= self.k.learned_mass_tables(self.mass_threshold)
        return G.Policy(
            allowed_schemas=tuple(self.pcfg.get("allowed_schemas",
                                                ["sap", "sys", "information_schema"])),
            allowed_databases=tuple(x.lower() for x in self.pcfg.get("allowed_databases",
                                                                     ["replicate"])),
            pii=pii, pii_dates={c.upper() for c in self.pcfg.get("pii_dates", [])},
            mass_tables=mass)

    def check(self, sql: str) -> G.Checked:
        # Phase 1: Tabellen bestimmen (ohne PII), Phase 2: mit PII der Tabellen pruefen
        first = G.check(sql, G.Policy(
            allowed_schemas=tuple(self.pcfg.get("allowed_schemas",
                                                ["sap", "sys", "information_schema"])),
            allowed_databases=tuple(x.lower() for x in self.pcfg.get("allowed_databases",
                                                                     ["replicate"]))))
        return G.check(sql, self.policy(first.tables))

    def is_pii(self, table: str, field: str) -> bool:
        return field.upper() in self._pii_cols(table)

    def is_mass(self, table: str) -> bool:
        return table.upper() in self.policy([]).mass_tables

    # -- Hilfen -------------------------------------------------------------
    @staticmethod
    def _ident(name: str, what: str = "Name") -> str:
        if not name or not _IDENT.match(name):
            raise G.GuardError(f"Ungueltiger {what}: {name!r}")
        return name.upper()

    def _log(self, tool: str, params: dict, rows: int, t0: float, ok=True, err=None):
        if self.audit:
            self.audit.log(tool, params, rows, time.time() - t0, ok=ok, err=err)

    def _exec(self, tool: str, sql: str, zweck: str = "", max_rows: int | None = None,
              checked: G.Checked | None = None, trusted: bool = False,
              tables: list | None = None) -> dict:
        """Gemeinsamer Ausfuehrungspfad: Guard -> DB -> Maskierung -> Lernen -> Audit."""
        t0 = time.time()
        n = min(int(max_rows or self.row_limit), self.row_limit_max)
        norm = G.literal_free(sql)
        try:
            if not trusted and checked is None:
                checked = self.check(sql)
        except G.GuardError as e:
            self.k.log_query(norm, tables or [], False, 0, time.time() - t0,
                             f"Guard: {e}", zweck)
            self._log(tool, {"sql": sql}, 0, t0, ok=False, err=str(e))
            return {"fehler": f"Abgewiesen: {e}"}
        exe = checked.sql if checked else sql
        tabs = checked.tables if checked else (tables or [])
        uses_salt = bool(checked and checked.uses_salt) or "@__salt" in exe
        try:
            cols, rows, trunc = self.db.run(exe, salt=self.salt if uses_salt else None,
                                            max_rows=n)
        except Exception as e:
            err = str(e)[:500]
            self.k.log_query(norm, tabs, False, 0, time.time() - t0, err, zweck)
            self._log(tool, {"sql": sql}, 0, t0, ok=False, err=err)
            out = {"fehler": err}
            hints = [p["meldung"] for t in tabs for p in self.k.pitfalls_for(t)][:5]
            if hints:
                out["bekannte_fallstricke"] = hints
            return out
        pii = checked.pii_columns if checked else set()
        rows = [G.mask_row(r, pii) for r in rows]
        self.k.log_query(norm, tabs, True, len(rows), time.time() - t0, None, zweck,
                         checked.join_pairs if checked else ())
        self._log(tool, {"sql": sql}, len(rows), t0)
        out = {"spalten": cols, "zeilen": rows, "anzahl": len(rows), "abgeschnitten": trunc}
        if trunc:
            out["hinweis"] = f"Auf {n} Zeilen begrenzt — aggregieren oder filtern."
        if uses_salt and not self.salt_stable:
            out["hinweis_pseudo"] = ("SAPFHIR_PRIVACY_SECRET nicht gesetzt: PSEUDO-Hashes "
                                     "sind nur innerhalb dieser Sitzung vergleichbar.")
        return out

    # -- Werkzeuge ----------------------------------------------------------
    def verbindung_pruefen(self) -> dict:
        _, rows, _ = self.db.run(
            "SELECT SERVERPROPERTY('ProductVersion') AS version, "
            "SERVERPROPERTY('Edition') AS edition, DB_NAME() AS db, SUSER_SNAME() AS login, "
            "IS_ROLEMEMBER('db_datawriter') AS datawriter, IS_ROLEMEMBER('db_owner') AS owner",
            max_rows=1)
        info = rows[0] if rows else {}
        info["warnung"] = ("Login hat Schreibrechte — fuer den MCP einen reinen "
                           "db_datareader-Login verwenden!") \
            if (info.get("datawriter") or info.get("owner")) else None
        info["salt_stabil"] = self.salt_stable
        return info

    def sql_lesen(self, sql: str, zweck: str = "", max_zeilen: int = 0) -> dict:
        out = self._exec("sql_lesen", sql, zweck, max_zeilen or None)
        if "fehler" not in out:
            try:
                tabs = self.check(sql).tables
            except G.GuardError:
                tabs = []
            facts = [f"#{f['id']} [{f['status']}] {f['aussage']}"
                     for t in tabs for f in self.k.facts(t) if f["status"] != "widerlegt"]
            if facts:
                out["bekannte_fakten"] = facts[:8]
        return out

    def tabellen_suchen(self, muster: str = "%") -> dict:
        m = (muster or "%").replace("*", "%")
        if not re.match(r"^[A-Za-z0-9_%/]{1,64}$", m):
            raise G.GuardError("Muster nur aus Buchstaben, Ziffern, _, %, / .")
        sql = ("SELECT t.name AS tabelle, SUM(p.rows) AS zeilen FROM sys.tables t "
               "JOIN sys.schemas s ON s.schema_id = t.schema_id "
               "JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1) "
               f"WHERE s.name = 'sap' AND t.name LIKE '{m}' AND t.name NOT LIKE '%[_][_]ct' "
               "AND t.name NOT LIKE '%[_][_]ct[_][_]bak' "
               "GROUP BY t.name ORDER BY t.name")
        out = self._exec("tabellen_suchen", sql, f"Tabellensuche {m}", 1000, trusted=True)
        for r in out.get("zeilen", []):
            self.k.put_stat(r["tabelle"], "zeilen", int(r["zeilen"] or 0))
            reg = self.k.registry.get(r["tabelle"].upper()) or {}
            r["registry"] = bool(reg)
            r["fhir"] = reg.get("fhir")
        return out

    def tabelle_beschreiben(self, tabelle: str) -> dict:
        t = self._ident(tabelle, "Tabellenname")
        cols = self._exec("tabelle_beschreiben",
                          "SELECT c.COLUMN_NAME AS spalte, c.DATA_TYPE AS typ, "
                          "c.CHARACTER_MAXIMUM_LENGTH AS laenge, "
                          "CASE c.IS_NULLABLE WHEN 'YES' THEN 1 ELSE 0 END AS nullable, "
                          "c.ORDINAL_POSITION AS ordinal FROM INFORMATION_SCHEMA.COLUMNS c "
                          f"WHERE c.TABLE_SCHEMA = 'sap' AND c.TABLE_NAME = '{t}' "
                          "ORDER BY c.ORDINAL_POSITION", f"Schema {t}", 1000, trusted=True,
                          tables=[t])
        if "fehler" in cols:
            return cols
        if not cols["zeilen"]:
            return {"fehler": f"Tabelle sap.{t} nicht gefunden (nicht repliziert?)",
                    "aehnliche": [r["titel"] for r in self.k.search(t, 5)]}
        pk = self._exec("tabelle_beschreiben",
                        "SELECT kcu.COLUMN_NAME AS spalte FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc "
                        "JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu ON kcu.CONSTRAINT_NAME = "
                        "tc.CONSTRAINT_NAME AND kcu.TABLE_SCHEMA = tc.TABLE_SCHEMA "
                        f"WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY' AND tc.TABLE_SCHEMA = 'sap' "
                        f"AND tc.TABLE_NAME = '{t}' ORDER BY kcu.ORDINAL_POSITION",
                        f"PK {t}", 100, trusted=True, tables=[t])
        cnt = self._exec("tabelle_beschreiben",
                         "SELECT SUM(p.rows) AS zeilen FROM sys.tables t "
                         "JOIN sys.schemas s ON s.schema_id = t.schema_id "
                         "JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1) "
                         f"WHERE s.name = 'sap' AND t.name = '{t}'", f"Zeilen {t}", 1,
                         trusted=True, tables=[t])
        pk_cols = [r["spalte"].upper() for r in pk.get("zeilen", [])]
        schema = [{**c, "pk": c["spalte"].upper() in pk_cols} for c in cols["zeilen"]]
        self.k.put_schema(t, schema)
        self._pii_resolved.pop(t, None)
        n = (cnt.get("zeilen") or [{}])[0].get("zeilen")
        if n is not None:
            self.k.put_stat(t, "zeilen", int(n))
        reg = self.k.registry.get(t) or {}
        reg_pk = [c.upper() for c in reg.get("pk", [])]
        pii = self._pii_cols(t)
        return {
            "tabelle": t, "zeilen": n, "massentabelle": self.is_mass(t),
            "pk_db": pk_cols, "pk_registry": reg_pk or None,
            "pk_abweichung": bool(reg_pk and pk_cols and reg_pk != pk_cols),
            "spalten": [{**c, "verkryptet": c["spalte"].upper() in pii} for c in schema],
            "registry_notiz": reg.get("notes"),
        }

    def pk_pruefen(self, tabelle: str, felder: list[str] | None = None) -> dict:
        t = self._ident(tabelle, "Tabellenname")
        if self.is_mass(t):
            return {"fehler": f"{t} ist Massentabelle — PK-Pruefung ins Lastfenster/Batch."}
        fs = [self._ident(f, "Feldname") for f in (felder or [])] or \
            [c.upper() for c in (self.k.registry.get(t) or {}).get("pk", [])] or \
            [c["spalte"] for c in self.k.get_schema(t) if c["pk"]]
        if not fs:
            return {"fehler": "Kein PK bekannt — felder angeben oder erst tabelle_beschreiben."}
        cl = ", ".join(f"[{f}]" for f in fs)
        sql = (f"SELECT (SELECT COUNT_BIG(*) FROM sap.[{t}]) AS zeilen, "
               f"(SELECT COUNT_BIG(*) FROM (SELECT {cl} FROM sap.[{t}] GROUP BY {cl} "
               f"HAVING COUNT_BIG(*) > 1) d) AS doppelte_schluessel")
        out = self._exec("pk_pruefen", sql, f"PK-Uniqueness {t}({','.join(fs)})", 1,
                         trusted=True, tables=[t])
        if "fehler" in out:
            return out
        r = out["zeilen"][0]
        res = {"tabelle": t, "felder": fs, "zeilen": r["zeilen"],
               "doppelte_schluessel": r["doppelte_schluessel"],
               "eindeutig": int(r["doppelte_schluessel"] or 0) == 0}
        self.k.put_stat(t, f"pk:{','.join(fs)}", res)
        return res

    def fuellgrade(self, tabelle: str, felder: list[str] | None = None) -> dict:
        t = self._ident(tabelle, "Tabellenname")
        if self.is_mass(t):
            return {"fehler": f"{t} ist Massentabelle — Fuell-Audit ins Lastfenster/Batch "
                              f"(Analyse_Datenbank §4)."}
        fs = [self._ident(f, "Feldname") for f in (felder or [])]
        if not fs:
            fs = [c["spalte"] for c in self.k.get_schema(t)][:80]
        if not fs:
            return {"fehler": "Spalten unbekannt — felder angeben oder erst tabelle_beschreiben."}
        parts = [f"SUM(CASE WHEN LTRIM(RTRIM(ISNULL(CAST([{f}] AS nvarchar(4000)), ''))) "
                 f"NOT IN ('', '0', '00000000', '000000', '0000000000', '0.000', '0101-01-01') "
                 f"THEN 1 ELSE 0 END) AS [{f}]" for f in fs]
        sql = f"SELECT COUNT_BIG(*) AS [__n], {', '.join(parts)} FROM sap.[{t}]"
        out = self._exec("fuellgrade", sql, f"Fuellgrade {t}", 1, trusted=True, tables=[t])
        if "fehler" in out:
            return out
        r = out["zeilen"][0]
        n = int(r.pop("__n") or 0)
        res = {f: {"belegt": int(v or 0), "quote": round(int(v or 0) / n, 4) if n else None}
               for f, v in r.items()}
        self.k.put_stat(t, "fuellgrade", {"n": n, "felder": res})
        self.k.put_stat(t, "zeilen", n)
        tot = [f for f, v in res.items() if v["belegt"] == 0]
        return {"tabelle": t, "zeilen": n, "felder": res, "tote_felder": tot}

    def werteverteilung(self, tabelle: str, feld: str, top: int = 20) -> dict:
        t = self._ident(tabelle, "Tabellenname")
        f = self._ident(feld, "Feldname")
        if self.is_pii(t, f):
            return {"fehler": f"{t}.{f} ist verkryptungspflichtig — keine Werteverteilung. "
                              f"Nur LEN/COUNT via sql_lesen."}
        if self.is_mass(t):
            return {"fehler": f"{t} ist Massentabelle — Verteilung ins Lastfenster oder "
                              f"sql_lesen mit Schluesselfilter."}
        top = max(1, min(int(top), 200))
        sql = (f"SELECT TOP ({top}) [{f}] AS wert, COUNT_BIG(*) AS n FROM sap.[{t}] "
               f"GROUP BY [{f}] ORDER BY n DESC")
        out = self._exec("werteverteilung", sql, f"Werteverteilung {t}.{f}", top,
                         trusted=True, tables=[t])
        if "fehler" not in out:
            self.k.put_stat(t, f"werte:{f}", out["zeilen"])
        return out

    def stichprobe(self, tabelle: str, felder: list[str] | None = None, n: int = 20,
                   where: str = "") -> dict:
        t = self._ident(tabelle, "Tabellenname")
        fs = [self._ident(f, "Feldname") for f in (felder or [])]
        if not fs:
            proj = self.k.projections.get(t)
            if proj:
                y = yaml.safe_load(proj) or {}
                fs = [str(x).upper() for x in (y.get("select") or [])]
        if not fs:
            fs = [c["spalte"] for c in self.k.get_schema(t)][:25]
        if not fs:
            return {"fehler": "Spalten unbekannt — felder angeben oder erst tabelle_beschreiben."}
        dates = {c.upper() for c in self.pcfg.get("pii_dates", [])}
        sel = []
        for f in fs:
            if self.is_pii(t, f):
                sel.append(f"YEAR([{f}]) AS [{f}_jahr]" if f in dates
                           else f"PSEUDO([{f}]) AS [{f}_h]")
            else:
                sel.append(f"[{f}]")
        n = max(1, min(int(n), self.row_limit_max))
        sql = f"SELECT TOP ({n}) {', '.join(sel)} FROM sap.[{t}]"
        if where.strip():
            sql += f" WHERE {where.strip()}"
        return self._exec("stichprobe", sql, f"Stichprobe {t}", n)

    def kontext(self, tabelle: str) -> dict:
        t = self._ident(tabelle, "Tabellenname")
        try:
            pii = sorted(self._pii_cols(t))
        except G.GuardError as e:
            pii = [f"(komplett verkryptet: {e})"]
        return self.k.context(t, pii, self.is_mass(t))

    def wissen_suchen(self, frage: str, limit: int = 15) -> list[dict]:
        return self.k.search(frage, max(1, min(int(limit), 50)))

    def merken(self, aussage: str, tabelle: str = "", feld: str = "",
               status: str = "hypothese", beleg_sql: str = "") -> dict:
        t = self._ident(tabelle, "Tabellenname") if tabelle else ""
        f = self._ident(feld, "Feldname") if feld else ""
        if beleg_sql:
            beleg_sql = G.literal_free(beleg_sql)
        fid = self.k.add_fact(aussage, t, f, status, beleg_sql)
        return {"id": fid, "status": status,
                "hinweis": "Nach Beleg mit fakt_bewerten() auf verifiziert setzen."
                if status == "hypothese" else None}

    def fakt_bewerten(self, fakt_id: int, status: str, beleg: str = "") -> dict:
        return self.k.set_fact_status(int(fakt_id), status, G.literal_free(beleg) if beleg else "")

    def abfrage_speichern(self, name: str, sql: str, zweck: str) -> dict:
        n = self._ident(name.replace("-", "_"), "Abfragename")
        c = self.check(sql)
        self.k.save_query(n, sql.strip(), zweck, c.tables)
        return {"gespeichert": n, "tabellen": c.tables}

    def abfrage_ausfuehren(self, name: str, max_zeilen: int = 0) -> dict:
        s = self.k.get_saved(self._ident(name.replace("-", "_"), "Abfragename"))
        if not s:
            return {"fehler": f"Keine gespeicherte Abfrage '{name}'.",
                    "vorhanden": [x["name"] for x in self.k.saved()][:30]}
        return self._exec("abfrage_ausfuehren", s["sql"], s["zweck"], max_zeilen or None)

    def abfragen(self, tabelle: str = "") -> list[dict]:
        return self.k.saved(tabelle)

    def wissen_export(self) -> dict:
        md = self.k.export_markdown()
        d = (self.pcfg.get("knowledge") or {}).get("export_dir", "data/knowledge")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, f"wissen_export_{time.strftime('%Y%m%d_%H%M')}.md")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(md)
        return {"datei": p, "inhalt": md}


# ---------------------------------------------------------------------------
# MCP-Anbindung
# ---------------------------------------------------------------------------
def build_service(root: str = ".") -> LiveService:
    pcfg = _load_yaml(os.path.join(root, "config", "live_mcp.yaml"))
    ccfg = _load_yaml(os.path.join(root, "config", "connection.yaml"))
    kcfg = pcfg.get("knowledge") or {}
    lim = pcfg.get("limits") or {}
    k = Knowledge(kcfg.get("store", "data/knowledge/live.sqlite"), root,
                  tuple(kcfg.get("docs", [])))
    db = LiveDB(ccfg.get("source") or {}, int(lim.get("query_timeout_s", 60)),
                int(lim.get("lock_timeout_ms", 5000)))
    audit = Audit(kcfg.get("audit_log", "data/audit/live_mcp.jsonl"))
    return LiveService(pcfg, k, db, audit)


def _make_app():
    try:
        from mcp.server.fastmcp import FastMCP as _App  # mcp 1.x
    except Exception:
        try:
            from mcp.server.mcpserver import MCPServer as _App  # mcp 2.x
        except Exception:
            return None
    return _App("sapfhir-live", instructions=INSTRUCTIONS)


def register(app, svc: LiveService):
    """Registriert die Werkzeuge. Fehler des Guards kommen als {'fehler': ...} zurueck,
    damit das Modell daraus lernen und korrigieren kann."""

    import functools

    def safe(fn):
        @functools.wraps(fn)
        def wrap(*a, **kw):
            try:
                return fn(*a, **kw)
            except (G.GuardError, ValueError) as e:
                return {"fehler": str(e)}
        return wrap

    @app.tool()
    @safe
    def verbindung_pruefen() -> dict:
        """Server-Version, Datenbank, Login und ob der Login (unerwuenscht) Schreibrechte hat."""
        return svc.verbindung_pruefen()

    @app.tool()
    @safe
    def kontext(tabelle: str) -> dict:
        """ZUERST aufrufen: alles Bekannte zu einer IS-H-Tabelle — Registry (PK, FHIR-Ziel,
        verifizierte Notizen), Spaltenprojektion, verkryptungspflichtige Felder, Schema-Cache,
        Statistik, gemerkte Fakten, Fallstricke aus frueheren Fehlern, gelernte Joins,
        gespeicherte und bewaehrte Abfragen."""
        return svc.kontext(tabelle)

    @app.tool()
    @safe
    def wissen_suchen(frage: str, limit: int = 15) -> list:
        """Volltextsuche (BM25) ueber Projektdoku (Analyse_Datenbank, VERIFY_LOG, Datenkatalog,
        MD-Management), tables.yaml-Notizen, Spaltenprojektionen, Fakten und gespeicherte
        Abfragen. Z.B. 'Entlassart', 'RKT Reklamation', 'KVNR'."""
        return svc.wissen_suchen(frage, limit)

    @app.tool()
    @safe
    def tabellen_suchen(muster: str = "%") -> dict:
        """Tabellen im Schema sap nach LIKE-Muster (z.B. 'ZNRKT%', 'N2%') mit Zeilenzahl
        (aus Partitionsstatistik, billig) und ob sie in der Registry stehen."""
        return svc.tabellen_suchen(muster)

    @app.tool()
    @safe
    def tabelle_beschreiben(tabelle: str) -> dict:
        """Schema live: Spalten, Typen, PRIMARY KEY (DB vs. Registry), Zeilenzahl,
        verkryptungspflichtige Felder. Wird im Wissensspeicher gecacht."""
        return svc.tabelle_beschreiben(tabelle)

    @app.tool()
    @safe
    def pk_pruefen(tabelle: str, felder: list[str] | None = None) -> dict:
        """PK-Uniqueness live (Dreiklang Schritt 2). Ohne felder: PK aus Registry/Schema."""
        return svc.pk_pruefen(tabelle, felder)

    @app.tool()
    @safe
    def fuellgrade(tabelle: str, felder: list[str] | None = None) -> dict:
        """Fuellraten (ein Scan; '', '0', 00000000, 0101-01-01 gelten als leer) und tote
        Felder. Nicht fuer Massentabellen."""
        return svc.fuellgrade(tabelle, felder)

    @app.tool()
    @safe
    def werteverteilung(tabelle: str, feld: str, top: int = 20) -> dict:
        """Top-N Werteverteilung eines kodierten Feldes (nicht fuer verkryptungspflichtige
        Felder)."""
        return svc.werteverteilung(tabelle, feld, top)

    @app.tool()
    @safe
    def stichprobe(tabelle: str, felder: list[str] | None = None, n: int = 20,
                   where: str = "") -> dict:
        """TOP-n-Stichprobe (max. 1000). Verkryptungspflichtige Felder kommen automatisch
        als SHA-256-Pseudonym (<feld>_h), GBDAT nur als Jahr. where = T-SQL-Bedingung
        (wird mitgeprueft). Ohne felder: Spaltenprojektion aus config/columns."""
        return svc.stichprobe(tabelle, felder, n, where)

    @app.tool()
    @safe
    def sql_lesen(sql: str, zweck: str = "", max_zeilen: int = 0) -> dict:
        """Freie T-SQL-Abfrage (ein SELECT/WITH, Tabellen als sap.<T>, max. 1000 Zeilen).
        Verkryptungspflichtige Felder nur als PSEUDO(f)/LEN(f)/LEFT(f,1)/COUNT(f)/IS NULL.
        'zweck' kurz angeben — der Server lernt daraus (Joins, bewaehrte Abfragen)."""
        return svc.sql_lesen(sql, zweck, max_zeilen)

    @app.tool()
    @safe
    def merken(aussage: str, tabelle: str = "", feld: str = "", status: str = "hypothese",
               beleg_sql: str = "") -> dict:
        """Erkenntnis dauerhaft festhalten (z.B. 'NFAL.ENDTYP in diesem Haus tot, Wahrheit
        NBEW.BWGR1'). status: hypothese|verifiziert|widerlegt. KEINE Patientendaten."""
        return svc.merken(aussage, tabelle, feld, status, beleg_sql)

    @app.tool()
    @safe
    def fakt_bewerten(fakt_id: int, status: str, beleg: str = "") -> dict:
        """Status eines gemerkten Fakts setzen (verifiziert/widerlegt) mit Beleg."""
        return svc.fakt_bewerten(fakt_id, status, beleg)

    @app.tool()
    @safe
    def abfrage_speichern(name: str, sql: str, zweck: str) -> dict:
        """Bewaehrte Abfrage unter einem Namen speichern (wird geprueft)."""
        return svc.abfrage_speichern(name, sql, zweck)

    @app.tool()
    @safe
    def abfrage_ausfuehren(name: str, max_zeilen: int = 0) -> dict:
        """Gespeicherte Abfrage ausfuehren."""
        return svc.abfrage_ausfuehren(name, max_zeilen)

    @app.tool()
    @safe
    def abfragen(tabelle: str = "") -> list:
        """Gespeicherte Abfragen, optional je Tabelle."""
        return svc.abfragen(tabelle)

    @app.tool()
    @safe
    def wissen_export() -> dict:
        """Gelerntes Wissen (Fakten, Fallstricke, Joins, Zeilenzahlen) als Markdown-Vorschlag
        fuer config/tables.yaml + VERIFY_LOG exportieren (Uebernahme nur nach Pruefung)."""
        return svc.wissen_export()

    return app


def main():
    app = _make_app()
    if app is None:
        raise SystemExit("mcp-SDK nicht installiert (pip install mcp)")
    # Relative Pfade (config/, data/) beziehen sich auf das Repo-/Installationsverzeichnis.
    root = os.environ.get("SAPFHIR_ROOT")
    if root:
        os.chdir(root)
    register(app, build_service("."))
    app.run()


if __name__ == "__main__":
    main()
