# -*- coding: utf-8 -*-
"""Datenqualitaet & Reconciliation (CONCEPT §15).

- Reconciliation: Zeilenzahl Quelle (extract_state) vs. bronze_current je Tabelle
  -> _meta.reconciliation (Dashboard-Kachel). Mit --source laeuft der exakte
  COUNT(*) gegen die Live-Replika (nachts im Lastfenster).
- Feldprofile: NULL-Quoten + Enum-Haeufigkeiten der Mapping-Spalten
  -> _meta.field_profile (unterlegt die # VERIFY-Annahmen mit echten Werten).
- VERIFY-Report: listet alle offenen # VERIFY-Marker in src/ + config/
  (Phase-3-Gate: Tier 1 ohne offene Marker).

CLI:
  python -m sapfhir.gold.quality --warehouse data/warehouse.duckdb
  python -m sapfhir.gold.quality --verify-report
"""
from __future__ import annotations
import argparse
import glob
import os
import re

import duckdb
import yaml

_DDL = """
CREATE SCHEMA IF NOT EXISTS _meta;
CREATE TABLE IF NOT EXISTS _meta.reconciliation (
    ts TIMESTAMP, table_name VARCHAR, source_rows BIGINT,
    local_rows BIGINT, delta BIGINT, status VARCHAR
);
CREATE TABLE IF NOT EXISTS _meta.field_profile (
    ts TIMESTAMP, table_name VARCHAR, column_name VARCHAR,
    null_pct DOUBLE, top_values VARCHAR
);
"""

# Spalten, deren Wertebereich die # VERIFY-Enums belegt
PROFILE_COLS = {
    "npat": ["GSCHL", "STORN"],
    "nfal": ["FALAR", "STORN", "STATU"],
    "nbew": ["BEWTY", "STORN"],
    "ndia": ["STORN"],
    "nicp": ["STORN"],
}


def _tables(con) -> list[str]:
    return [r[0] for r in con.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema='bronze_current'").fetchall()]


def reconcile(con, source=None, threshold: float = 0.001) -> list[dict]:
    """Vergleicht bronze_current-Zeilen mit der Quelle. Ohne Live-Verbindung
    dient rows_seen aus dem Extract-State als Quell-Approximation."""
    out = []
    for t in _tables(con):
        local = con.execute(f'SELECT COUNT(*) FROM bronze_current."{t}"').fetchone()[0]
        if source is not None:
            src_rows = source.scalar(f"SELECT COUNT(*) FROM sap.[{t.upper()}]")
        else:
            r = con.execute(
                "SELECT MAX(rows_seen) FROM _meta.extract_state "
                "WHERE lower(table_name)=? AND phase='backfill'", [t]).fetchone()
            src_rows = r[0] if r and r[0] else None
        if src_rows is None:
            status = "UNKNOWN"
            delta = None
        else:
            delta = int(src_rows) - int(local)
            status = ("OK" if src_rows == 0 or
                      abs(delta) / max(int(src_rows), 1) <= threshold else "ALARM")
        con.execute("INSERT INTO _meta.reconciliation VALUES (now(),?,?,?,?,?)",
                    [t, src_rows, local, delta, status])
        out.append({"table": t, "source": src_rows, "local": local,
                    "delta": delta, "status": status})
    return out


def profile(con) -> int:
    n = 0
    for t in _tables(con):
        cols_avail = {r[0].upper() for r in
                      con.execute(f'DESCRIBE bronze_current."{t}"').fetchall()}
        for c in PROFILE_COLS.get(t, []):
            if c not in cols_avail:
                continue
            null_pct = con.execute(
                f'SELECT 100.0 * SUM(CASE WHEN "{c}" IS NULL THEN 1 ELSE 0 END) '
                f'/ GREATEST(COUNT(*),1) FROM bronze_current."{t}"').fetchone()[0]
            top = con.execute(
                f'SELECT string_agg(v || \'=\' || n, \', \') FROM ('
                f'  SELECT CAST("{c}" AS VARCHAR) v, COUNT(*) n '
                f'  FROM bronze_current."{t}" GROUP BY 1 ORDER BY n DESC LIMIT 8)'
            ).fetchone()[0]
            con.execute("INSERT INTO _meta.field_profile VALUES (now(),?,?,?,?)",
                        [t, c, round(null_pct or 0, 2), top])
            n += 1
    return n


def dias_coverage(index_path: str = "legacy/dias/OBJEKTBAUM_INDEX.md",
                  registry_path: str = "config/tables.yaml",
                  con=None) -> dict:
    """DIAS-Abdeckungsdiff (Analyse_Datenbank §5, automatisiert): jede im
    DIAS-Baum genutzte sap-Tabelle ohne Registry-Eintrag ist eine Luecke.
    Ergebnis nach _meta.dias_coverage (Dashboard-Kachel) + Rueckgabe."""
    if not os.path.exists(index_path):
        return {"error": f"{index_path} fehlt"}
    idx = open(index_path, encoding="utf-8").read()
    dias = set()
    for m in re.finditer(r"\| (?:Replicate|Analysen)\.(\w+)\.(\w+) \|", idx):
        if m.group(1).lower() == "sap" and not m.group(2).upper().endswith("__CT__BAK"):
            dias.add(m.group(2).upper())
    reg = set(t.upper() for t in
              yaml.safe_load(open(registry_path, encoding="utf-8"))["tables"])
    fehlt = sorted(dias - reg)
    out = {"dias_genutzt": len(dias), "in_registry": len(dias & reg),
           "luecken": fehlt}
    if con is not None:
        con.execute("CREATE TABLE IF NOT EXISTS _meta.dias_coverage ("
                    "ts TIMESTAMP, dias_genutzt INT, in_registry INT, "
                    "luecken VARCHAR)")
        con.execute("INSERT INTO _meta.dias_coverage VALUES (now(),?,?,?)",
                    [out["dias_genutzt"], out["in_registry"], ",".join(fehlt)])
    return out


def verify_report(roots=("src", "config")) -> list[dict]:
    """Alle offenen # VERIFY-Marker mit Datei/Zeile (Phase-3-Gate, CONCEPT §15.4)."""
    hits = []
    pat = re.compile(r"#\s*VERIFY|VERIFY\b")
    for root in roots:
        for f in glob.glob(os.path.join(root, "**", "*"), recursive=True):
            if not f.endswith((".py", ".yaml", ".sql")):
                continue
            try:
                with open(f, encoding="utf-8") as fh:
                    for i, line in enumerate(fh, 1):
                        if "VERIFY" in line:
                            hits.append({"file": f, "line": i,
                                         "text": line.strip()[:120]})
            except OSError:
                continue
    return hits


def run(warehouse: str = "data/warehouse.duckdb", source=None) -> dict:
    con = duckdb.connect(warehouse)
    try:
        con.execute(_DDL)
        rec = reconcile(con, source)
        prof = profile(con)
        dias = dias_coverage(con=con)
    finally:
        con.close()
    return {"reconciliation": rec, "profiles": prof, "dias": dias}


def main(argv=None):
    ap = argparse.ArgumentParser(description="DQ-Checks + VERIFY-Report")
    ap.add_argument("--warehouse", default="data/warehouse.duckdb")
    ap.add_argument("--verify-report", action="store_true")
    args = ap.parse_args(argv)
    if args.verify_report:
        hits = verify_report()
        for h in hits:
            print(f"{h['file']}:{h['line']}: {h['text']}")
        print(f"\n{len(hits)} offene VERIFY-Marker.")
        return
    res = run(args.warehouse)
    alarms = [r for r in res["reconciliation"] if r["status"] == "ALARM"]
    for r in res["reconciliation"]:
        print(f"  {r['table']:<12} quelle={r['source']} lokal={r['local']} "
              f"-> {r['status']}")
    print(f"Feldprofile: {res['profiles']}  |  Alarme: {len(alarms)}")
    if alarms:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
