# -*- coding: utf-8 -*-
"""Sammelt die OFFENEN Live-Verifikationen (Stand GESAMTREVIEW §4, nach R16) in
einem read-only-Lauf gegen die Replika und schreibt einen Bericht (MD + JSON).

Ausfuehren im Klinik-/Analytiknetz — idealerweise im LASTFENSTER (Punkt 2/4
scannen grosse Tabellen):

    python tools/verify_live.py --config config/connection.yaml
    -> data/verify_live_report.md  +  data/verify_live_report.json

Deckt ab (Nummern = GESAMTREVIEW §4):
  A. PK-Uniqueness der neuen Registry-Kandidaten (#3): NAPX_BEW/DIA/ICP/DRG,
     NTMN, TNDRG (+ alle noch offenen # VERIFY-PKs der Registry)
  B. NICP<->N1LSTEAM-Joinpfad (#2): Deckungsgrade der Kandidatenpfade
     (NICP.LFDBEW->NLEI und N2OPDIAGNOSEN.LNRLS)
  C. SOOD/SRGBTBREL-Audit (#4): Struktur, Fuellstand, Objekttyp-Verteilung
     (Arztbrief-Pfad; KEINE Inhalte — Verkryptungsregel §4)
  D. NFFZ-REFA-Verteilung (#6): Paar-Kombinationen fuer die Q/T/S-Deutung
  E. Katalog-Strukturen TN14U/TN14W/TN24T/TNDRG (Lookup-Spaltennamen final)
  F. Fill-Audit NDOC-Kernfelder (54 Mio — nur SUM/CASE, ein Scan)

Verkryptungsregel (Analyse_Datenbank §4) ist eingehalten: keine Namen, keine
Freitexte, keine EDIFACT-Inhalte — nur Zaehlwerte, Schluessel und Codes.
"""
from __future__ import annotations
import argparse
import json
import os
import sys

import yaml

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from sapfhir.extract.dbsource import Source  # noqa: E402

# A: Registry-Kandidaten mit noch unverifiziertem PK
PK_KANDIDATEN = {
    "NAPX_BEW": ["MANDT", "EINRI", "APXNR", "LFDBEW_NEW"],
    "NAPX_DIA": ["MANDT", "APXNR", "LFDNR_NEW"],
    "NAPX_ICP": ["MANDT", "APXNR", "LNRIC"],
    "NAPX_DRG": ["MANDT", "APXNR"],
    "NTMN":     ["MANDT", "EINRI", "TMNID"],
    "TNDRG":    ["MANDT", "DRG"],
    "TN14U":    ["MANDT", "EINRI", "BEWTY", "BWART"],
    "TN14W":    ["MANDT", "ENTLZ"],
    "TN24T":    ["MANDT", "BEKAT"],
}


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


def _uniq(src, table, pk):
    """PK-Uniqueness: COUNT(*) vs COUNT(DISTINCT CONCAT(pk))."""
    cols = set(_cols(src, table))
    missing = [c for c in pk if c not in cols]
    if missing:
        return {"ok": False, "missing_cols": missing, "spalten": sorted(cols)}
    concat = "CONCAT(" + ", '|', ".join(f"[{c}]" for c in pk) + ")"
    try:
        r = src.query(f"SELECT COUNT(*) AS n, COUNT(DISTINCT {concat}) AS d "
                      f"FROM sap.[{table}]")[0]
        return {"ok": r["n"] == r["d"], "n": r["n"], "d": r["d"]}
    except Exception as e:
        return {"ok": False, "err": str(e)}


def run(cfg_path: str, out_dir: str = "data") -> dict:
    with open(cfg_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    rep: dict = {}
    src = Source(cfg["source"]).connect()
    try:
        print("[A] PK-Uniqueness der Registry-Kandidaten ...")
        rep["pk_checks"] = {t: _uniq(src, t, pk)
                            for t, pk in PK_KANDIDATEN.items()}

        print("[B] NICP<->N1LSTEAM-Joinpfade (#2, LASTFENSTER!) ...")
        rep["nicp_lfdbew_belegt"] = src.scalar(
            "SELECT COUNT(*) FROM sap.NICP WHERE LTRIM(RTRIM(ISNULL(LFDBEW,'')))"
            " NOT IN ('','0','00000')")
        rep["nicp_gesamt"] = _count(src, "NICP")
        # Kandidatenpfad ueber N2OPDIAGNOSEN (LNRLS -> N1LSTEAM.LNRLS)
        rep["n2opdiag_spalten"] = _cols(src, "N2OPDIAGNOSEN")
        try:
            rep["n2opdiag_lnrls_in_lsteam"] = src.query(
                "SELECT TOP 1 COUNT(*) AS gesamt, "
                "SUM(CASE WHEN t.LNRLS IS NOT NULL THEN 1 ELSE 0 END) AS treffer "
                "FROM (SELECT TOP 100000 LNRLS FROM sap.N2OPDIAGNOSEN "
                "      WHERE LNRLS IS NOT NULL) o "
                "LEFT JOIN (SELECT DISTINCT LNRLS FROM sap.N1LSTEAM) t "
                "  ON o.LNRLS = t.LNRLS")
        except Exception as e:
            rep["n2opdiag_lnrls_in_lsteam"] = f"ERR: {e}"

        print("[C] SOOD/SRGBTBREL (#4, Arztbrief-Pfad) ...")
        for t in ("SOOD", "SRGBTBREL"):
            rep[t.lower()] = {"columns": _cols(src, t), "rows": _count(src, t)}
        # Objekttyp-Verteilung der Relationen (welche IS-H-Objekte haengen an Docs?)
        try:
            rep["srgbtbrel_typen"] = src.query(
                "SELECT TOP 25 TYPEID_A, TYPEID_B, COUNT(*) AS n "
                "FROM sap.SRGBTBREL GROUP BY TYPEID_A, TYPEID_B "
                "ORDER BY n DESC")
        except Exception as e:
            rep["srgbtbrel_typen"] = f"ERR: {e}"

        print("[D] NFFZ-REFA-Paarverteilung (#6) ...")
        try:
            rep["nffz_refa"] = src.query(
                "SELECT REFA1, REFA2, COUNT(*) AS n FROM sap.NFFZ "
                "WHERE ISNULL(STORN,'') IN ('','0') "
                "GROUP BY REFA1, REFA2 ORDER BY n DESC")
        except Exception as e:
            rep["nffz_refa"] = f"ERR: {e}"

        print("[E] Katalog-Strukturen + Stichproben ...")
        rep["kataloge"] = {}
        for t in ("TN14U", "TN14W", "TN24T", "TNDRG"):
            cols = _cols(src, t)
            sample = []
            if cols:
                try:
                    sample = src.query(f"SELECT TOP 10 * FROM sap.[{t}]")
                except Exception as e:
                    sample = [{"ERROR": str(e)}]
            rep["kataloge"][t] = {"columns": cols, "sample": sample}

        print("[F] NDOC-Fill-Audit (54 Mio, ein Scan — LASTFENSTER!) ...")
        try:
            rep["ndoc_fill"] = src.query(
                "SELECT COUNT(*) AS n, "
                "SUM(CASE WHEN LTRIM(RTRIM(ISNULL(PATNR,''))) NOT IN "
                "  ('','0000000000') THEN 1 ELSE 0 END) AS patnr_belegt, "
                "SUM(CASE WHEN LTRIM(RTRIM(ISNULL(FALNR,''))) <> '' "
                "  THEN 1 ELSE 0 END) AS falnr_belegt, "
                "SUM(CASE WHEN LTRIM(RTRIM(ISNULL(DTID,''))) <> '' "
                "  THEN 1 ELSE 0 END) AS dtid_belegt, "
                "SUM(CASE WHEN MEDOK='X' THEN 1 ELSE 0 END) AS medok "
                "FROM sap.NDOC")
        except Exception as e:
            rep["ndoc_fill"] = f"ERR: {e}"
    finally:
        src.close()

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "verify_live_report.json"), "w",
              encoding="utf-8") as f:
        json.dump(rep, f, ensure_ascii=False, indent=2, default=str)

    with open(os.path.join(out_dir, "verify_live_report.md"), "w",
              encoding="utf-8") as f:
        f.write("# SAP_FIHR — Live-Verifikationsbericht (Backlog nach R16)\n\n")
        f.write("## A — PK-Uniqueness (Registry-Kandidaten)\n\n"
                "| Tabelle | ok | n | distinct | Anmerkung |\n|---|---|---:|---:|---|\n")
        for t, r in rep["pk_checks"].items():
            note = ("fehlende Spalten: " + ",".join(r.get("missing_cols", []))
                    if r.get("missing_cols") else r.get("err", ""))
            f.write(f"| {t} | {r.get('ok')} | {r.get('n','-')} | "
                    f"{r.get('d','-')} | {note} |\n")
        f.write(f"\n## B — NICP↔N1LSTEAM\n\n- NICP.LFDBEW belegt: "
                f"{rep['nicp_lfdbew_belegt']} / {rep['nicp_gesamt']}\n"
                f"- N2OPDIAGNOSEN.LNRLS→N1LSTEAM (Stichprobe 100k): "
                f"{json.dumps(rep['n2opdiag_lnrls_in_lsteam'], default=str)}\n")
        f.write(f"\n## C — SAP-Office\n\n- SOOD: {rep['sood']['rows']} Zeilen\n"
                f"- SRGBTBREL: {rep['srgbtbrel']['rows']} Zeilen\n"
                f"- Relation-Typen (Top):\n```json\n"
                + json.dumps(rep["srgbtbrel_typen"], indent=2, default=str)[:3000]
                + "\n```\n")
        f.write("\n## D — NFFZ-REFA-Paare\n```json\n"
                + json.dumps(rep["nffz_refa"], indent=2, default=str)[:3000] + "\n```\n")
        f.write("\n## E — Katalog-Spalten\n\n")
        for t, k in rep["kataloge"].items():
            f.write(f"- **{t}**: {', '.join(k['columns']) or 'NICHT VORHANDEN'}\n")
        f.write("\n## F — NDOC-Fill\n```json\n"
                + json.dumps(rep["ndoc_fill"], indent=2, default=str) + "\n```\n")

    print(f"\nBericht: {out_dir}/verify_live_report.md + .json — bitte hochladen "
          f"bzw. committen (enthaelt nur Zaehlwerte/Schluessel, keine Klardaten).")
    return rep


def main(argv=None):
    ap = argparse.ArgumentParser(description="Live-Verifikationslauf (read-only)")
    ap.add_argument("--config", default="config/connection.yaml")
    ap.add_argument("--out", default="data")
    args = ap.parse_args(argv)
    run(args.config, args.out)


if __name__ == "__main__":
    main()
