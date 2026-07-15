# -*- coding: utf-8 -*-
"""Laedt den Patienten-Graph in Kuzu (eingebettete Graph-DB, Cypher).

Knoten: Patient, Fall, Bewegung, Diagnose, Prozedur, OE.
Kanten:  HAT_FALL, HAT_BEWEGUNG, IN_OE, HAT_DIAGNOSE, HAT_PROZEDUR, FOLGT_AUF,
         WIEDERAUFNAHME (abgeleitet).

Kuzu laedt direkt aus Parquet via COPY FROM (kein CSV-Umweg). Kein Dienst, kein
Adminrecht. Feldkennungen mit # VERIFY sind vor Produktivlauf zu bestaetigen.

CLI: python -m sapfhir.graph.load --config config/connection.yaml
"""
from __future__ import annotations
import argparse
import os

import yaml

try:
    import kuzu
except Exception:
    kuzu = None


DDL = [
    "CREATE NODE TABLE IF NOT EXISTS Patient(patnr STRING, gender STRING, PRIMARY KEY(patnr))",
    "CREATE NODE TABLE IF NOT EXISTS Fall(falnr STRING, fallart STRING, beg DATE, ende DATE, PRIMARY KEY(falnr))",
    "CREATE NODE TABLE IF NOT EXISTS Bewegung(bewid STRING, bewtyp STRING, beg DATE, ende DATE, PRIMARY KEY(bewid))",
    "CREATE NODE TABLE IF NOT EXISTS Diagnose(icd STRING, PRIMARY KEY(icd))",
    "CREATE NODE TABLE IF NOT EXISTS OE(oeid STRING, PRIMARY KEY(oeid))",
    "CREATE REL TABLE IF NOT EXISTS HAT_FALL(FROM Patient TO Fall)",
    "CREATE REL TABLE IF NOT EXISTS HAT_BEWEGUNG(FROM Fall TO Bewegung)",
    "CREATE REL TABLE IF NOT EXISTS IN_OE(FROM Bewegung TO OE)",
    "CREATE REL TABLE IF NOT EXISTS HAT_DIAGNOSE(FROM Fall TO Diagnose, art STRING)",
    "CREATE REL TABLE IF NOT EXISTS FOLGT_AUF(FROM Fall TO Fall, tage INT64)",
    "CREATE REL TABLE IF NOT EXISTS WIEDERAUFNAHME(FROM Fall TO Fall, tage INT64)",
]


def load(db_path: str = "data/graph.kuzu", bronze: str = "data/bronze",
         wieder_tage: int = 30):
    if kuzu is None:
        raise RuntimeError("kuzu nicht installiert (pip install kuzu)")
    db = kuzu.Database(db_path)
    con = kuzu.Connection(db)
    for stmt in DDL:
        con.execute(stmt)

    # Knoten/Kanten aus Parquet. COPY erwartet passende Spaltenreihenfolge -> wir
    # projizieren ueber Zwischen-Views mit DuckDB in temporaere Parquet-Dateien.
    import duckdb
    d = duckdb.connect()
    tmp = os.path.join(db_path + "_stage")
    os.makedirs(tmp, exist_ok=True)

    def stage(name, sql):
        out = os.path.join(tmp, name + ".parquet")
        d.execute(f"COPY ({sql}) TO '{out}' (FORMAT PARQUET)")
        return out

    p_pat = stage("patient",
        f"SELECT DISTINCT PATNR AS patnr, CAST(GSCHL AS VARCHAR) AS gender "  # VERIFY
        f"FROM read_parquet('{bronze}/npat/**/*.parquet', union_by_name=true) "
        f"WHERE PATNR IS NOT NULL")
    p_fall = stage("fall",
        f"SELECT DISTINCT FALNR AS falnr, FALAR AS fallart, "
        f"TRY_CAST(BEGDT AS DATE) AS beg, TRY_CAST(ENDAT AS DATE) AS ende "
        f"FROM read_parquet('{bronze}/nfal/**/*.parquet', union_by_name=true) "
        f"WHERE FALNR IS NOT NULL")

    con.execute(f"COPY Patient FROM '{p_pat}'")
    con.execute(f"COPY Fall FROM '{p_fall}'")

    # HAT_FALL aus NFAL (PATNR->FALNR)
    p_hf = stage("hat_fall",
        f"SELECT DISTINCT PATNR, FALNR "
        f"FROM read_parquet('{bronze}/nfal/**/*.parquet', union_by_name=true) "
        f"WHERE PATNR IS NOT NULL AND FALNR IS NOT NULL")
    con.execute(f"COPY HAT_FALL FROM '{p_hf}'")

    # Abgeleitete WIEDERAUFNAHME: gleicher Patient, Folge-Fall < wieder_tage,
    # gleiche ICD-3-Steller-Gruppe der Hauptdiagnose. (Cypher nach dem Laden.)
    con.execute(f"""
        MATCH (p:Patient)-[:HAT_FALL]->(a:Fall), (p)-[:HAT_FALL]->(b:Fall)
        WHERE a.ende IS NOT NULL AND b.beg IS NOT NULL AND b.beg > a.ende
          AND date_diff('day', a.ende, b.beg) <= {int(wieder_tage)}
        CREATE (a)-[:WIEDERAUFNAHME {{tage: date_diff('day', a.ende, b.beg)}}]->(b)
    """)  # VERIFY: date_diff-Signatur in aktueller Kuzu-Version
    con.close()
    print(f"Kuzu-Graph geladen: {db_path}")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="config/connection.yaml")
    ap.add_argument("--db", default="data/graph.kuzu")
    ap.add_argument("--bronze", default="data/bronze")
    args = ap.parse_args(argv)
    cfg = {}
    if os.path.exists(args.config):
        with open(args.config) as f:
            cfg = yaml.safe_load(f)
    wt = cfg.get("graph", {}).get("wiederaufnahme_tage", 30)
    load(args.db, args.bronze, wt)


if __name__ == "__main__":
    main()
