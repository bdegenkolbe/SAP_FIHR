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

TEXT_COL = "TXT"          # verifiziert R8: N2TEXT.TXT (LCHR 8070)
# DVS-Schluessel (R8): synthetische Dok-ID aus DOKAR-DOKNR-DOKVR-DOKTL
KEY_COLS = ["DOKAR", "DOKNR", "DOKVR", "DOKTL"]


def build(con: duckdb.DuckDBPyConnection) -> bool:
    if not con.execute(
            "SELECT 1 FROM information_schema.tables "
            "WHERE table_schema='bronze_current' AND table_name='n2text'").fetchone():
        return False
    cols = {r[0].upper() for r in con.execute(
        "DESCRIBE bronze_current.n2text").fetchall()}
    if TEXT_COL not in cols or not all(k in cols for k in KEY_COLS):
        print(f"FTS uebersprungen: Spalten {KEY_COLS}/{TEXT_COL} nicht in N2TEXT "
              f"(vorhanden: {sorted(cols)}).")
        return False
    con.execute("INSTALL fts; LOAD fts;")
    key_expr = " || '-' || ".join(f'COALESCE(CAST("{c}" AS VARCHAR), \'\')'
                                  for c in KEY_COLS)
    # PATNR/FALNR fuer den Patientenfilter aus NDOC dazu joinen (falls vorhanden)
    join = ""
    pat_cols = ""
    if bool(con.execute(
            "SELECT 1 FROM information_schema.tables WHERE table_schema='bronze_current' "
            "AND table_name='ndoc'").fetchone()):
        join = ('LEFT JOIN bronze_current.ndoc d USING ("DOKAR","DOKNR","DOKVR","DOKTL") ')
        pat_cols = ', d."PATNR" AS PATNR, d."FALNR" AS FALNR'
    con.execute(f"""
        CREATE OR REPLACE TABLE mcp_doc_text AS
        SELECT {key_expr} AS TEXTID, t."{TEXT_COL}" AS TEXTINHALT{pat_cols}
        FROM bronze_current.n2text t
        {join}
        WHERE t."{TEXT_COL}" IS NOT NULL
    """)
    con.execute("PRAGMA create_fts_index('mcp_doc_text', 'TEXTID', "
                "'TEXTINHALT', overwrite=1)")
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
