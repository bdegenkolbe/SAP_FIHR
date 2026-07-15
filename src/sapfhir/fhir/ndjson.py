# -*- coding: utf-8 -*-
"""Silver-Layer: liest Bronze-Parquet und leitet FHIR-R4-NDJSON aus (Bulk-Data-Format).

Ein Verzeichnis je Ressourcentyp, gzip-NDJSON. Idempotent ueber stabile uuid5-IDs
(sapfhir.fhir.ids). Kein FHIR-Server noetig; optionaler Import in HAPI/Medplum moeglich.

CLI:
  python -m sapfhir.fhir.ndjson --in data/bronze --out data/silver \
        --config config/connection.yaml
"""
from __future__ import annotations
import argparse
import glob
import gzip
import json
import os

import pyarrow.parquet as pq
import yaml

from . import ids as _ids
from .privacy import Privacy
from .mappers import core as M


def _load(path):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# Bronze-Tabelle -> (FHIR-Typ, Mapper) ; mehrere Mapper je Tabelle moeglich
TABLE_TO_FHIR = {
    "npat": [("Patient", M.map_patient)],
    "nfal": [("Encounter", M.map_encounter)],
    "nbew": [("Encounter", M.map_encounter_bewegung)],
    "ndia": [("Condition", M.map_condition)],
    "nicp": [("Procedure", M.map_procedure)],
    "n2labor": [("Observation", M.map_observation_labor)],
    "ndoc": [("DocumentReference", M.map_document_reference)],
}


class NdjsonWriter:
    def __init__(self, out_dir: str):
        self.out_dir = out_dir
        self._fh: dict[str, "gzip.GzipFile"] = {}
        self.counts: dict[str, int] = {}

    def write(self, res: dict):
        rt = res["resourceType"]
        if rt not in self._fh:
            d = os.path.join(self.out_dir, "fhir", rt)
            os.makedirs(d, exist_ok=True)
            self._fh[rt] = gzip.open(os.path.join(d, "part-0.ndjson.gz"), "wt",
                                     encoding="utf-8")
            self.counts[rt] = 0
        self._fh[rt].write(json.dumps(res, ensure_ascii=False, default=str) + "\n")
        self.counts[rt] += 1

    def close(self):
        for fh in self._fh.values():
            fh.close()


def run(in_dir: str, out_dir: str, cfg: dict):
    ns = _ids.make_ns(cfg.get("fhir", {}).get("id_namespace", "sapfhir"))
    pcfg = cfg.get("privacy", {})
    secret = os.environ.get(pcfg.get("secret_env", "SAPFHIR_PRIVACY_SECRET"), "")
    priv = Privacy(mode=pcfg.get("mode", "pseudonymize"), secret=secret,
                   date_shift=pcfg.get("date_shift", True),
                   free_text_deid=pcfg.get("free_text_deid", True),
                   keep_filenames=pcfg.get("keep_filenames", False),
                   gate=pcfg.get("gate", "enforce"))
    loinc = _load_loinc(cfg)

    w = NdjsonWriter(out_dir)
    try:
        for tdir in sorted(glob.glob(os.path.join(in_dir, "*"))):
            table = os.path.basename(tdir).lower()
            if table not in TABLE_TO_FHIR:
                continue
            files = glob.glob(os.path.join(tdir, "**", "*.parquet"), recursive=True)
            for pf in files:
                for batch in pq.ParquetFile(pf).iter_batches(batch_size=10000):
                    for row in batch.to_pylist():
                        for fhir_type, fn in TABLE_TO_FHIR[table]:
                            if fn is M.map_observation_labor:
                                res = fn(row, ns, priv, loinc)
                            else:
                                res = fn(row, ns, priv)
                            w.write(res)
    finally:
        w.close()
    return w.counts


def _load_loinc(cfg) -> dict:
    p = cfg.get("terminology", {}).get("loinc_map")
    m: dict = {}
    if p and os.path.exists(p):
        import csv
        with open(p, newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                m[r.get("local_code")] = r.get("loinc")
    return m


def main(argv=None):
    ap = argparse.ArgumentParser(description="Bronze -> FHIR NDJSON")
    ap.add_argument("--in", dest="in_dir", default="data/bronze")
    ap.add_argument("--out", dest="out_dir", default="data/silver")
    ap.add_argument("--config", default="config/connection.yaml")
    args = ap.parse_args(argv)
    cfg = _load(args.config) if os.path.exists(args.config) else {}
    counts = run(args.in_dir, args.out_dir, cfg)
    print("FHIR-Ausleitung:", json.dumps(counts, indent=2))


if __name__ == "__main__":
    main()
