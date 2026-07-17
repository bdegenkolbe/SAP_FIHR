# -*- coding: utf-8 -*-
"""Silver-Layer v3: bronze_current.* -> FHIR-R4-NDJSON (Bulk-Data-Format).

Pipeline-Reihenfolge je Ressource (verbindlich, s. docs/Analyse_Datenbank.md §7):

    Bronze-Zeile -> Mapper (rohe Werte) -> Date-Shift (Pipeline-Schritt, patientenfix)
                 -> normalize_resource() (ISO-8601, Europe/Berlin) -> NDJSON + Index

Eigenschaften (CONCEPT §16):
- liest ausschliesslich die Merge-Views bronze_current.* (nie Roh-Parquet);
- Kontext-Lookups: FALNR->PATNR (Subject/Shift), FALNR->APXNR (Account-Klammer,
  NAPX_FAL), NKDI-Kodetexte ('<DKAT>|<DKEY>' -> DTEXT1), N2LABOR-Kopf fuer
  N2LABOR001-Werte (Join ueber DVS-Schluessel); NAPX-Koepfe -> Account;
- Date-Shift als Pipeline-Schritt fuer Ressourcen, deren Mapper nicht selbst shiftet
  (NPAT/NFAL shiften intern — dort NICHT doppelt schieben);
- run-basierte Ausleitung, silver.fhir_index, Provenance je Lauf, inkrementell.

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
from .normalize import normalize_resource, DATE_KEYS, PERIOD_PARENTS
from .mappers import core as M
from ..extract import merge as _merge


def _load(path):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# Mapper, die priv-intern bereits shiften (NICHT doppelt schieben!)
_SELF_SHIFTING_SOURCES = {"sapfhir/NPAT", "sapfhir/NFAL"}


def _shift_resource_dates(res: dict, priv, patnr) -> dict:
    """Pipeline-Date-Shift (patientenfix) fuer Ressourcen ohne Mapper-internen Shift.
    Laeuft VOR normalize_resource auf den rohen Werten (Analyse_Datenbank §7)."""
    if not priv or getattr(priv, "mode", "off") == "off" or not patnr:
        return res
    if res.get("meta", {}).get("source") in _SELF_SHIFTING_SOURCES:
        return res

    def walk(node, parent_key=None):
        if isinstance(node, dict):
            for k, v in node.items():
                if isinstance(v, str) and (
                        k in DATE_KEYS and (k not in ("start", "end")
                                            or parent_key in PERIOD_PARENTS)):
                    node[k] = priv.shift(patnr, v)
                else:
                    walk(v, k)
        elif isinstance(node, list):
            for item in node:
                walk(item, parent_key)
    walk(res)
    return res


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


def _view_exists(con, table: str) -> bool:
    return bool(con.execute(
        "SELECT 1 FROM information_schema.tables "
        "WHERE table_schema='bronze_current' AND table_name=?", [table]).fetchone())


def _cols(con, table: str) -> set[str]:
    return {r[0].upper() for r in
            con.execute(f'DESCRIBE bronze_current."{table}"').fetchall()}


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
    globs = _delta_globs(bronze, table)
    if not globs:
        return None
    keys = ", ".join(f't."{c}"' for c in pk)
    n = con.execute(
        f"SELECT COUNT(*) FROM read_parquet({globs!r}, union_by_name=true) "
        f"WHERE _seq > ?", [last_seq]).fetchone()[0]
    if not n:
        return None
    sub_keys = ", ".join(f'"{c}"' for c in pk)
    return (f"({keys}) IN (SELECT DISTINCT {sub_keys} "
            f"FROM read_parquet({globs!r}, union_by_name=true) "
            f"WHERE _seq > '{last_seq}')")


# ---------------------------------------------------------------------------
# Kontext-Lookups (Broadcast, klein genug fuer Memory; Analyse_Datenbank §8.1)
# ---------------------------------------------------------------------------
def _lookup_apxnr(con) -> dict:
    """FALNR -> APXNR (Account-Klammer). NAPX_FAL ist klein (45k Zeilen live)."""
    if not _view_exists(con, "napx_fal"):
        return {}
    return {str(r[0]).strip(): str(r[1]).strip() for r in con.execute(
        "SELECT FALNR, APXNR FROM bronze_current.napx_fal "
        "WHERE COALESCE(STORN,'') IN ('','0')").fetchall()}


def _lookup_kodetext(con) -> dict:
    """NKDI: '<DKAT>|<DKEY>' -> DTEXT1 (SPRAS='D' falls vorhanden). 390k live."""
    if not _view_exists(con, "nkdi"):
        return {}
    cols = _cols(con, "nkdi")
    if not {"DKAT", "DKEY", "DTEXT1"} <= cols:
        return {}
    where = "WHERE COALESCE(SPRAS,'D')='D'" if "SPRAS" in cols else ""
    return {f"{str(r[0]).strip()}|{str(r[1]).strip()}": str(r[2]).strip()
            for r in con.execute(
                f"SELECT DKAT, DKEY, DTEXT1 FROM bronze_current.nkdi {where}"
            ).fetchall() if r[2]}


def _lookup_napx_faelle(con) -> dict:
    """APXNR -> Liste der NAPX_FAL-Zeilen (fuer map_account_napx)."""
    if not _view_exists(con, "napx_fal"):
        return {}
    out: dict[str, list] = {}
    cur = con.execute("SELECT * FROM bronze_current.napx_fal")
    cols = [c[0] for c in cur.description]
    for r in cur.fetchall():
        row = dict(zip(cols, r))
        out.setdefault(str(row.get("APXNR")).strip(), []).append(row)
    return out


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
    registry = _load(registry_path)["tables"] if os.path.exists(registry_path) else {}
    run_id = run_id or time.strftime("%Y%m%d-%H%M%S")

    con = duckdb.connect(warehouse)
    con.execute(_DDL)
    if registry:
        _merge.create_views(con, registry, bronze)

    apx_by_fal = _lookup_apxnr(con)
    kodetext = _lookup_kodetext(con)
    napx_faelle = _lookup_napx_faelle(con)

    # Tabelle -> (mapper, braucht FALNR->PATNR-Join, kwargs-Fabrik)
    PLAN: dict[str, tuple] = {
        "npat":      (M.map_patient, False, None),
        "nfal":      (M.map_encounter, False,
                      lambda row, pat: {"apxnr": apx_by_fal.get(
                          str(row.get("FALNR") or "").strip())}),
        "nbew":      (M.map_encounter_bewegung, True, None),
        "ndia":      (M.map_condition, True,
                      lambda row, pat: {"kodetext": kodetext}),
        "nicp":      (M.map_procedure, True,
                      lambda row, pat: {"patnr": pat}),
        "ndoc":      (M.map_document_reference, False, None),
        "n2labor":   (M.map_diagnosticreport_labor, False, None),
        "nksk":      (M.map_coverage, True, None),
        "ngeb":      (M.map_geburt, False, None),
        "nbau":      (M.map_location_bau, False, None),
        "nrsf":      (M.map_risikofaktor, False, None),
        "n1meorder": (M.map_medicationrequest, False, None),
        "n1corder":  (M.map_servicerequest, False, None),
        "nktr":      (M.map_organization_kostentraeger, False, None),
        "norg":      (M.map_organization_norg, False, None),
        "nper":      (M.map_practitioner_nper, False, None),
        "napx":      (None, False, None),   # Sonderpfad Account (Kopf+Faelle)
        # n2labor001 hat einen Sonderpfad (Header-Join), s.u.
    }

    w = NdjsonWriter(out_dir, run_id)
    orphans: dict[str, int] = {}

    def emit(res, patnr):
        if not res:
            return 0
        n = 0
        for r in (res if isinstance(res, list) else [res]):
            _shift_resource_dates(r, priv, patnr)
            normalize_resource(r)
            idx_pat = patnr
            if idx_pat and priv and priv.mode != "off":
                idx_pat = priv.pseudonym(idx_pat)
            w.write(r, patnr=idx_pat)
            n += 1
        return n

    def incremental_where(table, alias="t"):
        treg = next((r for t, r in registry.items() if t.lower() == table), None)
        last = con.execute(
            "SELECT MAX(max_seq) FROM silver.silver_runs WHERE table_name=?",
            [table]).fetchone()[0]
        if last is None or full or not treg:
            return ""
        flt = _changed_pk_filter(con, bronze, table, treg["pk"], last)
        return None if flt is None else f"WHERE {flt}"

    def record_run(table, nrows):
        con.execute("INSERT INTO silver.silver_runs VALUES (?,?,?,?,now())",
                    [run_id, table, _delta_max_seq(con, bronze, table) or "", nrows])

    try:
        for table, (fn, join_pat, kw_fn) in PLAN.items():
            if not _view_exists(con, table):
                continue
            where = incremental_where(table)
            if where is None:
                continue
            nrows = 0

            if table == "napx":   # Account: Kopf + gruppierte NAPX_FAL-Zeilen
                cur = con.execute(f"SELECT t.* FROM bronze_current.napx t {where}")
                cols = [c[0] for c in cur.description]
                for r in cur.fetchall():
                    kopf = dict(zip(cols, r))
                    faelle = napx_faelle.get(str(kopf.get("APXNR")).strip(), [])
                    nrows += emit(M.map_account_napx(kopf, ns, priv, faelle=faelle),
                                  None)
                record_run(table, nrows)
                continue

            if join_pat and _view_exists(con, "nfal"):
                falnr_col = "FALN1" if table == "ngeb" else "FALNR"
                sel = (f'SELECT t.*, f."PATNR" AS _patnr '
                       f'FROM bronze_current."{table}" t '
                       f'LEFT JOIN (SELECT DISTINCT "FALNR", "PATNR" '
                       f'           FROM bronze_current.nfal) f '
                       f'ON t."{falnr_col}" = f."FALNR" {where}')
            else:
                sel = f'SELECT t.* FROM bronze_current."{table}" t {where}'
            cur = con.execute(sel)
            cols = [c[0] for c in cur.description]
            while True:
                rows = cur.fetchmany(10000)
                if not rows:
                    break
                for r in rows:
                    row = {k: (v.isoformat() if hasattr(v, "isoformat") else v)
                           for k, v in zip(cols, r)}
                    patnr = row.pop("_patnr", None) or row.get("PATNR")
                    if join_pat and not patnr and table in ("nbew", "ndia", "nicp"):
                        orphans[table] = orphans.get(table, 0) + 1
                        continue
                    kwargs = kw_fn(row, patnr) if kw_fn else {}
                    nrows += emit(fn(row, ns, priv, **kwargs), patnr)
            record_run(table, nrows)

        # N2LABOR001-Werte mit N2LABOR-Kopf (DVS-Schluessel-Join, R6/R8)
        if _view_exists(con, "n2labor001") and _view_exists(con, "n2labor"):
            where = incremental_where("n2labor001")
            if where is not None:
                nrows = 0
                sel = (
                    'SELECT t.*, h."N2LAPATNR" AS _h_pat, h."N2LAFALNR" AS _h_fal, '
                    '       h."N2LAEINRI" AS _h_einri, h."N2LADATUM" AS _h_dat, '
                    '       h."N2LATIME" AS _h_time '
                    'FROM bronze_current.n2labor001 t '
                    'LEFT JOIN bronze_current.n2labor h USING '
                    '("DOKAR","DOKNR","DOKVR","DOKTL") ' + (where or ""))
                cur = con.execute(sel)
                cols = [c[0] for c in cur.description]
                while True:
                    rows = cur.fetchmany(10000)
                    if not rows:
                        break
                    for r in rows:
                        row = {k: (v.isoformat() if hasattr(v, "isoformat") else v)
                               for k, v in zip(cols, r)}
                        header = {"N2LAPATNR": row.pop("_h_pat", None),
                                  "N2LAFALNR": row.pop("_h_fal", None),
                                  "N2LAEINRI": row.pop("_h_einri", None),
                                  "N2LADATUM": row.pop("_h_dat", None),
                                  "N2LATIME": row.pop("_h_time", None)}
                        res = M.map_observation_labor(row, ns, priv, header=header)
                        nrows += emit(res, header.get("N2LAPATNR"))
                record_run("n2labor001", nrows)

        # Provenance je Lauf (CONCEPT §16.3)
        prov = {
            "resourceType": "Provenance",
            "id": _ids.rid(ns, "Provenance", run_id),
            "recorded": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "agent": [{"who": {"display": "sapfhir/0.3"}}],
            "entity": [{"role": "source",
                        "what": {"display": f"bronze_current:{t}"}}
                       for t in PLAN],
            "meta": {"source": "sapfhir/run"},
        }
        normalize_resource(prov)
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
    return {"run_id": run_id, "counts": w.counts, "orphans": orphans}


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
