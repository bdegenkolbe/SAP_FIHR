# -*- coding: utf-8 -*-
"""Erzeugt eine synthetische Parquet-Bronze mit fiktiven Daten, damit die komplette
Pipeline (Merge -> FHIR -> Gold -> Graph -> Dashboard -> MCP) ohne Klinik-DB
verprobbar ist. KEINE echten Daten.

Enthaelt bewusst auch CDC-Deltas (1 Update, 1 Delete), damit der Merge-Layer
(bronze_current, CONCEPT §14) sichtbar arbeitet.

Ausfuehren:
  python tools/seed_demo.py               # nur Bronze + State erzeugen
  python tools/seed_demo.py --pipeline    # + Merge, FHIR, Gold, Graph in einem Zug
"""
import argparse
import os
import random
import sys
import datetime as dt

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

random.seed(42)
BASE = "data/bronze"
ICDS = ["I50.14", "I63.5", "J18.9", "F10.3", "S72.0", "Z38.0", "I50.13", "J44.1"]
OPS = ["8-800.c0", "5-820.00", "1-632.0", "8-831.0", "5-790.13"]
OES = ["KARD", "UCHIR", "NEUR", "INN", "GYN"]
LABS = [("KREA", "Kreatinin", "mg/dl", 0.6, 1.4), ("HB", "Haemoglobin", "g/dl", 12, 17),
        ("CRP", "CRP", "mg/l", 0, 5), ("LEUK", "Leukozyten", "/nl", 4, 10)]
NAMEN = ["Muster", "Beispiel", "Fiktiv", "Demo", "Test", "Probe"]
VORNAMEN = ["Alex", "Kim", "Chris", "Robin", "Sam", "Toni"]


def _w(table, rows, part_date=None):
    d = os.path.join(BASE, table)
    if part_date:
        years = {}
        for r in rows:
            years.setdefault(str(r.get(part_date) or "unknown")[:4], []).append(r)
        for y, rs in years.items():
            os.makedirs(os.path.join(d, f"jahr={y}"), exist_ok=True)
            pq.write_table(pa.Table.from_pylist(rs),
                           os.path.join(d, f"jahr={y}", "part-0.parquet"))
    else:
        os.makedirs(d, exist_ok=True)
        pq.write_table(pa.Table.from_pylist(rows),
                       os.path.join(d, "part-0.parquet"))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--pipeline", action="store_true",
                    help="nach dem Seed direkt Merge+FHIR+Gold+Graph bauen")
    ap.add_argument("--patienten", type=int, default=500)
    args = ap.parse_args(argv)

    npat, nadr, nfal, nbew, ndia, nicp, n2labor, ndoc, n2text = \
        [], [], [], [], [], [], [], [], []
    doc_id = 0
    for pi in range(1, args.patienten + 1):
        patnr = f"{7700000+pi:010d}"
        adrnr = f"{880000+pi:08d}"
        npat.append({"MANDT": "100", "PATNR": patnr,
                     "GSCHL": random.choice(["1", "2"]),
                     "GBDAT": f"{random.randint(1940,2010)}-0{random.randint(1,9)}-15",
                     "NNAME": random.choice(NAMEN), "VNAME": random.choice(VORNAMEN),
                     "ADRNR": adrnr, "TODKZ": "", "STORN": "",
                     "ERDAT": "2020-01-01", "UPDAT": "2026-01-01"})
        nadr.append({"MANDT": "100", "ADRNR": adrnr, "STRAS": f"Demoweg {pi}",
                     "PSTLZ": "12345", "ORT01": "Musterstadt", "LAND1": "DE",
                     "ERDAT": "2020-01-01", "UPDAT": "2020-01-01"})
        vorfall_ende = None
        for fi in range(random.randint(1, 4)):
            falnr = f"{4400000+pi*10+fi:010d}"
            # Wiederaufnahme-Kandidaten: manchmal kurz nach dem Vorfall beginnen
            if vorfall_ende and random.random() < 0.2:
                beg = vorfall_ende + dt.timedelta(days=random.randint(3, 25))
            else:
                beg = dt.date(2026, random.randint(1, 6), random.randint(1, 28))
            end = beg + dt.timedelta(days=random.randint(1, 20))
            fal_art = random.choice(["1", "1", "2"])
            icd = random.choice(ICDS)
            nfal.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                         "FALAR": fal_art, "PATNR": patnr,
                         "BEGDT": beg.isoformat(),
                         "ENDAT": end.isoformat() if fal_art == "1" else None,
                         "FACHR": random.choice(OES), "STORN": "",
                         "ERDAT": beg.isoformat(), "UPDAT": end.isoformat()})
            vorfall_ende = end if fal_art == "1" else vorfall_ende
            # Bewegungskette: Aufnahme -> (Verlegung) -> Entlassung
            oes = random.sample(OES, k=random.randint(1, 2))
            lfd = 0
            for j, oe in enumerate(oes):
                lfd += 1
                b_beg = beg + dt.timedelta(days=j * 2)
                nbew.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                             "LFDNR": f"{lfd:05d}",
                             "BEWTY": "1" if j == 0 else "2",
                             "BWIDT": b_beg.isoformat(),
                             "BWEDT": end.isoformat() if fal_art == "1" else None,
                             "ORGFA": oe, "ORGPF": None, "STORN": "",
                             "ERDAT": b_beg.isoformat()})
            ndia.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                         "LFDNR": "001", "DKEY1": icd,
                         "DIADT": beg.isoformat(), "DIATX": None, "STORN": ""})
            if random.random() < 0.5:
                nicp.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                             "LFDNR": "001", "ICPML": random.choice(OPS),
                             "ICPK1": None, "ICDAT": beg.isoformat(), "STORN": ""})
            for k in range(random.randint(0, 3)):
                code, txt, einh, lo, hi = random.choice(LABS)
                n2labor.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                                "LFDNR": f"{k+1:03d}", "PARCD": code, "PARTX": txt,
                                "WERT": str(round(random.uniform(lo, hi * 1.3), 2)),
                                "EINH": einh, "REFBER": f"{lo}-{hi}",
                                "BEFDT": beg.isoformat(), "STORN": ""})
            if random.random() < 0.6:
                doc_id += 1
                did = f"D{doc_id:08d}"
                ndoc.append({"MANDT": "100", "EINRI": "0001", "DOCID": did,
                             "FALNR": falnr, "PATNR": patnr, "DOCTY": "ARZTBRIEF",
                             "DOCKA": "BRIEF", "DOCDT": end.isoformat(),
                             "STORN": ""})
                n2text.append({"MANDT": "100", "EINRI": "0001",
                               "TEXTID": f"T{doc_id:08d}", "DOCID": did,
                               "FALNR": falnr, "PATNR": patnr,
                               "TEXTINHALT": (
                                   f"Entlassbrief (fiktiv). Diagnose {icd}. "
                                   f"Aufenthalt {beg} bis {end} auf {oes[0]}. "
                                   f"Verlauf unauffaellig, Demo-Datensatz.")})

    _w("npat", npat, part_date="ERDAT")
    _w("nadr", nadr)
    _w("nfal", nfal, part_date="BEGDT")
    _w("nbew", nbew, part_date="BWIDT")
    _w("ndia", ndia, part_date="DIADT")
    _w("nicp", nicp, part_date="ICDAT")
    _w("n2labor", n2labor)
    _w("ndoc", ndoc)
    _w("n2text", n2text)

    # --- CDC-Delta-Beispiel: 1 Fall verlaengert (U), 1 Fall geloescht (D) ----
    d0, d1 = nfal[0].copy(), nfal[1].copy()
    d0["ENDAT"] = "2026-06-30"; d0["_op"] = "U"; d0["_seq"] = "20260715000000001"
    d1["_op"] = "D"; d1["_seq"] = "20260715000000002"
    delta_dir = os.path.join(BASE, "_delta", "nfal")
    os.makedirs(delta_dir, exist_ok=True)
    pq.write_table(pa.Table.from_pylist([d0, d1]),
                   os.path.join(delta_dir, "seq-demo.parquet"))

    # Extract-State (Quelle der Monitor-/Reconciliation-Kacheln)
    con = duckdb.connect("data/warehouse.duckdb")
    con.execute("CREATE SCHEMA IF NOT EXISTS _meta;"
                "CREATE TABLE IF NOT EXISTS _meta.extract_state("
                "schema_name VARCHAR, table_name VARCHAR, phase VARCHAR,"
                "keyset_cursor VARCHAR, change_seq VARCHAR, rows_seen BIGINT,"
                "last_run_ts TIMESTAMP, last_duration DOUBLE,"
                "PRIMARY KEY (schema_name, table_name, phase));"
                "CREATE TABLE IF NOT EXISTS _meta.run_log ("
                "ts TIMESTAMP, schema_name VARCHAR, table_name VARCHAR,"
                "phase VARCHAR, rows BIGINT, duration DOUBLE, note VARCHAR);")
    con.execute("DELETE FROM _meta.extract_state")
    for t, n in [("NPAT", len(npat)), ("NADR", len(nadr)), ("NFAL", len(nfal)),
                 ("NBEW", len(nbew)), ("NDIA", len(ndia)), ("NICP", len(nicp)),
                 ("N2LABOR", len(n2labor)), ("NDOC", len(ndoc)),
                 ("N2TEXT", len(n2text))]:
        con.execute("INSERT INTO _meta.extract_state VALUES "
                    "('sap',?,'backfill',NULL,NULL,?,now(),1.0)", [t, n])
    con.execute("INSERT INTO _meta.extract_state VALUES "
                "('sap','NFAL','cdc',NULL,'20260715000000002',2,now(),0.1)")
    con.close()
    print(f"Demo erzeugt: {len(npat)} Patienten, {len(nfal)} Faelle, "
          f"{len(nbew)} Bewegungen, {len(n2labor)} Laborwerte, "
          f"{len(ndoc)} Dokumente + 2 CDC-Deltas (1 Update, 1 Delete).")

    if args.pipeline:
        from sapfhir.fhir import ndjson as _ndjson
        from sapfhir.gold import build as _gold
        from sapfhir.graph import load as _graph
        print("\n[1/3] FHIR-Ausleitung (inkl. bronze_current-Merge) ...")
        res = _ndjson.run({}, full=True)
        print(f"      Ressourcen: {res['counts']}")
        print("[2/3] Gold-Marts + FTS + mcp.*-Views + DQ ...")
        _gold.build()
        print("[3/3] Kuzu-Graph ...")
        try:
            _graph.load()
        except RuntimeError as e:
            print(f"      Graph uebersprungen: {e}")
        print("\nFertig. Dashboard:  python -m sapfhir.api.app"
              "\n        MCP:        python -m sapfhir.mcp.server")
    else:
        print("Pipeline bauen:  python tools/seed_demo.py --pipeline"
              "\noder einzeln:    python -m sapfhir.fhir.ndjson --full && "
              "python -m sapfhir.gold.build && python -m sapfhir.graph.load")


if __name__ == "__main__":
    main()
