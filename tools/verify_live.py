# -*- coding: utf-8 -*-
"""Sammelt ALLE offenen Live-Verifikationen in einem read-only-Lauf gegen die
Replika und schreibt einen Bericht (Markdown + JSON) zum Hochladen/Review.

Ausfuehren im Klinik-/Analytiknetz (dauert wenige Minuten, nur TOP-/COUNT-Queries):

    python tools/verify_live.py --config config/connection.yaml
    -> data/verify_live_report.md  +  data/verify_live_report.json

Deckt ab (Stand nach VERIFY_RESULTS_4 / ALTBESTAND_ANALYSE):
  1. Registry-/PK-Abgleich aller tables.yaml-Eintraege (INFORMATION_SCHEMA)
  2. Fuellstaende der neu aufgenommenen Tabellen (Kataloge, NKSK, NGEB, NBAU, ...)
  3. Spaltenlisten + TOP-20-Stichproben der Katalogtabellen
     (TN14T/TN14R/TN14U/TN14W/TN24T/NKDI) -> finale Lookup-Spaltennamen
  4. NDOC-Dokumentkategorien-Verteilung + N2TEXT-Struktur (Arztbrief-Frage)
  5. SOOD/SRGBTBREL-Fuellstand (SAP-Office als Arztbrief-Pfad, DIAS-Befund)
  6. NC301S-Struktur + Fuellstand (einzige aktiv genutzte NC301-Tabelle)
  7. N2LABOR-Spalten (PARCD/WERT/EINH offen aus Runde 1)
  8. Qlik-__ct-Spannen (min/max change_seq) der Tier-1-Tabellen -> Retention
"""
from __future__ import annotations
import argparse
import json
import os
import sys

import yaml

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from sapfhir.extract.dbsource import Source  # noqa: E402

KATALOGE = ["TN14T", "TN14R", "TN14U", "TN14W", "TN14B", "TN14V",
            "TN24", "TN24T", "NKDI", "TNK00", "TN10S", "TN10B", "TN10H", "NOEK"]
NEUE_TABELLEN = ["NKSK", "NKSD", "NGEB", "NBAU", "NAPX", "NAPX_FAL", "NAPX_BEW",
                 "NAPX_DIA", "NAPX_ICP", "NGPA", "NKTR", "NPER", "NEHC", "NKSP",
                 "N2OPDIAGNOSEN", "NC301S", "SOOD", "SRGBTBREL", "N2LABOR"]
TIER1_CT = ["NPAT", "NFAL", "NBEW", "NDIA", "NICP", "N2LABOR", "NDOC", "N2TEXT",
            "NKSK", "NAPX_FAL"]


def _cols(src, table):
    return [r["COLUMN_NAME"] for r in src.query(
        "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS "
        "WHERE TABLE_SCHEMA='sap' AND TABLE_NAME=? ORDER BY ORDINAL_POSITION",
        (table,))]


def _count(src, table):
    try:
        return src.scalar(
            "SELECT SUM(p.rows) FROM sys.tables t "
            "JOIN sys.schemas s ON t.schema_id=s.schema_id "
            "JOIN sys.partitions p ON t.object_id=p.object_id AND p.index_id IN (0,1) "
            "WHERE s.name='sap' AND t.name=?", (table,))
    except Exception as e:
        return f"ERR: {e}"


def _sample(src, table, n=20):
    try:
        return src.query(f"SELECT TOP {int(n)} * FROM sap.[{table}]")
    except Exception as e:
        return [{"ERROR": str(e)}]


def run(cfg_path: str, out_dir: str = "data") -> dict:
    with open(cfg_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    with open("config/tables.yaml", encoding="utf-8") as f:
        registry = yaml.safe_load(f)["tables"]

    rep: dict = {}
    src = Source(cfg["source"]).connect()
    try:
        print("[1/8] Verbindungs-/Rechte-Check ...")
        rep["check"] = src.check()

        print("[2/8] Registry-/PK-Abgleich ...")
        rep["registry"] = src.check_registry(registry)

        print("[3/8] Fuellstaende neue Tabellen ...")
        rep["counts"] = {t: _count(src, t) for t in NEUE_TABELLEN + KATALOGE}

        print("[4/8] Katalog-Strukturen + Stichproben ...")
        rep["kataloge"] = {t: {"columns": _cols(src, t),
                               "sample": _sample(src, t)}
                           for t in KATALOGE if _cols(src, t)}

        print("[5/8] NDOC-Kategorien / N2TEXT (Arztbrief-Frage) ...")
        rep["ndoc_spalten"] = _cols(src, "NDOC")
        for col in ("DOCKA", "DOCTY", "DOKAR"):   # Kandidaten fuer Kategorie
            if col in rep["ndoc_spalten"]:
                rep[f"ndoc_verteilung_{col}"] = src.query(
                    f"SELECT TOP 50 [{col}], COUNT(*) AS n FROM sap.NDOC "
                    f"GROUP BY [{col}] ORDER BY n DESC")
        rep["n2text_spalten"] = _cols(src, "N2TEXT")

        print("[6/8] SOOD/SRGBTBREL (SAP-Office-Dokumente) ...")
        rep["sood"] = {"columns": _cols(src, "SOOD"), "rows": _count(src, "SOOD")}
        rep["srgbtbrel"] = {"columns": _cols(src, "SRGBTBREL"),
                            "rows": _count(src, "SRGBTBREL")}

        print("[7/8] NC301S + N2LABOR Strukturen ...")
        rep["nc301s"] = {"columns": _cols(src, "NC301S"),
                         "rows": _count(src, "NC301S"),
                         "sample": _sample(src, "NC301S", 5)}
        rep["n2labor_spalten"] = _cols(src, "N2LABOR")
        rep["n2labor_sample"] = _sample(src, "N2LABOR", 5)

        print("[8/8] __ct-Spannen (Retention) ...")
        rep["ct_spannen"] = {}
        for t in TIER1_CT:
            rep["ct_spannen"][t] = {"min": src.min_change_seq("sap", t),
                                    "max": src.max_change_seq("sap", t)}
    finally:
        src.close()

    os.makedirs(out_dir, exist_ok=True)
    jpath = os.path.join(out_dir, "verify_live_report.json")
    with open(jpath, "w", encoding="utf-8") as f:
        json.dump(rep, f, ensure_ascii=False, indent=2, default=str)

    mpath = os.path.join(out_dir, "verify_live_report.md")
    with open(mpath, "w", encoding="utf-8") as f:
        f.write("# SAP_FIHR — Live-Verifikationsbericht\n\n")
        f.write("## 1. Verbindung/Rechte\n```json\n"
                + json.dumps(rep["check"], indent=2, default=str) + "\n```\n")
        f.write("\n## 2. Registry-/PK-Abgleich (nur Abweichungen)\n\n")
        for t, r in sorted(rep["registry"].items()):
            if not r.get("exists"):
                f.write(f"- **{t}: existiert nicht!**\n")
            elif not r.get("pk_ok") or r.get("missing_proj_cols"):
                f.write(f"- **{t}**: db_pk={r.get('db_pk')} "
                        f"missing_pk={r.get('missing_pk_cols')} "
                        f"missing_proj={r.get('missing_proj_cols')}\n")
        f.write("\n## 3. Fuellstaende\n\n| Tabelle | Zeilen |\n|---|---:|\n")
        for t, n in sorted(rep["counts"].items(),
                           key=lambda kv: -(kv[1] if isinstance(kv[1], int) else -1)):
            f.write(f"| {t} | {n} |\n")
        f.write("\n## 4. Katalog-Spalten\n\n")
        for t, k in rep["kataloge"].items():
            f.write(f"- **{t}**: {', '.join(k['columns'])}\n")
        for key in ("ndoc_verteilung_DOCKA", "ndoc_verteilung_DOCTY",
                    "ndoc_verteilung_DOKAR"):
            if key in rep:
                f.write(f"\n## {key}\n```json\n"
                        + json.dumps(rep[key][:20], indent=2, default=str) + "\n```\n")
        f.write("\n## SOOD/SRGBTBREL\n"
                f"- SOOD: {rep['sood']['rows']} Zeilen\n"
                f"- SRGBTBREL: {rep['srgbtbrel']['rows']} Zeilen\n")
        f.write("\n## NC301S\n"
                f"- {rep['nc301s']['rows']} Zeilen, Spalten: "
                f"{', '.join(rep['nc301s']['columns'] or ['-'])}\n")
        f.write("\n## N2LABOR-Spalten\n- "
                + ", ".join(rep["n2labor_spalten"] or ["-"]) + "\n")
        f.write("\n## __ct-Spannen (Retention-Check)\n\n"
                "| Tabelle | min seq | max seq |\n|---|---|---|\n")
        for t, s in rep["ct_spannen"].items():
            f.write(f"| {t} | {s['min']} | {s['max']} |\n")

    print(f"\nBericht: {mpath}  +  {jpath}")
    print("Beide Dateien bitte fuer die naechste Runde hochladen "
          "(enthalten KEINE Patientendaten — nur Strukturen, Zaehlwerte und "
          "Katalog-Stichproben; NDOC/N2LABOR-Samples vor Weitergabe pruefen!).")
    return rep


def main(argv=None):
    ap = argparse.ArgumentParser(description="Live-Verifikationslauf (read-only)")
    ap.add_argument("--config", default="config/connection.yaml")
    ap.add_argument("--out", default="data")
    args = ap.parse_args(argv)
    run(args.config, args.out)


if __name__ == "__main__":
    main()
