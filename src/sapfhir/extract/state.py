# -*- coding: utf-8 -*-
"""Extraktions-Status (Watermarks, Keyset-Cursor) in DuckDB.

Macht Backfill und CDC resuemierbar. Jeder Batch aktualisiert den State idempotent;
Abbruch jederzeit moeglich, Wiederaufsetzen am letzten Cursor / an der letzten
change_seq.
"""
from __future__ import annotations
import json
import time
from typing import Sequence

import duckdb

_DDL = """
CREATE SCHEMA IF NOT EXISTS _meta;
CREATE TABLE IF NOT EXISTS _meta.extract_state (
    schema_name   VARCHAR,
    table_name    VARCHAR,
    phase         VARCHAR,        -- 'backfill' | 'cdc'
    keyset_cursor VARCHAR,        -- JSON-Array des letzten PK-Tupels
    change_seq    VARCHAR,        -- letzte Qlik header__change_seq
    rows_seen     BIGINT DEFAULT 0,
    last_run_ts   TIMESTAMP,
    last_duration DOUBLE,
    PRIMARY KEY (schema_name, table_name, phase)
);
CREATE TABLE IF NOT EXISTS _meta.run_log (
    ts TIMESTAMP, schema_name VARCHAR, table_name VARCHAR,
    phase VARCHAR, rows BIGINT, duration DOUBLE, note VARCHAR
);
"""


class State:
    def __init__(self, path: str = "data/warehouse.duckdb"):
        self.con = duckdb.connect(path)
        self.con.execute(_DDL)

    def get(self, schema: str, table: str, phase: str) -> dict | None:
        r = self.con.execute(
            "SELECT keyset_cursor, change_seq, rows_seen FROM _meta.extract_state "
            "WHERE schema_name=? AND table_name=? AND phase=?",
            [schema, table, phase]).fetchone()
        if not r:
            return None
        return {"cursor": json.loads(r[0]) if r[0] else None,
                "change_seq": r[1], "rows_seen": r[2] or 0}

    def update(self, schema: str, table: str, phase: str, *,
               cursor: Sequence | None = None, change_seq: str | None = None,
               rows_add: int = 0, duration: float = 0.0):
        cur_json = json.dumps(list(cursor)) if cursor is not None else None
        self.con.execute(
            "INSERT INTO _meta.extract_state "
            "(schema_name, table_name, phase, keyset_cursor, change_seq, rows_seen, "
            " last_run_ts, last_duration) VALUES (?,?,?,?,?,?, now(), ?) "
            "ON CONFLICT (schema_name, table_name, phase) DO UPDATE SET "
            "keyset_cursor=COALESCE(excluded.keyset_cursor, _meta.extract_state.keyset_cursor), "
            "change_seq=COALESCE(excluded.change_seq, _meta.extract_state.change_seq), "
            "rows_seen=_meta.extract_state.rows_seen + ?, "
            "last_run_ts=now(), last_duration=? ",
            [schema, table, phase, cur_json, change_seq, rows_add, duration,
             rows_add, duration])

    def log(self, schema: str, table: str, phase: str, rows: int,
            duration: float, note: str = ""):
        self.con.execute(
            "INSERT INTO _meta.run_log VALUES (now(),?,?,?,?,?,?)",
            [schema, table, phase, rows, duration, note])

    def close(self):
        self.con.close()
