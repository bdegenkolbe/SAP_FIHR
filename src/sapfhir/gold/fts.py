# -*- coding: utf-8 -*-
"""Volltextindex (DuckDB-FTS/BM25) ueber N2TEXT fuer doc_search (CONCEPT §9).

Materialisiert die Dokumenttexte als Tabelle main.mcp_doc_text IN der Warehouse-
Datei (kein read_parquet im MCP-Anfragepfad -> Sandbox-kompatibel, CONCEPT §17.1)
und legt den BM25-Index an. Der Indexname folgt der DuckDB-Konvention
fts_main_mcp_doc_text.

Aufruf ueber gold/build.py oder:  python -m sapfhir.gold.fts
"""
from __future__ import annotations
import argparse

import duckdb

TEXT_COL = "TEXTINHALT"   # VERIFY Spaltenname N2TEXT (ggf. Zeilentabelle -> Aggregat)
ID_COL = "TEXTID"         # VERIFY


def build(con: duckdb.DuckDBPyConnection) -> bool:
    if not con.execute(
            "SELECT 1 FROM information_schema.tables "
            "WHERE table_schema='bronze_current' AND table_name='n2text'").fetchone():
        return False
    cols = {r[0].upper() for r in con.execute(
        "DESCRIBE bronze_current.n2text").fetchall()}
    if TEXT_COL not in cols or ID_COL not in cols:
        print(f"FTS uebersprungen: Spalten {ID_COL}/{TEXT_COL} nicht in N2TEXT "
              f"(vorhanden: {sorted(cols)}) — VERIFY aufloesen.")
        return False
    con.execute("INSTALL fts; LOAD fts;")
    keep = [ID_COL, TEXT_COL] + [c for c in ("PATNR", "FALNR", "DOCID") if c in cols]
    con.execute(f"""
        CREATE OR REPLACE TABLE mcp_doc_text AS
        SELECT {', '.join('"%s"' % c for c in keep)}
        FROM bronze_current.n2text
        WHERE "{TEXT_COL}" IS NOT NULL
    """)
    con.execute(f"PRAGMA create_fts_index('mcp_doc_text', '{ID_COL}', "
                f"'{TEXT_COL}', overwrite=1)")
    return True


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--warehouse", default="data/warehouse.duckdb")
    args = ap.parse_args(argv)
    con = duckdb.connect(args.warehouse)
    try:
        ok = build(con)
        print("FTS-Index erstellt." if ok else "FTS nicht erstellt (keine N2TEXT-Daten).")
    finally:
        con.close()


if __name__ == "__main__":
    main()
