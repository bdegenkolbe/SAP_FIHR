# -*- coding: utf-8 -*-
"""Keyset-Pagination fuer grosse IS-H-Tabellen.

Statt OFFSET (das bei 210 Mio Zeilen quadratisch entartet) paginieren wir ueber den
zusammengesetzten Clustered-Key. Konstante Latenz je Batch, jederzeit resuemierbar.

Der Cursor ist der letzte gesehene Schluesseltupel; die naechste Seite holt alles
"groesser als" diesen Tupel in kanonischer Sortierreihenfolge.
"""
from __future__ import annotations
from typing import Iterator, Sequence


def _tuple_gt_clause(cols: Sequence[str]) -> str:
    """Erzeugt eine (col1,col2,...) > (?,?,...)-Bedingung, portabel als OR-Kaskade.
    MSSQL unterstuetzt Row-Value-Constructors im WHERE nicht zuverlaessig, daher die
    entfaltete lexikographische Form."""
    parts = []
    for i in range(len(cols)):
        eqs = " AND ".join(f"[{cols[j]}] = ?" for j in range(i))
        gt = f"[{cols[i]}] > ?"
        parts.append(f"({eqs} AND {gt})" if eqs else f"({gt})")
    return "(" + " OR ".join(parts) + ")"


def _params_for_cursor(cursor: Sequence, ncols: int) -> list:
    """Baut die Parameterliste passend zur entfalteten Bedingung."""
    out: list = []
    for i in range(ncols):
        for j in range(i):
            out.append(cursor[j])
        out.append(cursor[i])
    return out


def iter_keyset(src, schema: str, table: str, pk: Sequence[str],
                columns: Sequence[str] | None = None,
                batch_rows: int = 100000,
                start_cursor: Sequence | None = None,
                where_extra: str | None = None) -> Iterator[tuple[list[dict], tuple]]:
    """Liefert (batch, cursor)-Paare. cursor = letztes Schluesseltupel des Batches,
    zum Persistieren im State und Wiederaufsetzen.

    columns: schmale Projektion (Pflicht bei breiten Tabellen wie NBEW/NFAL mit 120+
             Spalten). None -> SELECT * (nur fuer kleine Tabellen).
    """
    col_sql = "*" if not columns else ", ".join(f"[{c}]" for c in columns)
    order = ", ".join(f"[{c}]" for c in pk)
    cursor = tuple(start_cursor) if start_cursor else None

    while True:
        conds = []
        params: list = []
        if cursor is not None:
            conds.append(_tuple_gt_clause(pk))
            params += _params_for_cursor(cursor, len(pk))
        if where_extra:
            conds.append(where_extra)
        where = ("WHERE " + " AND ".join(conds)) if conds else ""
        sql = (f"SELECT TOP {int(batch_rows)} {col_sql} "
               f"FROM {schema}.[{table}] {where} ORDER BY {order}")
        batch = src.query(sql, params)
        if not batch:
            return
        last = batch[-1]
        cursor = tuple(last[c] for c in pk)
        yield batch, cursor
        if len(batch) < batch_rows:
            return
