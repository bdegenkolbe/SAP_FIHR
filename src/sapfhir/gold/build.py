# -*- coding: utf-8 -*-
"""Gold-Build: bronze_current-Views -> Marts -> FTS -> MCP-View-Schicht -> DQ.

Reihenfolge ist Teil des Vertrags (CONCEPT §14/§15/§17):
  1. extract/merge.create_views  — ohne bronze_current sieht Gold keine CDC-Deltas
  2. marts.sql                   — Analyse-Views fuer das Dashboard
  3. fts.build                   — BM25-Index fuer doc_search (falls N2TEXT da)
  4. mcp/views.build             — maskierte, materialisierte mcp.*-Schicht
  5. quality.run                 — Reconciliation + Feldprofile

CLI: python -m sapfhir.gold.build --config config/connection.yaml
"""
from __future__ import annotations
import argparse
import os

import duckdb
import yaml

from ..extract import merge as _merge
from ..fhir.lookups import build_ref_tables
from . import fts as _fts
from . import quality as _quality
from ..mcp import views as _views


def _load(p):
    with open(p, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def build(warehouse: str = "data/warehouse.duckdb",
          registry_path: str = "config/tables.yaml",
          bronze: str = "data/bronze",
          pseudonymize_view: bool = True) -> dict:
    registry = _load(registry_path)["tables"]
    con = duckdb.connect(warehouse)
    result = {}
    try:
        views = _merge.create_views(con, registry, bronze)
        result["bronze_current"] = views

        here = os.path.dirname(__file__)
        with open(os.path.join(here, "marts.sql"), "r", encoding="utf-8") as f:
            con.execute(f.read())
        # optionale Marts (nur wenn die Quelle entladen wurde)
        if "ndrg" in views:
            con.execute("""
                CREATE OR REPLACE VIEW gold.casemix AS
                SELECT strftime(TRY_CAST(UPDAT AS DATE), '%Y') AS jahr,
                       COUNT(*) AS drg_faelle
                       -- SUM(bewertungsrelation) AS cm  -- VERIFY Spalte fuer CMI
                FROM bronze_current.ndrg GROUP BY 1""")
        result["marts"] = True

        # ref_*-Klartextschicht (CONCEPT_EXT §8): Kataloge materialisieren,
        # dann Klartext-Marts, die nur bei vorhandenem Katalog entstehen.
        result["ref"] = build_ref_tables(con)
        if "icd" in result["ref"] and "ndia" in views:
            con.execute("""
                CREATE OR REPLACE VIEW gold.top_diagnosen AS
                SELECT d.DKEY1 AS icd, ANY_VALUE(r."TEXT") AS text, COUNT(*) AS n
                FROM bronze_current.ndia d
                LEFT JOIN ref.icd r
                  ON CAST(d.DKAT1 AS VARCHAR) = r."DKAT"
                 AND CAST(d.DKEY1 AS VARCHAR) = r."DKEY"
                WHERE COALESCE(TRIM(d.STORN),'') NOT IN ('X','1')
                  AND COALESCE(d.KHDIA,'') = 'X'
                GROUP BY 1 ORDER BY n DESC LIMIT 50""")
        if "oe" in result["ref"] and "nbew" in views:
            con.execute("""
                CREATE OR REPLACE VIEW gold.belegung_oe AS
                SELECT COALESCE(b.ORGPF, b.ORGFA) AS oe,
                       ANY_VALUE(r."TEXT") AS oe_name,
                       COUNT(*) AS offene_bewegungen
                FROM bronze_current.nbew b
                LEFT JOIN ref.oe r
                  ON CAST(COALESCE(b.ORGPF, b.ORGFA) AS VARCHAR) = r."ORGID"
                WHERE (b.BWEDT IS NULL
                       OR substr(CAST(b.BWEDT AS VARCHAR),1,4) = '9999')
                  AND COALESCE(TRIM(b.STORN),'') NOT IN ('X','1')
                GROUP BY 1 ORDER BY offene_bewegungen DESC""")

        try:
            result["fts"] = _fts.build(con)
        except Exception as e:   # FTS-Extension optional
            print(f"FTS uebersprungen ({e})")
            result["fts"] = False

        result["mcp_views"] = _views.build(con, pseudonymize=pseudonymize_view)
    finally:
        con.close()

    result["quality"] = _quality.run(warehouse)
    return result


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config/connection.yaml")
    ap.add_argument("--warehouse", default="data/warehouse.duckdb")
    ap.add_argument("--registry", default="config/tables.yaml")
    ap.add_argument("--bronze", default="data/bronze")
    args = ap.parse_args(argv)
    cfg = _load(args.config) if os.path.exists(args.config) else {}
    pseudo = bool(cfg.get("mcp", {}).get("pseudonymize_view", True))
    res = build(args.warehouse, args.registry, args.bronze, pseudo)
    print(f"Gold gebaut: {len(res['bronze_current'])} bronze_current-Views, "
          f"FTS={res['fts']}, mcp-Views={res['mcp_views']}")


if __name__ == "__main__":
    main()
