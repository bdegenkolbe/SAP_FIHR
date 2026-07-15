# -*- coding: utf-8 -*-
"""Erzeugt eine synthetische DuckDB + Parquet-Bronze mit fiktiven Daten, damit
Dashboard und MCP-Server ohne Praxis-/Klinik-DB testbar sind. Keine echten Daten.

Ausfuehren: python tools/seed_demo.py
"""
import os
import random
import datetime as dt

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq

random.seed(42)
BASE = "data/bronze"
ICDS = ["I50.14", "I63.5", "J18.9", "F10.3", "S72.0", "Z38.0"]
OPS = ["8-800.c0", "5-820.00", "1-632.0", "8-831.0"]


def _w(table, rows, part_date=None):
    d = os.path.join(BASE, table)
    if part_date:
        years = {}
        for r in rows:
            years.setdefault(str(r.get(part_date, "2026"))[:4], []).append(r)
        for y, rs in years.items():
            os.makedirs(os.path.join(d, f"jahr={y}"), exist_ok=True)
            pq.write_table(pa.Table.from_pylist(rs),
                           os.path.join(d, f"jahr={y}", "part-0.parquet"))
    else:
        os.makedirs(d, exist_ok=True)
        pq.write_table(pa.Table.from_pylist(rows),
                       os.path.join(d, "part-0.parquet"))


def main():
    npat, nfal, nbew, ndia, nicp = [], [], [], [], []
    for pi in range(1, 501):
        patnr = f"{7700000+pi:010d}"
        npat.append({"MANDT": "100", "PATNR": patnr,
                     "GSCHL": random.choice(["1", "2"]),
                     "GBDAT": f"{random.randint(1940,2010)}-0{random.randint(1,9)}-15"})
        for fi in range(random.randint(1, 4)):
            falnr = f"{4400000+pi*10+fi:010d}"
            beg = dt.date(2026, random.randint(1, 6), random.randint(1, 28))
            end = beg + dt.timedelta(days=random.randint(1, 20))
            fal_art = random.choice(["1", "1", "2"])
            nfal.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                         "FALAR": fal_art, "PATNR": patnr,
                         "BEGDT": beg.isoformat(),
                         "ENDAT": end.isoformat() if fal_art == "1" else None,
                         "STORN": "", "UPDAT": end.isoformat()})
            nbew.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                         "LFDNR": "00001", "BEWTY": "1",
                         "BWIDT": beg.isoformat(),
                         "BWEDT": end.isoformat() if fal_art == "1" else None,
                         "ORGFA": random.choice(["KARD", "UCHIR", "NEUR", "INN"]),
                         "ORGPF": None, "STORN": "", "ERDAT": beg.isoformat()})
            ndia.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                         "LFDNR": "001", "DKEY1": random.choice(ICDS),
                         "DIADT": beg.isoformat(), "STORN": ""})
            if random.random() < 0.5:
                nicp.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                             "LFDNR": "001", "ICPML": random.choice(OPS),
                             "ICDAT": beg.isoformat()})
    _w("npat", npat)
    _w("nfal", nfal, part_date="BEGDT")
    _w("nbew", nbew, part_date="BWIDT")
    _w("ndia", ndia, part_date="DIADT")
    _w("nicp", nicp, part_date="ICDAT")
    # leerer Platzhalter, damit die Gold-View gold.casemix (NDRG) baubar ist
    _w("ndrg", [{"MANDT": "100", "EINRI": "0001", "FALNR": "0", "LFDNR": "0",
                 "UPDAT": "2026-01-01"}])

    con = duckdb.connect("data/warehouse.duckdb")
    con.execute(open(os.path.join("src", "sapfhir", "gold", "marts.sql")).read())
    con.execute("CREATE SCHEMA IF NOT EXISTS _meta;"
                "CREATE TABLE IF NOT EXISTS _meta.extract_state("
                "schema_name VARCHAR, table_name VARCHAR, phase VARCHAR,"
                "keyset_cursor VARCHAR, change_seq VARCHAR, rows_seen BIGINT,"
                "last_run_ts TIMESTAMP, last_duration DOUBLE);")
    for t, n in [("NPAT", len(npat)), ("NFAL", len(nfal)), ("NBEW", len(nbew)),
                 ("NDIA", len(ndia)), ("NICP", len(nicp))]:
        con.execute("INSERT INTO _meta.extract_state VALUES "
                    "('sap',?,'backfill',NULL,NULL,?,now(),1.0)", [t, n])
    con.close()
    print(f"Demo erzeugt: {len(npat)} Patienten, {len(nfal)} Faelle. "
          f"Start: python -m sapfhir.api.app")


if __name__ == "__main__":
    main()
