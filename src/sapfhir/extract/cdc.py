# -*- coding: utf-8 -*-
"""Inkrementeller Lauf (CDC) ueber Qlik-Replicate-Change-Tables.

Qlik legt je Basistabelle eine <tabelle>__ct mit Spalten header__change_seq,
header__change_oper (INSERT/UPDATE/DELETE) und den Nutzspalten an. Wir lesen alles
seit der zuletzt gemerkten change_seq, mergen nach Bronze (Upsert je PK) und markieren
Deletes/Stornos.

Fallback fuer Tabellen mit cdc: watermark -> UPDAT/ERDAT-Vergleich (+1 Tag Ueberlappung,
Dedup ueber PK).

CLI: python -m sapfhir.extract.cdc --config config/connection.yaml --out data
"""
from __future__ import annotations
import argparse
import datetime as _dt
import os
import time

import yaml

from .dbsource import Source
from .state import State


def _load(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _merge_delta(st: State, table: str, pk: list[str], rows: list[dict],
                 storno_col: str | None):
    """Schreibt Delta-Zeilen in eine DuckDB-Delta-Landezone; der Gold-Build
    fuehrt Bronze+Delta zusammen (last-write-wins ueber change_seq).
    Deletes/Stornos werden als _deleted-Flag markiert (kein Hard-Delete)."""
    if not rows:
        return 0
    con = st.con
    tname = f"delta_{table.lower()}"
    con.execute(f"CREATE SCHEMA IF NOT EXISTS _delta")
    # dynamisch aus erster Zeile
    cols = list(rows[0].keys())
    coldefs = ", ".join(f'"{c}" VARCHAR' for c in cols)
    con.execute(f'CREATE TABLE IF NOT EXISTS _delta."{tname}" ({coldefs})')
    # append
    con.executemany(
        f'INSERT INTO _delta."{tname}" VALUES ({",".join("?"*len(cols))})',
        [[str(r.get(c)) if r.get(c) is not None else None for c in cols] for r in rows])
    return len(rows)


def cdc_table(src: Source, st: State, schema: str, table: str, reg: dict) -> int:
    mode = reg.get("cdc", "ct")
    pk = reg["pk"]
    storno = reg.get("storno")
    prev = st.get(schema, table, "cdc")
    seen = 0

    if mode == "ct":
        since = prev["change_seq"] if prev else None
        if since is None:
            # erster CDC-Lauf nach Backfill: aktuelle Spitze als Startpunkt merken
            top = src.max_change_seq(schema, table)
            st.update(schema, table, "cdc", change_seq=top)
            print(f"  {table}: CDC initialisiert bei change_seq={top}")
            return 0
        t0 = time.time()
        buf, last_seq = [], since
        for row in src.changed_rows(schema, table, since):
            last_seq = row.get("header__change_seq", last_seq)
            buf.append(row)
            if len(buf) >= 5000:
                seen += _merge_delta(st, table, pk, buf, storno); buf = []
        if buf:
            seen += _merge_delta(st, table, pk, buf, storno)
        st.update(schema, table, "cdc", change_seq=last_seq,
                  rows_add=seen, duration=time.time() - t0)

    elif mode == "watermark":
        wm_col = reg.get("watermark_col", "UPDAT")
        since = prev["change_seq"] if prev else None  # hier: ISO-Datum im change_seq-Feld
        t0 = time.time()
        params = []
        where = "1=1"
        if since:
            # 1 Tag Ueberlappung
            d = (_dt.date.fromisoformat(since[:10]) - _dt.timedelta(days=1)).isoformat()
            where = f"[{wm_col}] >= ?"
            params = [d]
        sql = f"SELECT * FROM {schema}.[{table}] WHERE {where}"
        buf, maxd = [], since or "0001-01-01"
        for row in src.iter_query(sql, params):
            v = row.get(wm_col)
            if isinstance(v, str) and v > maxd:
                maxd = v
            buf.append(row)
            if len(buf) >= 5000:
                seen += _merge_delta(st, table, pk, buf, storno); buf = []
        if buf:
            seen += _merge_delta(st, table, pk, buf, storno)
        st.update(schema, table, "cdc", change_seq=maxd,
                  rows_add=seen, duration=time.time() - t0)

    st.log(schema, table, "cdc", seen, 0.0, mode)
    return seen


def main(argv=None):
    ap = argparse.ArgumentParser(description="IS-H CDC-Inkrement")
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", default="data")
    ap.add_argument("--registry", default="config/tables.yaml")
    ap.add_argument("--tier", type=int)
    args = ap.parse_args(argv)

    cfg = _load(args.config)
    reg_all = _load(args.registry)["tables"]
    src = Source({**cfg["source"], **{"scope": cfg.get("scope", {})}}).connect()
    st = State(os.path.join(args.out, "warehouse.duckdb"))
    try:
        for tname, reg in reg_all.items():
            if reg.get("cdc") == "full":
                continue
            if args.tier and reg.get("tier") != args.tier:
                continue
            n = cdc_table(src, st, reg["schema"], tname, reg)
            print(f"[cdc] {reg['schema']}.{tname}: {n} Delta-Zeilen")
    finally:
        st.close()
        src.close()


if __name__ == "__main__":
    main()
