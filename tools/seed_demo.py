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
    napx_fal, napx, nksk, n2labor001 = [], [], [], []
    doc_id = 0
    lab_id = 0
    lnric = 0
    apxnr = 0
    for pi in range(1, args.patienten + 1):
        patnr = f"{7700000+pi:010d}"
        adrnr = f"{880000+pi:08d}"
        npat.append({"MANDT": "100", "PATNR": patnr,
                     "GSCHL": random.choice(["1", "2"]),
                     "GBDAT": f"{random.randint(1940,2010)}-0{random.randint(1,9)}-15",
                     "NNAME": random.choice(NAMEN), "VNAME": random.choice(VORNAMEN),
                     "ADRNR": adrnr, "TODKZ": "", "STORN": "",
                     "ERDAT": "2020-01-01", "UPDAT": "2026-01-01"})
        nadr.append({"MANDT": "100", "ADRNR": adrnr, "ADROB": "NPAT",
                     "STRAS": f"Demoweg {pi}",
                     "PSTLZ": "12345", "ORT01": "Musterstadt", "LAND1": "DE",
                     "ERDAT": "2020-01-01", "UPDAT": "2020-01-01"})
        vorfall_ende = None
        vorfalnr = None
        for fi in range(random.randint(1, 4)):
            falnr = f"{4400000+pi*10+fi:010d}"
            # Wiederaufnahme-Kandidaten: manchmal kurz nach dem Vorfall beginnen
            wiederaufnahme = bool(vorfall_ende and random.random() < 0.2)
            if wiederaufnahme:
                beg = vorfall_ende + dt.timedelta(days=random.randint(3, 25))
            else:
                beg = dt.date(2026, random.randint(1, 6), random.randint(1, 28))
            end = beg + dt.timedelta(days=random.randint(1, 20))
            fal_art = random.choice(["1", "1", "2"])
            icd = random.choice(ICDS)
            nfal.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                         "FALAR": fal_art, "PATNR": patnr,
                         "BEGDT": beg.isoformat(),
                         "ENDDT": end.isoformat() if fal_art == "1" else None,
                         "FACHR": random.choice(OES), "STATU": "E",
                         "ABRKZ": "2", "STASP": "", "STORN": "", "STDAT": None,
                         "ERDAT": beg.isoformat(), "UPDAT": end.isoformat()})
            # formale Fallzusammenfuehrung (NAPX_FAL) fuer einen Teil der
            # Wiederaufnahmen — speist die Graph-Kante FUEHRT_ZUSAMMEN
            if wiederaufnahme and vorfalnr and random.random() < 0.6:
                apxnr += 1
                ax = f"{apxnr:010d}"
                reason = random.choice(["WA", "KO", "RV", "OG"])
                napx.append({"MANDT": "100", "APXNR": ax, "STORN": "",
                             "ERDAT": beg.isoformat(), "UPDAT": beg.isoformat()})
                napx_fal.append({"MANDT": "100", "EINRI": "0001", "APXNR": ax,
                                 "FALNR": vorfalnr, "LEAD": "X",
                                 "REASON": reason, "STORN": "",
                                 "ERDAT": beg.isoformat(), "UPDAT": beg.isoformat()})
                napx_fal.append({"MANDT": "100", "EINRI": "0001", "APXNR": ax,
                                 "FALNR": falnr, "LEAD": "",
                                 "REASON": reason, "STORN": "",
                                 "ERDAT": beg.isoformat(), "UPDAT": beg.isoformat()})
            if fal_art == "1":
                vorfall_ende, vorfalnr = end, falnr
            # Kostenuebernahme (NKSK -> Coverage)
            nksk.append({"MANDT": "100", "BELNR": f"{9900000+pi*10+fi:010d}",
                         "EINRI": "0001", "FALNR": falnr,
                         "KOSTR": random.choice(["0001000101", "0001000202",
                                                 "0009999999"]),
                         "KSTYP": "N", "BEGDT": beg.isoformat(),
                         "ENDDT": end.isoformat(), "STORN": ""})
            # Bewegungskette: Aufnahme -> (Verlegung) -> Entlassung
            # (BEWTY Altbestand-korrigiert: 2=Entlassung, 3=Verlegung)
            oes = random.sample(OES, k=random.randint(1, 2))
            lfd = 0
            for j, oe in enumerate(oes):
                lfd += 1
                b_beg = beg + dt.timedelta(days=j * 2)
                bewty = "1" if j == 0 else "3"
                nbew.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                             "LFDNR": f"{lfd:05d}", "BEWTY": bewty,
                             "BWART": None, "BWGR1": "01",
                             "BWIDT": b_beg.isoformat(),
                             "BWEDT": end.isoformat() if fal_art == "1" else None,
                             "ORGFA": oe, "ORGPF": None, "STORN": "",
                             "ERDAT": b_beg.isoformat()})
            if fal_art == "1":
                lfd += 1
                nbew.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                             "LFDNR": f"{lfd:05d}", "BEWTY": "2",   # Entlassung
                             "BWART": None, "BWGR1": "01",
                             "BWIDT": end.isoformat(), "BWEDT": end.isoformat(),
                             "ORGFA": oes[-1], "ORGPF": None, "STORN": "",
                             "ERDAT": end.isoformat()})
            haupt = random.random() < 0.9
            ndia.append({"MANDT": "100", "EINRI": "0001", "FALNR": falnr,
                         "LFDNR": "001", "DKAT1": "56", "DKEY1": icd,
                         "DKEY2": None, "DITXT": f"Demo-Diagnose {icd}",
                         "DIAGW": "", "DIADT": beg.isoformat(),
                         "KHDIA": "X" if haupt else "", "FHDIA": "X" if haupt else "",
                         "AFDIA": "X", "ENDIA": "X" if fal_art == "1" else "",
                         "EWDIA": "", "BHDIA": "X", "OPDIA": "", "STORN": ""})
            if random.random() < 0.5:
                lnric += 1
                nicp.append({"MANDT": "100", "LNRIC": f"{lnric:010d}",
                             "EINRI": "0001", "FALNR": falnr, "LFDNR": "001",
                             "ICPML": random.choice(OPS), "ICPMK": "36",
                             "BTEXT": "Demo-Prozedur", "LSLOK": "",
                             "BZTOP": "08:30:00", "EZTOP": "10:15:00",
                             "BGDOP": beg.isoformat(), "ENDOP": beg.isoformat(),
                             "ORGFA": oes[0], "ICDAT": beg.isoformat(),
                             "STORN": ""})
            if random.random() < 0.7:
                lab_id += 1
                doknr = f"L{lab_id:08d}"
                n2labor.append({"MANDT": "100", "DOKAR": "LAB", "DOKNR": doknr,
                                "DOKVR": "01", "DOKTL": "000",
                                "N2LAEINRI": "0001", "N2LAPATNR": patnr,
                                "N2LAFALNR": falnr,
                                "N2LADATUM": beg.isoformat(),
                                "N2LATIME": "07:45:00", "N2LASTATUS": "F"})
                for k in range(random.randint(1, 3)):
                    code, txt, einh, lo, hi = random.choice(LABS)
                    wert = round(random.uniform(lo, hi * 1.3), 2)
                    n2labor001.append({
                        "MANDT": "100", "DOKAR": "LAB", "DOKNR": doknr,
                        "DOKVR": "01", "DOKTL": "000", "MUSEQ": f"{k+1:04d}",
                        "N2LEISTID": code, "N2KATTEXT": txt,
                        "N2VALUE": str(wert).replace(".", ","),
                        "N2UNIT": einh, "N2NORMAL": f"{lo}-{hi}",
                        "N2ABNORMAL": "H" if wert > hi else "",
                        "N2DATE": beg.isoformat(), "N2TIME": "07:45:00",
                        "N2VSTATUS": "F"})
            if random.random() < 0.6:
                doc_id += 1
                doknr = f"D{doc_id:08d}"
                ndoc.append({"MANDT": "100", "EINRI": "0001", "DOKAR": "MED",
                             "DOKNR": doknr, "DOKVR": "01", "DOKTL": "000",
                             "LFDDOK": "0001", "PATNR": patnr, "FALNR": falnr,
                             "DTID": "ARZ", "MEDOK": "X", "MITARB": "",
                             "ORGDO": oes[0], "DODAT": end.isoformat(),
                             "DOTIM": "12:00:00", "STORN": "", "LOEKZ": ""})
                n2text.append({"MANDT": "100", "DOKAR": "MED", "DOKNR": doknr,
                               "DOKVR": "01", "DOKTL": "000", "DOKTAB": "TXT",
                               "DOKFLD": "TEXT", "DOKOCC": "0001",
                               "TXT": (
                                   f"Entlassbrief (fiktiv). Diagnose {icd}. "
                                   f"Aufenthalt {beg} bis {end} auf {oes[0]}. "
                                   f"Verlauf unauffaellig, Demo-Datensatz.")})

    _w("npat", npat, part_date="ERDAT")
    _w("nadr", nadr)
    _w("nfal", nfal, part_date="BEGDT")
    _w("nbew", nbew, part_date="BWIDT")
    _w("ndia", ndia, part_date="DIADT")
    _w("nicp", nicp, part_date="BGDOP")
    _w("n2labor", n2labor)
    _w("ndoc", ndoc)
    _w("n2text", n2text)
    _w("napx", napx)
    _w("napx_fal", napx_fal)
    _w("nksk", nksk)
    _w("n2labor001", n2labor001)

    # Katalogtabellen (Referenzschicht) — speisen die Lookup-Schicht (fhir/lookups.py)
    _w("tn14t", [{"MANDT": "100", "SPRAS": "D", "EINRI": "0001", "BEWTY": b, "BEWTX": t}
                 for b, t in [("1", "Aufnahme"), ("2", "Entlassung"),
                              ("3", "interne Verlegung"), ("4", "ambulanter Besuch"),
                              ("6", "Beurlaubung Beginn"), ("7", "Beurlaubung Ende")]])
    _w("norg", [{"MANDT": "100", "EINRI": "0001", "ORGID": o, "ORGNA": n}
                for o, n in [("KARD", "Klinik fuer Kardiologie"),
                             ("UCHIR", "Klinik fuer Unfallchirurgie"),
                             ("NEUR", "Klinik fuer Neurologie"),
                             ("INN", "Klinik fuer Innere Medizin"),
                             ("GYN", "Klinik fuer Gynaekologie")]])

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
                 ("N2TEXT", len(n2text)), ("NAPX", len(napx)),
                 ("NAPX_FAL", len(napx_fal)), ("NKSK", len(nksk)),
                 ("N2LABOR001", len(n2labor001))]:
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
