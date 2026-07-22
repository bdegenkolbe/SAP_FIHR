# -*- coding: utf-8 -*-
"""Backfill (Vollabzug) einer oder mehrerer IS-H-Tabellen nach Parquet-Bronze.

Keyset-Pagination, adaptive Batchgroesse (Ziel ~target_batch_seconds), schmale
Spaltenprojektion aus config/columns/<tabelle>.yaml, Partitionierung nach Jahr,
resuemierbar ueber den Extract-State.

CLI:
  python -m sapfhir.extract.backfill --config config/connection.yaml --tier 1 --out data
  python -m sapfhir.extract.backfill --config ... --table NPAT NFAL NBEW --out data
"""
from __future__ import annotations
import argparse
import os
import time

import pyarrow as pa
import pyarrow.parquet as pq
import yaml

from .dbsource import Source
from .keyset import iter_keyset
from .state import State
from .window import Window


def _load(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _columns_for(table: str) -> list[str] | None:
    """Schmale Projektion aus config/columns/<table>.yaml, falls vorhanden."""
    p = os.path.join("config", "columns", f"{table}.yaml")
    if os.path.exists(p):
        spec = _load(p)
        return spec.get("select")
    return None


def _year_of(row: dict, date_col: str | None) -> str:
    if not date_col:
        return "unknown"
    v = row.get(date_col)
    if isinstance(v, str) and len(v) >= 4 and v[:4].isdigit():
        return v[:4]
    return "unknown"


def backfill_table(src: Source, st: State, schema: str, table: str, reg: dict,
                   out_dir: str, batch_rows: int, target_s: float,
                   scope: dict, window: Window | None = None) -> int:
    pk = reg["pk"]
    cols = _columns_for(table)
    date_col = reg.get("partition_date")
    where = []
    # Registry kann den Mandanten je Tabelle ueberschreiben (HR-System = '114',
    # IS-H = '100'; R28 live verifiziert)
    mandt = reg.get("mandt") or scope.get("mandt")
    if mandt:
        where.append(f"[MANDT] = '{mandt}'")
    if scope.get("einri") and "EINRI" in pk:
        where.append(f"[EINRI] = '{scope['einri']}'")
    where_extra = " AND ".join(where) if where else None

    prev = st.get(schema, table, "backfill")
    start_cursor = prev["cursor"] if prev else None
    total = prev["rows_seen"] if prev else 0
    base = os.path.join(out_dir, "bronze", table.lower())
    os.makedirs(base, exist_ok=True)

    part_no = 0
    for batch, cursor in iter_keyset(src, schema, table, pk, columns=cols,
                                     batch_rows=batch_rows,
                                     start_cursor=start_cursor,
                                     where_extra=where_extra):
        if window:
            window.wait()   # Lastfenster durchsetzen; Cursor bleibt im State
        t0 = time.time()
        # nach Jahr gruppiert schreiben
        by_year: dict[str, list[dict]] = {}
        for r in batch:
            by_year.setdefault(_year_of(r, date_col), []).append(r)
        for year, rows in by_year.items():
            ydir = os.path.join(base, f"jahr={year}")
            os.makedirs(ydir, exist_ok=True)
            tbl = pa.Table.from_pylist(rows)
            fn = os.path.join(ydir, f"part-{int(time.time()*1000)}-{part_no}.parquet")
            pq.write_table(tbl, fn, compression="zstd", compression_level=3)
            part_no += 1
        dt = time.time() - t0
        total += len(batch)
        st.update(schema, table, "backfill", cursor=cursor,
                  rows_add=len(batch), duration=dt)
        # adaptive Batchgroesse
        if dt > 0:
            factor = target_s / dt
            batch_rows = int(max(10000, min(500000, batch_rows * factor)))
        print(f"  {table}: +{len(batch):>7} (total {total:>10})  {dt:5.1f}s  "
              f"next batch={batch_rows}")
    st.log(schema, table, "backfill", total, 0.0, "done")
    return total


def main(argv=None):
    ap = argparse.ArgumentParser(description="IS-H Backfill -> Parquet Bronze")
    ap.add_argument("--config", required=True)
    ap.add_argument("--tier", type=int, help="alle Tabellen dieses Tiers")
    ap.add_argument("--table", nargs="+", help="explizite Tabellenliste")
    ap.add_argument("--out", default="data")
    ap.add_argument("--registry", default="config/tables.yaml")
    ap.add_argument("--ignore-window", action="store_true",
                    help="Lastfenster nicht durchsetzen (manueller Lauf)")
    args = ap.parse_args(argv)

    cfg = _load(args.config)
    reg_all = _load(args.registry)
    tables = reg_all["tables"]
    scope = cfg.get("scope", {})
    ex = cfg.get("extract", {})

    if args.table:
        selected = [(t, tables[t]) for t in args.table]
    elif args.tier:
        selected = [(t, r) for t, r in tables.items() if r.get("tier") == args.tier]
    else:
        raise SystemExit("Entweder --tier oder --table angeben.")

    window = Window(ex.get("window"), enforce=not args.ignore_window)
    src = Source({**cfg["source"], **{"scope": scope}}).connect()
    st = State(os.path.join(args.out, "warehouse.duckdb"))
    try:
        for tname, reg in selected:
            print(f"[backfill] {reg['schema']}.{tname} (Tier {reg.get('tier')})")
            backfill_table(src, st, reg["schema"], tname, reg, args.out,
                           int(ex.get("batch_rows", 100000)),
                           float(ex.get("target_batch_seconds", 120)), scope,
                           window=window)
    finally:
        st.close()
        src.close()


if __name__ == "__main__":
    main()
