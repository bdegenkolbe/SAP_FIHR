# -*- coding: utf-8 -*-
"""Merge-Layer: bronze_current.*-Views + naechtliche Compaction (CONCEPT §14).

bronze_current.<tabelle> = neueste Version je PK aus (Backfill ∪ Delta),
Deletes (_op='D') ausgeblendet, Metaspalten entfernt. Alle Konsumenten
(Gold-Marts, Silver-Ausleitung, Graph, MCP-Views) lesen ausschliesslich diese
Views — nie Roh-Glob-Pfade. Ohne diesen Schritt waeren CDC-Aenderungen unsichtbar
(ANALYSE A1).

Compaction faltet Delta-Dateien in die Jahrespartitionen ein (rewrite der
betroffenen Partitionen aus bronze_current, atomar via Staging + Rename),
verschiebt eingefaltete Deltas ins Archiv (kein Hard-Delete vor dem
Archiv-Horizont) und konsolidiert dabei die vielen Kleindateien des Backfills.

CLI:
  python -m sapfhir.extract.merge --views              # nur Views (idempotent)
  python -m sapfhir.extract.merge --compact            # Compaction + Views
"""
from __future__ import annotations
import argparse
import glob
import os
import shutil
import time

import duckdb
import yaml


def _load(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _has_files(pattern: str) -> bool:
    return bool(glob.glob(pattern, recursive=True))


def view_sql(table: str, pk: list[str], bronze: str = "data/bronze") -> str | None:
    """SQL fuer bronze_current.<table>; None, wenn keine Bronze-Daten vorliegen."""
    t = table.lower()
    base_glob = os.path.join(bronze, t, "**", "*.parquet")
    delta_glob = os.path.join(bronze, "_delta", t, "*.parquet")
    if not _has_files(base_glob):
        return None
    # PK gegen real vorhandene Spalten pruefen (Registry kann Spalten nennen,
    # die eine schmale Projektion/Seed nicht traegt) — Teil-PK mit Warnung.
    import duckdb as _duck
    try:
        avail = {r[0].upper() for r in _duck.connect().execute(
            f"DESCRIBE SELECT * FROM read_parquet('{base_glob}', "
            f"union_by_name=true) LIMIT 0").fetchall()}
    except _duck.Error:
        avail = set()
    eff_pk = [c for c in pk if c.upper() in avail] if avail else list(pk)
    if not eff_pk:
        return None
    if len(eff_pk) < len(pk):
        print(f"  [merge] {t}: PK-Spalten {sorted(set(pk)-set(eff_pk))} fehlen "
              f"in Bronze — dedupliziere ueber {eff_pk}")
    part = ", ".join(f'"{c}"' for c in eff_pk)
    base = (f"SELECT *, CAST(NULL AS VARCHAR) AS _op, '' AS _seq "
            f"FROM read_parquet('{base_glob}', union_by_name=true)")
    if _has_files(delta_glob):
        src = (f"{base}\nUNION ALL BY NAME\n"
               f"SELECT * FROM read_parquet('{delta_glob}', union_by_name=true)")
    else:
        src = base
    return (
        f"CREATE OR REPLACE VIEW bronze_current.\"{t}\" AS\n"
        f"SELECT * EXCLUDE (_op, _seq, _rn) FROM (\n"
        f"  SELECT *, row_number() OVER (PARTITION BY {part} ORDER BY _seq DESC) AS _rn\n"
        f"  FROM (\n{src}\n  )\n"
        f") WHERE _rn = 1 AND COALESCE(_op, '') <> 'D'")


def create_views(con: duckdb.DuckDBPyConnection, registry: dict,
                 bronze: str = "data/bronze") -> list[str]:
    """(Re-)erzeugt alle bronze_current-Views. Liefert die erzeugten Tabellennamen."""
    con.execute("CREATE SCHEMA IF NOT EXISTS bronze_current")
    made = []
    for tname, reg in registry.items():
        sql = view_sql(tname, reg["pk"], bronze)
        if sql:
            con.execute(sql)
            made.append(tname.lower())
    return made


def compact_table(con: duckdb.DuckDBPyConnection, table: str, reg: dict,
                  bronze: str = "data/bronze") -> int:
    """Faltet Deltas einer Tabelle in die Jahrespartitionen ein.
    Liefert die Zahl der eingefalteten Delta-Dateien."""
    t = table.lower()
    delta_dir = os.path.join(bronze, "_delta", t)
    delta_files = sorted(glob.glob(os.path.join(delta_dir, "*.parquet")))
    if not delta_files:
        return 0

    date_col = reg.get("partition_date")
    year_expr = (f"COALESCE(substr(CAST(\"{date_col}\" AS VARCHAR), 1, 4), 'unknown')"
                 if date_col else "'unknown'")
    # betroffene Jahre aus den Deltas
    years = ([r[0] for r in con.execute(
        f"SELECT DISTINCT {year_expr} "
        f"FROM read_parquet('{os.path.join(delta_dir, '*.parquet')}', "
        f"union_by_name=true)").fetchall()] if date_col else ["unknown"])
    if date_col and "unknown" in years:
        # Delta-Zeile ohne Datum (typisch: Delete mit reinem PK) — Zieljahr unbekannt,
        # daher alle vorhandenen Partitionen rewriten, sonst ueberlebt die Basiszeile
        # die Archiv-Bereinigung und "aufersteht" in bronze_current.
        base_years = {os.path.basename(p).split("=", 1)[1]
                      for p in glob.glob(os.path.join(bronze, t, "jahr=*"))}
        years = sorted(set(years) | base_years)

    stage = os.path.join(bronze, f"_compact_{t}")
    shutil.rmtree(stage, ignore_errors=True)
    for y in years:
        ydir = os.path.join(stage, f"jahr={y}")
        os.makedirs(ydir, exist_ok=True)
        con.execute(
            f"COPY (SELECT * FROM bronze_current.\"{t}\" "
            f"      WHERE {year_expr} = ?) "
            f"TO '{os.path.join(ydir, 'part-0.parquet')}' "
            f"(FORMAT PARQUET, COMPRESSION ZSTD)", [str(y)])

    # Swap: betroffene Jahrespartitionen ersetzen, Deltas archivieren
    tdir = os.path.join(bronze, t)
    for y in years:
        old = (os.path.join(tdir, f"jahr={y}") if date_col
               else tdir)  # ohne partition_date liegt alles flach im Tabellenordner
        new = os.path.join(stage, f"jahr={y}")
        if date_col:
            shutil.rmtree(old, ignore_errors=True)
            shutil.move(new, old)
        else:
            # flache Tabelle: kompletten Inhalt ersetzen
            for f in glob.glob(os.path.join(tdir, "**", "*.parquet"), recursive=True):
                os.remove(f)
            os.makedirs(tdir, exist_ok=True)
            shutil.move(os.path.join(new, "part-0.parquet"),
                        os.path.join(tdir, "part-0.parquet"))
    shutil.rmtree(stage, ignore_errors=True)

    archive = os.path.join(bronze, "_delta_archive", t)
    os.makedirs(archive, exist_ok=True)
    for f in delta_files:
        shutil.move(f, os.path.join(archive, os.path.basename(f)))
    return len(delta_files)


def prune_archive(bronze: str = "data/bronze", horizon_days: int = 90) -> int:
    """Loescht archivierte Deltas aelter als der Horizont (CONCEPT §14, Default 90 Tage)."""
    cutoff = time.time() - horizon_days * 86400
    n = 0
    for f in glob.glob(os.path.join(bronze, "_delta_archive", "*", "*.parquet")):
        if os.path.getmtime(f) < cutoff:
            os.remove(f); n += 1
    return n


def run(warehouse: str = "data/warehouse.duckdb",
        registry_path: str = "config/tables.yaml",
        bronze: str = "data/bronze", compact: bool = False,
        horizon_days: int = 90) -> dict:
    registry = _load(registry_path)["tables"]
    con = duckdb.connect(warehouse)
    result = {"views": [], "compacted": {}, "pruned": 0}
    try:
        result["views"] = create_views(con, registry, bronze)
        if compact:
            con.execute("CREATE SCHEMA IF NOT EXISTS _meta;"
                        "CREATE TABLE IF NOT EXISTS _meta.compaction_log ("
                        "ts TIMESTAMP, table_name VARCHAR, delta_files INT)")
            for tname, reg in registry.items():
                if tname.lower() not in result["views"]:
                    continue
                n = compact_table(con, tname, reg, bronze)
                if n:
                    result["compacted"][tname] = n
                    con.execute("INSERT INTO _meta.compaction_log VALUES (now(), ?, ?)",
                                [tname, n])
            # Views neu erzeugen (Delta-Globs haben sich geaendert)
            result["views"] = create_views(con, registry, bronze)
            result["pruned"] = prune_archive(bronze, horizon_days)
    finally:
        con.close()
    return result


def main(argv=None):
    ap = argparse.ArgumentParser(description="bronze_current-Views + Compaction")
    ap.add_argument("--warehouse", default="data/warehouse.duckdb")
    ap.add_argument("--registry", default="config/tables.yaml")
    ap.add_argument("--bronze", default="data/bronze")
    ap.add_argument("--views", action="store_true", help="nur Views erzeugen")
    ap.add_argument("--compact", action="store_true", help="Compaction + Views")
    ap.add_argument("--horizon-days", type=int, default=90)
    args = ap.parse_args(argv)
    res = run(args.warehouse, args.registry, args.bronze,
              compact=args.compact, horizon_days=args.horizon_days)
    print(f"bronze_current: {len(res['views'])} Views"
          + (f", Compaction: {res['compacted']}" if res["compacted"] else "")
          + (f", Archiv bereinigt: {res['pruned']}" if res["pruned"] else ""))


if __name__ == "__main__":
    main()
