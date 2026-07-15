# -*- coding: utf-8 -*-
"""Silver-Layer v2: bronze_current.* -> FHIR-R4-NDJSON (Bulk-Data-Format).

CONCEPT §16:
- liest ausschliesslich die Merge-Views bronze_current.* (nie Roh-Parquet), damit
  CDC-Aenderungen sichtbar sind;
- loest FALNR -> PATNR fuer NBEW/NDIA/NICP/N2LABOR/NDOC auf (subject-Referenz +
  Date-Shift-Schluessel); Zeilen ohne aufloesbare PATNR landen in _meta.orphan_rows;
- schreibt run-basiert: data/silver/fhir/<Typ>/run=<id>/part-0.ndjson.gz — ein Lauf
  ueberschreibt nie Dateien fremder Laeufe;
- fuehrt den FHIR-Index silver.fhir_index (resource_type, id, patnr, run_id, file,
  line) fuer fhir_get/fhir_search ohne Datei-Scan;
- erzeugt eine Provenance-Ressource je Lauf;
- inkrementell: exportiert nur Zeilen, deren PK seit dem letzten Lauf in den
  CDC-Deltas auftaucht (Erstlauf oder --full: alles).

CLI:
  python -m sapfhir.fhir.ndjson --config config/connection.yaml [--full]
"""
from __future__ import annotations
import argparse
import glob as _glob
import gzip
import json
import os
import time

import duckdb
import yaml

from . import ids as _ids
from .privacy import Privacy
from .terminology import LoincMap
from .lookups import Lookups
from .mappers import core as M
from ..extract import merge as _merge


def _load(path):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# Bronze-Tabelle -> (FHIR-Typ, Mapper, braucht_patnr_lookup)
# Mapper duerfen auch Listen liefern (map_geburt -> mehrere Observations).
TABLE_TO_FHIR = {
    "npat":    ("Patient", M.map_patient, False),
    "nfal":    ("Encounter", M.map_encounter, False),
    "nbew":    ("Encounter", M.map_encounter_bewegung, True),
    "ndia":    ("Condition", M.map_condition, True),
    "nicp":    ("Procedure", M.map_procedure, True),
    "n2labor": ("Observation", M.map_observation_labor, True),
    "ndoc":    ("DocumentReference", M.map_document_reference, True),
    "nksk":    ("Coverage", M.map_coverage, False),
    "ngeb":    ("Observation", M.map_geburt, False),
    "nbau":    ("Location", M.map_location_bau, False),
}

_DDL = """
CREATE SCHEMA IF NOT EXISTS silver;
CREATE TABLE IF NOT EXISTS silver.fhir_index (
    resource_type VARCHAR, id VARCHAR, patnr VARCHAR,
    run_id VARCHAR, file VARCHAR, line BIGINT
);
CREATE TABLE IF NOT EXISTS silver.silver_runs (
    run_id VARCHAR, table_name VARCHAR, max_seq VARCHAR,
    rows BIGINT, ts TIMESTAMP
);
CREATE SCHEMA IF NOT EXISTS _meta;
CREATE TABLE IF NOT EXISTS _meta.orphan_rows (
    run_id VARCHAR, table_name VARCHAR, falnr VARCHAR, n BIGINT
);
"""


class NdjsonWriter:
    """Ein gzip-NDJSON-Stream je Ressourcentyp, run-basiert, mit Index-Puffer."""

    def __init__(self, out_dir: str, run_id: str):
        self.out_dir = out_dir
        self.run_id = run_id
        self._fh: dict[str, gzip.GzipFile] = {}
        self._line: dict[str, int] = {}
        self.counts: dict[str, int] = {}
        self.index: list[tuple] = []

    def _path(self, rt: str) -> str:
        d = os.path.join(self.out_dir, "fhir", rt, f"run={self.run_id}")
        os.makedirs(d, exist_ok=True)
        return os.path.join(d, "part-0.ndjson.gz")

    def write(self, res: dict, patnr: str | None = None):
        rt = res["resourceType"]
        if rt not in self._fh:
            self._fh[rt] = gzip.open(self._path(rt), "wt", encoding="utf-8")
            self._line[rt] = 0
            self.counts[rt] = 0
        self._fh[rt].write(json.dumps(res, ensure_ascii=False, default=str) + "\n")
        self.index.append((rt, res["id"], patnr, self.run_id,
                           self._path(rt), self._line[rt]))
        self._line[rt] += 1
        self.counts[rt] += 1

    def close(self):
        for fh in self._fh.values():
            fh.close()


def _delta_globs(bronze: str, table: str) -> list[str]:
    return [g for g in (os.path.join(bronze, "_delta", table, "*.parquet"),
                        os.path.join(bronze, "_delta_archive", table, "*.parquet"))
            if _glob.glob(g)]


def _delta_max_seq(con, bronze: str, table: str) -> str | None:
    globs = _delta_globs(bronze, table)
    if not globs:
        return None
    return con.execute(
        f"SELECT MAX(_seq) FROM read_parquet({globs!r}, union_by_name=true)"
    ).fetchone()[0]


def _changed_pk_filter(con, bronze: str, table: str, pk: list[str],
                       last_seq: str) -> str | None:
    """WHERE-Zusatz: nur PKs, die seit last_seq in Deltas auftauchen.
    None -> keine Aenderungen (Tabelle ueberspringen)."""
    globs = _delta_globs(bronze, table)
    if not globs:
        return None
    keys = ", ".join(f'"{c}"' for c in pk)
    n = con.execute(
        f"SELECT COUNT(*) FROM read_parquet({globs!r}, union_by_name=true) "
        f"WHERE _seq > ?", [last_seq]).fetchone()[0]
    if not n:
        return None
    return (f"({keys}) IN (SELECT DISTINCT {keys} "
            f"FROM read_parquet({globs!r}, union_by_name=true) "
            f"WHERE _seq > '{last_seq}')")


def _view_exists(con, table: str) -> bool:
    return bool(con.execute(
        "SELECT 1 FROM information_schema.tables "
        "WHERE table_schema='bronze_current' AND table_name=?", [table]).fetchone())


def run(cfg: dict, warehouse: str = "data/warehouse.duckdb",
        bronze: str = "data/bronze", out_dir: str = "data/silver",
        registry_path: str = "config/tables.yaml", full: bool = False,
        run_id: str | None = None) -> dict:
    ns = _ids.make_ns(cfg.get("fhir", {}).get("id_namespace", "sapfhir"))
    pcfg = cfg.get("privacy", {})
    secret = os.environ.get(pcfg.get("secret_env", "SAPFHIR_PRIVACY_SECRET"), "")
    priv = Privacy(mode=pcfg.get("mode", "pseudonymize"), secret=secret,
                   date_shift=pcfg.get("date_shift", True),
                   free_text_deid=pcfg.get("free_text_deid", True),
                   keep_filenames=pcfg.get("keep_filenames", False),
                   gate=pcfg.get("gate", "enforce"))
    loinc = LoincMap(cfg.get("terminology", {}).get("loinc_map"))
    registry = _load(registry_path)["tables"] if os.path.exists(registry_path) else {}
    run_id = run_id or time.strftime("%Y%m%d-%H%M%S")

    con = duckdb.connect(warehouse)
    con.execute(_DDL)
    if registry:
        _merge.create_views(con, registry, bronze)
    # Katalog-Lookups (TN14T/NKDI/NORG/...): Klartexte statt Rohcodes, sobald
    # die Kataloge entladen sind; sonst Fallback auf die verifizierten Enums.
    lookups = Lookups(con)

    w = NdjsonWriter(out_dir, run_id)
    orphans: dict[str, int] = {}
    try:
        for table, (fhir_type, fn, needs_pat) in TABLE_TO_FHIR.items():
            treg = next((r for t, r in registry.items() if t.lower() == table), None)
            if not _view_exists(con, table):
                continue
            # Inkrement: nur geaenderte PKs seit letztem Lauf
            where = ""
            last = con.execute(
                "SELECT MAX(max_seq) FROM silver.silver_runs WHERE table_name=?",
                [table]).fetchone()[0]
            if last is not None and not full and treg:
                flt = _changed_pk_filter(con, bronze, table, treg["pk"], last)
                if flt is None:
                    continue   # keine Aenderungen seit letztem Lauf
                where = f"WHERE {flt}"
            if needs_pat:
                sel = (f'SELECT t.*, f."PATNR" AS _patnr '
                       f'FROM bronze_current."{table}" t '
                       f'LEFT JOIN (SELECT DISTINCT "FALNR", "PATNR" '
                       f'           FROM bronze_current.nfal) f USING ("FALNR") '
                       f'{where}')
            else:
                sel = f'SELECT t.* FROM bronze_current."{table}" t {where}'
            cur = con.execute(sel)
            cols = [c[0] for c in cur.description]
            nrows = 0
            while True:
                rows = cur.fetchmany(10000)
                if not rows:
                    break
                for r in rows:
                    row = {k: (v.isoformat() if hasattr(v, "isoformat") else v)
                           for k, v in zip(cols, r)}
                    patnr = row.pop("_patnr", None) or row.get("PATNR")
                    if needs_pat and not patnr:
                        orphans[table] = orphans.get(table, 0) + 1
                        continue
                    if fn is M.map_observation_labor:
                        res = fn(row, ns, priv, patnr=patnr, loinc=loinc)
                    elif fn in (M.map_encounter_bewegung, M.map_condition):
                        res = fn(row, ns, priv, patnr=patnr, lookups=lookups)
                    elif needs_pat:
                        res = fn(row, ns, priv, patnr=patnr)
                    else:
                        res = fn(row, ns, priv)
                    idx_pat = patnr
                    if idx_pat and priv and priv.mode != "off":
                        idx_pat = priv.pseudonym(idx_pat)
                    for r_out in (res if isinstance(res, list) else [res]):
                        w.write(r_out, patnr=idx_pat)
                        nrows += 1
            max_seq = _delta_max_seq(con, bronze, table) or ""
            con.execute("INSERT INTO silver.silver_runs VALUES (?,?,?,?,now())",
                        [run_id, table, max_seq, nrows])

        # Provenance je Lauf (CONCEPT §16.3)
        prov = {
            "resourceType": "Provenance",
            "id": _ids.rid(ns, "Provenance", run_id),
            "recorded": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "agent": [{"who": {"display": "sapfhir/0.2"}}],
            "entity": [{"role": "source",
                        "what": {"display": f"bronze_current:{t}"}}
                       for t in TABLE_TO_FHIR],
            "meta": {"source": "sapfhir/run"},
        }
        w.write(prov)
    finally:
        w.close()

    if w.index:
        con.executemany("INSERT INTO silver.fhir_index VALUES (?,?,?,?,?,?)",
                        w.index)
    for t, n in orphans.items():
        con.execute("INSERT INTO _meta.orphan_rows VALUES (?,?,?,?)",
                    [run_id, t, None, n])
    con.close()
    return {"run_id": run_id, "counts": w.counts, "orphans": orphans,
            "loinc_coverage": round(loinc.coverage, 3)}


def main(argv=None):
    ap = argparse.ArgumentParser(description="bronze_current -> FHIR NDJSON")
    ap.add_argument("--config", default="config/connection.yaml")
    ap.add_argument("--warehouse", default="data/warehouse.duckdb")
    ap.add_argument("--bronze", default="data/bronze")
    ap.add_argument("--out", dest="out_dir", default="data/silver")
    ap.add_argument("--registry", default="config/tables.yaml")
    ap.add_argument("--full", action="store_true",
                    help="Vollexport (sonst inkrementell seit letztem Lauf)")
    args = ap.parse_args(argv)
    cfg = _load(args.config) if os.path.exists(args.config) else {}
    res = run(cfg, args.warehouse, args.bronze, args.out_dir, args.registry,
              full=args.full)
    print("FHIR-Ausleitung:", json.dumps(res, indent=2))


if __name__ == "__main__":
    main()
