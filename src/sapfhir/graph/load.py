# -*- coding: utf-8 -*-
"""Laedt den Patienten-Graph in Kuzu (eingebettete Graph-DB, Cypher) — CONCEPT §7.

Liest ausschliesslich bronze_current.* (Merge-Views, §14), staged die Knoten-/
Kantenmengen mit DuckDB als Parquet und laedt sie via COPY FROM in Kuzu
(kein CSV-Umweg, kein Dienst, kein Adminrecht).

Abgeleitete Kanten:
- FOLGT_AUF: Bewegungskette je Fall (aufsteigende LFDNR)
- WIEDERAUFNAHME: Folgefall desselben Patienten < N Tage nach Entlassung UND
  gleiche ICD-Dreisteller-Gruppe der Hauptdiagnose (Definition fachlich zu
  fixieren, CONCEPT §20.8). Die Ableitung laeuft in DuckDB (SQL), nicht in Cypher.

CLI: python -m sapfhir.graph.load --config config/connection.yaml
"""
from __future__ import annotations
import argparse
import os
import shutil

import duckdb
import yaml

try:
    import kuzu
except Exception:
    kuzu = None

from .schema import DDL
from ..extract import merge as _merge

# Staging-Queries: Name -> (SQL ueber bronze_current, benoetigte Tabelle)
_NODE_SQL = {
    "patient": (
        "SELECT DISTINCT PATNR AS patnr, CAST(GSCHL AS VARCHAR) AS gender "
        "FROM bronze_current.npat WHERE PATNR IS NOT NULL", "npat"),
    "fall": (
        "SELECT DISTINCT FALNR AS falnr, CAST(FALAR AS VARCHAR) AS fallart, "
        "TRY_CAST(BEGDT AS DATE) AS beg, TRY_CAST(ENDAT AS DATE) AS ende "
        "FROM bronze_current.nfal WHERE FALNR IS NOT NULL", "nfal"),
    # Kanten/Knoten mit Fallbezug filtern auf existierende Faelle — nach einem
    # CDC-Delete koennen Detailzeilen sonst auf geloeschte Knoten zeigen.
    "bewegung": (
        "SELECT DISTINCT FALNR || '-' || LFDNR AS bewid, "
        "CAST(BEWTY AS VARCHAR) AS bewtyp, "
        "TRY_CAST(BWIDT AS DATE) AS beg, TRY_CAST(BWEDT AS DATE) AS ende "
        "FROM bronze_current.nbew WHERE FALNR IN "
        "(SELECT FALNR FROM bronze_current.nfal)", "nbew"),
    "oe": (
        "SELECT DISTINCT COALESCE(ORGPF, ORGFA) AS oeid "
        "FROM bronze_current.nbew "
        "WHERE COALESCE(ORGPF, ORGFA) IS NOT NULL", "nbew"),
    "diagnose": (
        "SELECT DISTINCT DKEY1 AS icd FROM bronze_current.ndia "
        "WHERE DKEY1 IS NOT NULL", "ndia"),
    "prozedur": (
        "SELECT DISTINCT COALESCE(CAST(ICPML AS VARCHAR), CAST(ICPK1 AS VARCHAR)) AS ops "
        "FROM bronze_current.nicp "
        "WHERE COALESCE(CAST(ICPML AS VARCHAR), CAST(ICPK1 AS VARCHAR)) IS NOT NULL", "nicp"),
}

_REL_SQL = {
    "HAT_FALL": (
        "SELECT DISTINCT PATNR, FALNR FROM bronze_current.nfal "
        "WHERE PATNR IS NOT NULL AND FALNR IS NOT NULL", "nfal"),
    "HAT_BEWEGUNG": (
        "SELECT DISTINCT FALNR, FALNR || '-' || LFDNR "
        "FROM bronze_current.nbew WHERE FALNR IN "
        "(SELECT FALNR FROM bronze_current.nfal)", "nbew"),
    "IN_OE": (
        "SELECT DISTINCT FALNR || '-' || LFDNR, COALESCE(ORGPF, ORGFA) "
        "FROM bronze_current.nbew "
        "WHERE COALESCE(ORGPF, ORGFA) IS NOT NULL AND FALNR IN "
        "(SELECT FALNR FROM bronze_current.nfal)", "nbew"),
    # Bewegungskette: aufsteigende LFDNR je Fall  # VERIFY: LFDREF/VGNREF nutzen
    "FOLGT_AUF": (
        "WITH b AS (SELECT FALNR, LFDNR, FALNR || '-' || LFDNR AS bewid, "
        "  row_number() OVER (PARTITION BY FALNR ORDER BY LFDNR) rn "
        "  FROM bronze_current.nbew WHERE FALNR IN "
        "  (SELECT FALNR FROM bronze_current.nfal)) "
        "SELECT a.bewid, n.bewid FROM b a "
        "JOIN b n ON a.FALNR = n.FALNR AND n.rn = a.rn + 1", "nbew"),
    "HAT_DIAGNOSE": (
        "SELECT DISTINCT FALNR, DKEY1 FROM bronze_current.ndia "
        "WHERE DKEY1 IS NOT NULL AND FALNR IN "
        "(SELECT FALNR FROM bronze_current.nfal)", "ndia"),
    "HAT_PROZEDUR": (
        "SELECT DISTINCT FALNR, COALESCE(CAST(ICPML AS VARCHAR), CAST(ICPK1 AS VARCHAR)) "
        "FROM bronze_current.nicp "
        "WHERE COALESCE(CAST(ICPML AS VARCHAR), CAST(ICPK1 AS VARCHAR)) IS NOT NULL AND FALNR IN "
        "(SELECT FALNR FROM bronze_current.nfal)", "nicp"),
}

# FUEHRT_ZUSAMMEN: echte Fallzusammenfuehrung aus NAPX_FAL (fuehrender Fall LEAD='X'
# -> untergeordnete Faelle derselben APXNR). REASON-Klartexte aus dem produktiven
# Altbestand (docs/ALTBESTAND_ANALYSE.md §4).
_ZUSAMMEN_SQL = (
    "WITH lead AS (SELECT APXNR, FALNR FROM bronze_current.napx_fal "
    "  WHERE LEAD = 'X' AND COALESCE(STORN,'') NOT IN ('X')), "
    "sub AS (SELECT APXNR, FALNR, REASON FROM bronze_current.napx_fal "
    "  WHERE COALESCE(LEAD,'') <> 'X' AND COALESCE(STORN,'') NOT IN ('X')) "
    "SELECT l.FALNR, s.FALNR, s.REASON, "
    "CASE s.REASON "
    "  WHEN 'RV' THEN 'Rueckverlegung' "
    "  WHEN 'WA' THEN 'Wiederaufnahme' "
    "  WHEN 'KO' THEN 'Komplikation' "
    "  WHEN 'OG' THEN 'Wiederaufnahme nach §2(1) FPV' "
    "  WHEN 'MD' THEN 'Wiederaufnahme nach §2(2) FPV' "
    "  WHEN 'WP' THEN 'Wiederaufnahme Psychiatrie/Psychosomatik' "
    "  WHEN 'RP' THEN 'Rueckverlegung Psychiatrie/Psychosomatik' "
    "  WHEN 'FW' THEN 'Fehlbelegung/Fallwechsel' "
    "  ELSE 'Sonstiges' END AS reason_text "
    "FROM lead l JOIN sub s USING (APXNR) "
    "WHERE l.FALNR IN (SELECT FALNR FROM bronze_current.nfal) "
    "  AND s.FALNR IN (SELECT FALNR FROM bronze_current.nfal)")

# WIEDERAUFNAHME: < {tage} Tage + gleiche ICD-Dreisteller-Gruppe der Hauptdiagnose
_WIEDERAUFNAHME_SQL = (
    "WITH f AS (SELECT PATNR, FALNR, TRY_CAST(BEGDT AS DATE) beg, "
    "  TRY_CAST(ENDAT AS DATE) ende FROM bronze_current.nfal "
    "  WHERE PATNR IS NOT NULL AND FALNR IS NOT NULL), "
    "hd AS (SELECT FALNR, substr(MIN(DKEY1), 1, 3) icd3 "
    "  FROM bronze_current.ndia WHERE DKEY1 IS NOT NULL GROUP BY 1) "
    "SELECT a.FALNR, b.FALNR, date_diff('day', a.ende, b.beg) AS tage "
    "FROM f a JOIN f b ON a.PATNR = b.PATNR AND a.FALNR <> b.FALNR "
    "JOIN hd ha ON ha.FALNR = a.FALNR "
    "JOIN hd hb ON hb.FALNR = b.FALNR AND ha.icd3 = hb.icd3 "
    "WHERE a.ende IS NOT NULL AND b.beg IS NOT NULL "
    "  AND b.beg > a.ende "
    "  AND date_diff('day', a.ende, b.beg) <= {tage}")


def _has(d: duckdb.DuckDBPyConnection, table: str) -> bool:
    return bool(d.execute(
        "SELECT 1 FROM information_schema.tables "
        "WHERE table_schema='bronze_current' AND table_name=?", [table]).fetchone())


def load(db_path: str = "data/graph.kuzu",
         warehouse: str = "data/warehouse.duckdb",
         registry_path: str = "config/tables.yaml",
         bronze: str = "data/bronze", wieder_tage: int = 30) -> dict:
    if kuzu is None:
        raise RuntimeError("kuzu nicht installiert (pip install kuzu)")

    # Neuaufbau: Graph ist aus Bronze reproduzierbar, kein Inkrement noetig
    if os.path.isdir(db_path):
        shutil.rmtree(db_path)
    elif os.path.exists(db_path):
        os.remove(db_path)

    d = duckdb.connect(warehouse, read_only=False)
    if os.path.exists(registry_path):
        with open(registry_path, encoding="utf-8") as f:
            _merge.create_views(d, yaml.safe_load(f)["tables"], bronze)
    if not _has(d, "nfal") or not _has(d, "npat"):
        d.close()
        raise RuntimeError("bronze_current.npat/nfal fehlen — erst Backfill/Seed.")

    db = kuzu.Database(db_path)
    con = kuzu.Connection(db)
    for stmt in DDL:
        con.execute(stmt)

    tmp = db_path + "_stage"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp, exist_ok=True)
    loaded = {}

    def stage_and_copy(target: str, name: str, sql: str, needs: str) -> bool:
        if not _has(d, needs):
            return False
        out = os.path.join(tmp, name + ".parquet")
        d.execute(f"COPY ({sql}) TO '{out}' (FORMAT PARQUET)")
        con.execute(f"COPY {target} FROM '{out}'")
        loaded[target] = True
        return True

    try:
        for name, (sql, needs) in _NODE_SQL.items():
            stage_and_copy(name.capitalize() if name != "oe" else "OE",
                           name, sql, needs)
        for rel, (sql, needs) in _REL_SQL.items():
            stage_and_copy(rel, "rel_" + rel.lower(), sql, needs)
        if _has(d, "ndia"):
            stage_and_copy("WIEDERAUFNAHME", "rel_wiederaufnahme",
                           _WIEDERAUFNAHME_SQL.format(tage=int(wieder_tage)),
                           "nfal")
        if _has(d, "napx_fal"):
            stage_and_copy("FUEHRT_ZUSAMMEN", "rel_fuehrt_zusammen",
                           _ZUSAMMEN_SQL, "napx_fal")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        d.close()
    print(f"Kuzu-Graph geladen: {db_path} ({len(loaded)} Tabellen)")
    return loaded


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config/connection.yaml")
    ap.add_argument("--db", default="data/graph.kuzu")
    ap.add_argument("--warehouse", default="data/warehouse.duckdb")
    ap.add_argument("--bronze", default="data/bronze")
    ap.add_argument("--registry", default="config/tables.yaml")
    args = ap.parse_args(argv)
    cfg = {}
    if os.path.exists(args.config):
        with open(args.config) as f:
            cfg = yaml.safe_load(f)
    wt = cfg.get("graph", {}).get("wiederaufnahme_tage", 30)
    load(args.db, args.warehouse, args.registry, args.bronze, wt)


if __name__ == "__main__":
    main()
