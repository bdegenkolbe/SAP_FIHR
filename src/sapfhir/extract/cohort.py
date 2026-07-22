# -*- coding: utf-8 -*-
"""Kohorten-gefilterter Backfill (Phase-0-Einstieg: aktuelle Stationspatienten).

Statt eines Vollabzugs (85 Mio Zeilen) laedt dieser Treiber gezielt eine klinisch
sinnvolle Erst-Kohorte mit VOLLER Historie:

  1. Kohorte aufloesen: alle Patienten mit offener stationaerer Aufnahme-Bewegung
     (NBEW BEWTY='1', BWEDT = 9999-Sentinel / NULL, nicht storniert).
  2. Fall-Historie expandieren: ALLE FALNR dieser Patienten (NFAL) — 360-Grad.
  3. Kohorten-Tabellen (patienten-/fallbezogen) chunk-weise per IN-Liste laden.
  4. Referenz-/Katalogtabellen (Bewegungsarten, OE, Kostentraeger, ...) VOLL laden.

Ergebnis liegt als Parquet-Bronze wie beim normalen Backfill; die nachgelagerte
Pipeline (Privacy -> FHIR-NDJSON -> Gold -> mcp.*) bleibt unveraendert.

CLI:
  python -m sapfhir.extract.cohort --config config/connection.yaml \
         --define current_inpatients --out data
"""
from __future__ import annotations
import argparse
import datetime as _dt
import json
import os
import time

import pyarrow as pa
import pyarrow.parquet as pq
import yaml

from .dbsource import Source
from .backfill import backfill_table, _columns_for, _year_of
from .state import State
from .window import Window


# --- Kohorten-Schluessel je Tabelle ------------------------------------------
# (key_col, key_art, mandt_col): key_art PATNR|FALNR; mandt_col weicht bei Tabellen
# mit ENGLISCHEN Spaltennamen ab (NDRG: CLIENT/PATCASEID, verifiziert R9).
COHORT_KEY = {
    "NPAT": ("PATNR", "PATNR", "MANDT"),
    "NRSF": ("PATNR", "PATNR", "MANDT"),
    "NFAL": ("FALNR", "FALNR", "MANDT"),
    "NBEW": ("FALNR", "FALNR", "MANDT"),
    "NDIA": ("FALNR", "FALNR", "MANDT"),
    "NICP": ("FALNR", "FALNR", "MANDT"),   # PK LNRIC, aber FALNR-Spalte vorhanden
    "NKSK": ("FALNR", "FALNR", "MANDT"),   # PK BELNR,  aber FALNR-Spalte vorhanden
    "NDRG": ("PATCASEID", "FALNR", "CLIENT"),  # DRG je Fall (englische Spalten!)
}

# Nicht-SAP-Referenztabellen OHNE MANDT (voll laden, eigener Pfad)
REFERENCE_NOMANDT = ["Leistungen_DRGs"]

# Referenz-/Katalogtabellen: klein, ohne Personenbezug -> VOLL laden.
# (Tier-1 minus Kohorten-Tabellen minus dokumenten-/laborschwere Tabellen,
#  die erst in spaeteren Phasen erschlossen werden.)
REFERENCE_TABLES = [
    "NORG", "NGPA", "NKTR", "NKDI", "NPER",
    "TN14T", "TN14R", "TN14G", "TN14D", "TN14H", "TN14U",
    "TNK00", "TN26C", "TN01", "TN39A", "TN39T",
]
# Bewusst NICHT in Phase 0: NDOC/N2LABOR*/N2TEXT/N1MEORDER (Volumen/Dokumentwelt),
# NADR (Adressen) und TN14K (nicht repliziert).


def _load(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _chunks(seq, n=900):
    seq = list(seq)
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


# --- Schritt 1+2: Kohorte aufloesen ------------------------------------------
def resolve_current_inpatients(src: Source, scope: dict, cap: int | None = None,
                               load_scope: str = "current") -> dict:
    """Aktuell stationaer liegende Patienten.

    load_scope='current' (DEFAULT, R21-Korrektur): laedt NUR die aktuell offenen
    Faelle selbst — KEINE Ausweitung auf die restliche Fallhistorie der Patienten.
    Das entspricht wortgetreu "aktuelle Patienten auf Station" und bleibt klein
    (~Anzahl offener Bewegungen, nicht die Lebenshistorie aller Patienten).

    load_scope='history': fruehere (zu weite) Interpretation — expandiert auf ALLE
    historischen Faelle jedes betroffenen Patienten (360-Grad-Akte). Bewusst
    OPT-IN, da das bei 2.6k Patienten schnell auf >50k Faelle / >200k Bewegungen
    waechst und damit NICHT mehr "nur die aktuellen Stationspatienten" ist.
    """
    mandt = scope.get("mandt", "100")
    einri = scope.get("einri", "0001")

    # (1) offene stationaere Aufnahme-Bewegung -> aktuelle FALNR
    #     (NBEW haelt KEIN PATNR — Bewegungen haengen nur am Fall)
    rows = src.query(
        "SELECT DISTINCT FALNR FROM sap.NBEW "
        "WHERE MANDT = ? AND EINRI = ? AND BEWTY = '1' "
        "  AND COALESCE(STORN,'') NOT IN ('X','1') "
        "  AND (BWEDT IS NULL OR LEFT(CONVERT(varchar(8), BWEDT, 112),4) = '9999')",
        (mandt, einri))
    cur_faelle = {r["FALNR"] for r in rows if r.get("FALNR")}
    print(f"  [1] aktuelle Stations-Faelle (offene Bewegung): {len(cur_faelle)}")

    # (1b) Patienten dieser Faelle (ueber NFAL) — nur zur Identitaet/NPAT,
    #      NICHT als Ausgangspunkt fuer eine Fallhistorie-Erweiterung.
    patnr_by_fall: dict[str, str] = {}
    for ch in _chunks(cur_faelle):
        ph = ",".join(["?"] * len(ch))
        for r in src.iter_query(
                f"SELECT FALNR, PATNR FROM sap.NFAL WHERE MANDT = ? AND FALNR IN ({ph})",
                (mandt, *ch)):
            if r.get("FALNR") and r.get("PATNR"):
                patnr_by_fall[r["FALNR"]] = r["PATNR"]
    patnr = set(patnr_by_fall.values())
    if cap:
        patnr = set(sorted(patnr)[:cap])
        cur_faelle = {f for f, p in patnr_by_fall.items() if p in patnr}
    print(f"  [1b] aktuelle Stationspatienten: {len(patnr)}")

    if load_scope == "history":
        # (2) alle Faelle dieser Patienten (volle Historie) — nur auf Wunsch
        falnr: set[str] = set()
        for ch in _chunks(patnr):
            ph = ",".join(["?"] * len(ch))
            for r in src.iter_query(
                    f"SELECT FALNR FROM sap.NFAL WHERE MANDT = ? AND PATNR IN ({ph})",
                    (mandt, *ch)):
                if r.get("FALNR"):
                    falnr.add(r["FALNR"])
        print(f"  [2] Faelle gesamt (360-Grad-Historie, opt-in): {len(falnr)}")
    else:
        falnr = set(cur_faelle)
        print(f"  [2] Faelle im Ladeumfang (nur aktuelle, KEINE Historie): {len(falnr)}")

    return {
        "name": "current_inpatients",
        "load_scope": load_scope,
        "scope": {"mandt": mandt, "einri": einri},
        "resolved_at": _dt.datetime.now().isoformat(timespec="seconds"),
        "patnr": sorted(patnr),
        "falnr": sorted(falnr),
        "counts": {"patienten": len(patnr), "faelle": len(falnr)},
    }


def save_cohort(cohort: dict, out_dir: str) -> str:
    d = os.path.join(out_dir, "cohort")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, f"{cohort['name']}.json")
    with open(p, "w", encoding="utf-8") as f:
        json.dump(cohort, f, ensure_ascii=False, indent=2)
    return p


# --- Schritt 3: Kohorten-Tabelle laden ---------------------------------------
def cohort_backfill_table(src: Source, schema: str, table: str, key_col: str,
                          cohort: dict, reg: dict, out_dir: str,
                          scope: dict, st: "State | None" = None,
                          key_art: str = "FALNR", mandt_col: str = "MANDT") -> int:
    keys = cohort["patnr"] if key_art == "PATNR" else cohort["falnr"]
    cols = _columns_for(table)
    collist = ", ".join(f"[{c}]" for c in cols) if cols else "*"
    date_col = reg.get("partition_date")
    base = os.path.join(out_dir, "bronze", table.lower())
    os.makedirs(base, exist_ok=True)

    total = 0
    part_no = 0
    for ch in _chunks(keys):
        ph = ",".join(["?"] * len(ch))
        where = f"[{mandt_col}] = ?"
        params: list = [scope.get("mandt", "100")]
        if scope.get("einri") and "EINRI" in reg.get("pk", []):
            where += " AND [EINRI] = ?"
            params.append(scope["einri"])
        where += f" AND [{key_col}] IN ({ph})"
        params.extend(ch)
        sql = f"SELECT {collist} FROM {schema}.{table} WHERE {where}"

        by_year: dict[str, list[dict]] = {}
        for r in src.iter_query(sql, tuple(params)):
            by_year.setdefault(_year_of(r, date_col), []).append(r)
        for year, rows in by_year.items():
            if not rows:
                continue
            ydir = os.path.join(base, f"jahr={year}")
            os.makedirs(ydir, exist_ok=True)
            fn = os.path.join(ydir, f"part-{int(time.time()*1000)}-{part_no}.parquet")
            pq.write_table(pa.Table.from_pylist(rows), fn,
                           compression="zstd", compression_level=3)
            part_no += 1
            total += len(rows)
    print(f"  {table:8} (key {key_col}): {total:>9} Zeilen")
    if st is not None:
        # Markiert die Tabelle in _meta.extract_state als 'cohort' (Teilmenge) —
        # damit zeigt gold.quality.reconcile() statt "UNKNOWN" den Status
        # "KOHORTE" (bewusste Teilladung, kein Abgleichsfehler).
        st.update(schema, table, "cohort", rows_add=total)
    return total


# --- Treiber -----------------------------------------------------------------
def run(config: str, define: str, out_dir: str, cap: int | None = None,
        skip_reference: bool = False, load_scope: str = "current",
        progress=None) -> dict:
    """progress(str) wird bei jedem Meilenstein aufgerufen (fuer den Ladeknopf-Status)."""
    def _p(msg: str):
        print(msg)
        if progress:
            progress(msg)

    cfg = _load(config)
    reg_all = _load("config/tables.yaml")["tables"]
    scope = cfg.get("scope", {})
    ex = cfg.get("extract", {})

    os.makedirs(out_dir, exist_ok=True)
    src = Source({**cfg["source"], "scope": scope}).connect()
    st = State(os.path.join(out_dir, "warehouse.duckdb"))
    try:
        if define != "current_inpatients":
            raise SystemExit(f"Unbekannte Kohorten-Definition: {define}")
        _p("Kohorte aufloesen ...")
        cohort = resolve_current_inpatients(src, scope, cap=cap, load_scope=load_scope)
        path = save_cohort(cohort, out_dir)
        _p(f"Kohorte: {cohort['counts']['patienten']} Patienten, "
           f"{cohort['counts']['faelle']} Faelle (scope={load_scope}) -> {path}")

        _p("Kohorten-Tabellen laden (patienten-/fallbezogen) ...")
        rep = {}
        for table, (key_col, key_art, mandt_col) in COHORT_KEY.items():
            reg = reg_all.get(table)
            if not reg:
                print(f"  {table}: nicht in Registry — uebersprungen")
                continue
            rep[table] = cohort_backfill_table(
                src, reg.get("schema", "sap"), table, key_col, cohort, reg,
                out_dir, scope, st=st, key_art=key_art, mandt_col=mandt_col)
            _p(f"  {table}: {rep[table]} Zeilen")

        for table in REFERENCE_NOMANDT:
            # Nicht-SAP-Referenzkataloge ohne MANDT: klein, voll laden
            reg = reg_all.get(table)
            if not reg:
                continue
            base = os.path.join(out_dir, "bronze", table.lower())
            os.makedirs(base, exist_ok=True)
            rows = list(src.iter_query(f"SELECT * FROM {reg.get('schema','sap')}.[{table}]"))
            if rows:
                fn = os.path.join(base, "jahr=unknown")
                os.makedirs(fn, exist_ok=True)
                pq.write_table(pa.Table.from_pylist(rows),
                               os.path.join(fn, f"part-{int(time.time()*1000)}-0.parquet"),
                               compression="zstd", compression_level=3)
            rep[table] = len(rows)
            if st is not None:
                st.update(reg.get("schema", "sap"), table, "cohort", rows_add=len(rows))
            _p(f"  {table}: {len(rows)} Zeilen (Referenz, voll)")

        if not skip_reference:
            _p("Referenztabellen laden (voll, klein) ...")
            window = Window(None, enforce=False)
            for table in REFERENCE_TABLES:
                reg = reg_all.get(table)
                if not reg:
                    continue
                try:
                    n = backfill_table(
                        src, st, reg.get("schema", "sap"), table, reg, out_dir,
                        int(ex.get("batch_rows", 100000)),
                        float(ex.get("target_batch_seconds", 120)), scope,
                        window=window)
                    rep[table] = n
                except Exception as e:
                    print(f"  {table}: FEHLER {e}")
        _p("Extrakt abgeschlossen.")
        return {"cohort": cohort["counts"], "tables": rep}
    finally:
        st.close()
        src.close()


def main(argv=None):
    ap = argparse.ArgumentParser(description="Kohorten-gefilterter Backfill")
    ap.add_argument("--config", required=True)
    ap.add_argument("--define", default="current_inpatients",
                    help="Kohorten-Definition (aktuell: current_inpatients)")
    ap.add_argument("--out", default="data")
    ap.add_argument("--cap", type=int, default=None,
                    help="max. Patientenzahl (Probelauf)")
    ap.add_argument("--skip-reference", action="store_true",
                    help="Referenztabellen nicht laden")
    ap.add_argument("--scope", choices=["current", "history"], default="current",
                    help="current (DEFAULT) = nur aktuell offene Faelle; "
                         "history = zusaetzlich komplette Fallhistorie (opt-in)")
    args = ap.parse_args(argv)
    rep = run(args.config, args.define, args.out, cap=args.cap,
              skip_reference=args.skip_reference, load_scope=args.scope)
    print("\n== Zusammenfassung ==")
    print(json.dumps(rep, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
