# -*- coding: utf-8 -*-
"""Zentraler Fallzeitraum je Fall: gold.fall_zeitraum (R34).

Warum: NFAL.BEGDT/ENDDT sind in diesem Haus NUR bei ambulanten Faellen (FALAR=2)
gepflegt. Bei stationaeren/teilstationaeren Faellen (FALAR 1/3) steht zu 99,9 % das
SAP-Leerdatum 0101-01-01 (via Qlik) — wer dort ueber BEGDT zaehlt, sortiert oder
Zeitraeume bildet, verliert alle stationaeren Faelle (live R34: ~60.000/Jahr).

Regel (eine Stelle, alle Verbraucher lesen von hier):
  beg  = NFAL.BEGDT, wenn echtes Datum; sonst frueheste Aufnahmebewegung
         (NBEW BEWTY='1', nicht storniert); sonst frueheste beliebige Bewegung.
  ende = NFAL.ENDDT, wenn echtes Datum; sonst spaeteste Entlassbewegung
         (NBEW BEWTY='2', nicht storniert); sonst NULL = offener Fall.
  "Echtes Datum" = Jahr 1901..9998 (Sentinels 0101-01-01 und 9999-12-31 fallen raus,
  analog fhir.mappers.core._echtes_datum).

beg_quelle dokumentiert die Herkunft ('NFAL' | 'NBEW_AUFNAHME' | 'NBEW' | NULL),
damit Auswertungen die Ableitung offenlegen koennen.
"""
from __future__ import annotations

import duckdb


def echtes_datum_sql(expr: str) -> str:
    """SQL-Ausdruck: expr als DATE, Sentinels (Jahr <1901 oder >=9999) -> NULL."""
    d = f"TRY_CAST({expr} AS DATE)"
    return f"(CASE WHEN year({d}) BETWEEN 1901 AND 9998 THEN {d} END)"


_STORNO_FREI = "COALESCE(TRIM(CAST({c} AS VARCHAR)),'') NOT IN ('X','1')"


def _has(con: duckdb.DuckDBPyConnection, schema: str, table: str) -> bool:
    return bool(con.execute(
        "SELECT 1 FROM information_schema.tables "
        "WHERE table_schema=? AND table_name=?", [schema, table]).fetchone())


def _cols(con: duckdb.DuckDBPyConnection, schema: str, table: str) -> set[str]:
    return {r[0].upper() for r in
            con.execute(f'DESCRIBE {schema}."{table}"').fetchall()}


def build_sql(con: duckdb.DuckDBPyConnection) -> str | None:
    """CREATE-Statement fuer gold.fall_zeitraum (None, wenn NFAL fehlt)."""
    if not _has(con, "bronze_current", "nfal"):
        return None
    fcols = _cols(con, "bronze_current", "nfal")
    einri = 'f."EINRI"' if "EINRI" in fcols else "NULL"
    beg_nfal = echtes_datum_sql('f."BEGDT"') if "BEGDT" in fcols else "NULL"
    end_nfal = echtes_datum_sql('f."ENDDT"') if "ENDDT" in fcols else "NULL"
    storno_f = (_STORNO_FREI.format(c='f."STORN"') if "STORN" in fcols else "TRUE")

    bcols = (_cols(con, "bronze_current", "nbew")
             if _has(con, "bronze_current", "nbew") else set())
    if {"FALNR", "BEWTY", "BWIDT"} <= bcols:
        bw = echtes_datum_sql('b."BWIDT"')
        storno_b = (_STORNO_FREI.format(c='b."STORN"') if "STORN" in bcols else "TRUE")
        # EINRI im Join, falls vorhanden (FALNR ist nur je Einrichtung eindeutig)
        on_einri = ' AND b._einri IS NOT DISTINCT FROM f."EINRI"' if (
            "EINRI" in bcols and "EINRI" in fcols) else ""
        b_einri = 'b."EINRI"' if "EINRI" in bcols else "NULL"
        bew_cte = f"""
            bew AS (
              SELECT b."FALNR" AS _falnr, {b_einri} AS _einri,
                     MIN(CASE WHEN CAST(b."BEWTY" AS VARCHAR) = '1' THEN {bw} END) AS aufn,
                     MAX(CASE WHEN CAST(b."BEWTY" AS VARCHAR) = '2' THEN {bw} END) AS entl,
                     MIN({bw}) AS erste
              FROM bronze_current.nbew b
              WHERE {storno_b}
              GROUP BY 1, 2)"""
        join = f'LEFT JOIN bew b ON b._falnr = f."FALNR"{on_einri}'
        beg = f"COALESCE({beg_nfal}, b.aufn, b.erste)"
        ende = f"COALESCE({end_nfal}, b.entl)"
        quelle = (f"CASE WHEN {beg_nfal} IS NOT NULL THEN 'NFAL' "
                  f"WHEN b.aufn IS NOT NULL THEN 'NBEW_AUFNAHME' "
                  f"WHEN b.erste IS NOT NULL THEN 'NBEW' END")
        with_sql = f"WITH {bew_cte}"
    else:
        join, with_sql = "", ""
        beg, ende = beg_nfal, end_nfal
        quelle = f"CASE WHEN {beg_nfal} IS NOT NULL THEN 'NFAL' END"

    falar = 'CAST(f."FALAR" AS VARCHAR)' if "FALAR" in fcols else "NULL"
    stasp = 'f."STASP"' if "STASP" in fcols else "NULL"
    patnr = 'f."PATNR"' if "PATNR" in fcols else "NULL"
    # Bewusst OHNE Storno-Filter: 1 Zeile je NFAL-Zeile (passt 1:1 zu mcp.fall);
    # ist_storno erlaubt den Verbrauchern den gewohnten Filter.
    return f"""
        CREATE OR REPLACE TABLE gold.fall_zeitraum AS
        {with_sql}
        SELECT f."FALNR" AS FALNR, {einri} AS EINRI, {patnr} AS PATNR,
               {falar} AS FALAR, {stasp} AS STASP, NOT ({storno_f}) AS ist_storno,
               {beg} AS beg, {ende} AS ende, {quelle} AS beg_quelle
        FROM bronze_current.nfal f
        {join}"""


def build(con: duckdb.DuckDBPyConnection) -> bool:
    """Erzeugt gold.fall_zeitraum (materialisiert: die NBEW-Aggregation ist teuer und
    wird von Marts, mcp.fall und Graph geteilt). False, wenn NFAL fehlt."""
    sql = build_sql(con)
    if not sql:
        return False
    con.execute("CREATE SCHEMA IF NOT EXISTS gold")
    con.execute(sql)
    return True
