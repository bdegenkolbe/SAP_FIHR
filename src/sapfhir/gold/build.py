# -*- coding: utf-8 -*-
"""Baut die Gold-Views (marts.sql) und den Volltextindex (FTS) im DuckDB-Warehouse.

CLI: python -m sapfhir.gold.build --config config/connection.yaml
"""
from __future__ import annotations
import argparse
import os

import duckdb
import yaml


def _load(p):
    with open(p, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def build(warehouse: str = "data/warehouse.duckdb"):
    con = duckdb.connect(warehouse)
    here = os.path.dirname(__file__)
    with open(os.path.join(here, "marts.sql"), "r", encoding="utf-8") as f:
        con.execute(f.read())
    # FTS-Extension (lokal, kein Netz): Volltext ueber N2TEXT
    try:
        con.execute("INSTALL fts; LOAD fts;")
        con.execute("""
            CREATE OR REPLACE TABLE gold.doc_text AS
            SELECT * FROM read_parquet('data/bronze/n2text/**/*.parquet',
                                       union_by_name=true)
        """)
        # PRAGMA erzeugt den BM25-Index; Spaltennamen VERIFY (TEXTINHALT/TEXT)
        con.execute("PRAGMA create_fts_index('gold.doc_text', 'TEXTID', 'TEXTINHALT', "
                    "overwrite=1)")  # VERIFY Spalten
        print("FTS-Index auf gold.doc_text erstellt.")
    except Exception as e:
        print(f"FTS uebersprungen ({e}) - N2TEXT evtl. noch nicht entladen.")
    con.close()
    print(f"Gold-Views gebaut in {warehouse}")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config/connection.yaml")
    ap.add_argument("--warehouse", default="data/warehouse.duckdb")
    args = ap.parse_args(argv)
    build(args.warehouse)


if __name__ == "__main__":
    main()
