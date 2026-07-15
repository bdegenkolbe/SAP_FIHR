# -*- coding: utf-8 -*-
"""Inkrementeller Lauf (CDC) ueber Qlik-Replicate-Change-Tables (CONCEPT §5/§14).

Qlik legt je Basistabelle eine <tabelle>__ct mit Spalten header__change_seq,
header__change_oper (INSERT/UPDATE/DELETE) und den Nutzspalten an. Wir lesen alles
seit der zuletzt gemerkten change_seq und schreiben **Delta-Parquet im Bronze-Schema**
(Spaltenprojektion wie im Backfill) plus zwei Metaspalten:

    _op   'I' | 'U' | 'D'   (aus header__change_oper)
    _seq  header__change_seq (lexikografisch sortierbar)

Ablage: data/bronze/_delta/<tabelle>/seq=<von>-<bis>.parquet
Der Merge-Layer (extract/merge.py) macht daraus bronze_current.* (last-write-wins).

Retention-Lueckenerkennung (ANALYSE A2): Ist die eigene Watermark aelter als die
aelteste noch in der ct-Tabelle vorhandene Sequenz, wurden Aenderungen von Qlik
bereits abgeraeumt -> harter Fehler + Re-Backfill der Tabelle noetig.

Fallback fuer Tabellen mit cdc: watermark -> UPDAT/ERDAT-Vergleich (+1 Tag
Ueberlappung, Dedup ueber PK im Merge). Auch hier gilt die Spaltenprojektion.

CLI: python -m sapfhir.extract.cdc --config config/connection.yaml --out data
"""
from __future__ import annotations
import argparse
import datetime as _dt
import os
import time

import pyarrow as pa
import pyarrow.parquet as pq
import yaml

from .dbsource import Source
from .state import State


class RetentionGapError(RuntimeError):
    """Watermark liegt vor der aeltesten verfuegbaren change_seq."""


def _load(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _columns_for(table: str) -> list[str] | None:
    p = os.path.join("config", "columns", f"{table}.yaml")
    if os.path.exists(p):
        return _load(p).get("select")
    return None


_OP_MAP = {"INSERT": "I", "UPDATE": "U", "DELETE": "D",
           "I": "I", "U": "U", "D": "D"}


def _write_delta(out_dir: str, table: str, rows: list[dict],
                 columns: list[str] | None, seq_from: str, seq_to: str) -> str:
    """Schreibt einen Delta-Batch als Parquet (Projektion + _op/_seq)."""
    d = os.path.join(out_dir, "bronze", "_delta", table.lower())
    os.makedirs(d, exist_ok=True)
    slim = []
    for r in rows:
        rec = {c: r.get(c) for c in columns} if columns else {
            k: v for k, v in r.items() if not k.startswith("header__")}
        rec["_op"] = _OP_MAP.get(str(r.get("header__change_oper", "U")).upper(), "U")
        rec["_seq"] = str(r.get("header__change_seq", ""))
        slim.append(rec)
    fn = os.path.join(d, f"seq-{int(time.time()*1000)}.parquet")
    pq.write_table(pa.Table.from_pylist(slim), fn,
                   compression="zstd", compression_level=3)
    return fn


def cdc_table(src: Source, st: State, schema: str, table: str, reg: dict,
              out_dir: str = "data") -> int:
    mode = reg.get("cdc", "ct")
    columns = _columns_for(table)
    prev = st.get(schema, table, "cdc")
    seen = 0

    if mode == "ct":
        since = prev["change_seq"] if prev else None
        if since is None:
            # erster CDC-Lauf nach Backfill: aktuelle Spitze als Startpunkt merken
            top = src.max_change_seq(schema, table)
            st.update(schema, table, "cdc", change_seq=top or "0")
            print(f"  {table}: CDC initialisiert bei change_seq={top}")
            return 0
        # Retention-Waechter: aelteste verfuegbare Sequenz > Watermark?
        oldest = src.min_change_seq(schema, table)
        if oldest is not None and str(oldest) > str(since):
            st.log(schema, table, "cdc", 0, 0.0,
                   f"RETENTION_GAP watermark={since} oldest={oldest}")
            raise RetentionGapError(
                f"{schema}.{table}: Watermark {since} aelter als aelteste "
                f"verfuegbare change_seq {oldest} — Aenderungen wurden von Qlik "
                f"abgeraeumt. Re-Backfill der Tabelle erforderlich.")
        t0 = time.time()
        buf, last_seq = [], since
        for row in src.changed_rows(schema, table, since):
            last_seq = str(row.get("header__change_seq", last_seq))
            buf.append(row)
            if len(buf) >= 50000:
                _write_delta(out_dir, table, buf, columns, since, last_seq)
                seen += len(buf); buf = []
        if buf:
            _write_delta(out_dir, table, buf, columns, since, last_seq)
            seen += len(buf)
        st.update(schema, table, "cdc", change_seq=last_seq,
                  rows_add=seen, duration=time.time() - t0)

    elif mode == "watermark":
        wm_col = reg.get("watermark_col") or "UPDAT"
        since = prev["change_seq"] if prev else None  # ISO-Datum im change_seq-Feld
        t0 = time.time()
        col_sql = ", ".join(f"[{c}]" for c in columns) if columns else "*"
        params: list = []
        where = "1=1"
        if since:
            # 1 Tag Ueberlappung (Datum ohne Zeit in manchen Tabellen)
            d = (_dt.date.fromisoformat(since[:10]) - _dt.timedelta(days=1)).isoformat()
            where = f"[{wm_col}] >= ?"
            params = [d]
        sql = f"SELECT {col_sql} FROM {schema}.[{table}] WHERE {where}"
        buf, maxd = [], since or "0001-01-01"
        for row in src.iter_query(sql, params):
            v = row.get(wm_col)
            if isinstance(v, str) and v > maxd:
                maxd = v
            row["header__change_oper"] = "U"
            row["header__change_seq"] = str(v or maxd)
            buf.append(row)
            if len(buf) >= 50000:
                _write_delta(out_dir, table, buf, columns, "wm", "wm")
                seen += len(buf); buf = []
        if buf:
            _write_delta(out_dir, table, buf, columns, "wm", "wm")
            seen += len(buf)
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
    gaps = []
    try:
        for tname, reg in reg_all.items():
            if reg.get("cdc") == "full":
                continue
            if args.tier and reg.get("tier") != args.tier:
                continue
            try:
                n = cdc_table(src, st, reg["schema"], tname, reg, args.out)
                print(f"[cdc] {reg['schema']}.{tname}: {n} Delta-Zeilen")
            except RetentionGapError as e:
                gaps.append(str(e))
                print(f"[cdc] ALARM: {e}")
    finally:
        st.close()
        src.close()
    if gaps:
        raise SystemExit(f"{len(gaps)} Tabelle(n) mit Retention-Luecke — "
                         f"Re-Backfill erforderlich.")


if __name__ == "__main__":
    main()
