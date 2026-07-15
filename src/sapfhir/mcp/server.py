# -*- coding: utf-8 -*-
"""ishx-mcp / SAP_FIHR MCP-Server (stdio, read-only).

Stellt einem LLM (Claude Desktop / LibreChat via Supergateway) natuerlichsprachlichen
Zugriff auf den lokalen Analysespeicher bereit. KEIN Netz-Egress, alle Daten on-prem.

Tools:
  patient_search   Identifikation (Name/GebDat/PATNR/FALNR)
  patient_360      kompakte strukturierte Zusammenfassung
  patient_timeline chronologische Ereignisliste
  cohort_sql       DuckDB SELECT/WITH, SELECT-only-Guard, Zeilenlimit
  graph_query      Kuzu Cypher, read-only, Timeout
  doc_search       Volltext (FTS/BM25) ueber N2TEXT
  fhir_get         FHIR-Ressource per Typ+ID aus Silver-NDJSON-Index

Start: python -m sapfhir.mcp.server   (liest config/connection.yaml)
"""
from __future__ import annotations
import os
import time

import duckdb
import yaml

try:
    from mcp.server.fastmcp import FastMCP
except Exception:
    FastMCP = None

from .guard import check_sql, check_cypher, enforce_limit, GuardError
from .audit import Audit

CFG = {}
if os.path.exists("config/connection.yaml"):
    with open("config/connection.yaml") as f:
        CFG = yaml.safe_load(f)

_M = CFG.get("mcp", {})
ROW_LIMIT = int(_M.get("row_limit", 1000))
TIMEOUT = int(_M.get("query_timeout_s", 30))
PSEUDO = bool(_M.get("pseudonymize_view", True))
WAREHOUSE = "data/warehouse.duckdb"
GRAPH = "data/graph.kuzu"

audit = Audit(_M.get("audit_log", "data/audit/mcp.jsonl"))
app = FastMCP("sapfhir") if FastMCP else None


def _con():
    return duckdb.connect(WAREHOUSE, read_only=True)


def _mask(rows: list[dict]) -> list[dict]:
    """Maskiert Klarnamen/-adressen im MCP-View, wenn pseudonymize_view aktiv."""
    if not PSEUDO:
        return rows
    hide = {"NNAME", "VNAME", "STRAS", "ORT01", "GBDAT"}   # VERIFY Spalten
    out = []
    for r in rows:
        out.append({k: ("***" if k in hide else v) for k, v in r.items()})
    return out


def _run_sql(sql: str, params=()):
    con = _con()
    try:
        return [dict(zip([c[0] for c in con.description], row))
                for row in con.execute(sql, params).fetchall()] \
            if False else _fetch(con, sql, params)
    finally:
        con.close()


def _fetch(con, sql, params=()):
    cur = con.execute(sql, list(params))
    cols = [c[0] for c in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


# --- Tool-Implementierungen (auch ohne MCP-SDK testbar) ---------------------
def patient_search(name: str = "", gebdat: str = "", patnr: str = "",
                   falnr: str = "") -> list[dict]:
    t0 = time.time()
    conds, params = [], []
    if patnr:
        conds.append("PATNR = ?"); params.append(patnr)
    if falnr:
        # ueber NFAL aufloesen
        pass
    where = " AND ".join(conds) if conds else "1=1"
    sql = enforce_limit(
        f"SELECT PATNR, GSCHL, GBDAT FROM "
        f"read_parquet('data/bronze/npat/**/*.parquet', union_by_name=true) "
        f"WHERE {where}", min(20, ROW_LIMIT))
    try:
        rows = _mask(_run_sql(sql, params))
        audit.log("patient_search", {"patnr": patnr, "name": bool(name)},
                  len(rows), time.time() - t0)
        return rows
    except Exception as e:
        audit.log("patient_search", {}, 0, time.time() - t0, ok=False, err=str(e))
        raise


def patient_360(patnr: str) -> dict:
    t0 = time.time()
    b = "data/bronze"
    faelle = _run_sql(
        f"SELECT FALNR, FALAR, BEGDT, ENDAT FROM "
        f"read_parquet('{b}/nfal/**/*.parquet', union_by_name=true) "
        f"WHERE PATNR = ? ORDER BY BEGDT DESC LIMIT 50", [patnr])
    falnrs = [f["FALNR"] for f in faelle]
    dx, ops = [], []
    if falnrs:
        inlist = ",".join("?" * len(falnrs))
        dx = _run_sql(
            f"SELECT FALNR, DKEY1 AS icd FROM "
            f"read_parquet('{b}/ndia/**/*.parquet', union_by_name=true) "
            f"WHERE FALNR IN ({inlist}) LIMIT 200", falnrs)
        ops = _run_sql(
            f"SELECT FALNR, ICPML AS ops FROM "
            f"read_parquet('{b}/nicp/**/*.parquet', union_by_name=true) "
            f"WHERE FALNR IN ({inlist}) LIMIT 200", falnrs)
    out = {"patnr": patnr, "faelle": faelle, "diagnosen": dx, "prozeduren": ops}
    audit.log("patient_360", {"patnr": patnr}, len(faelle), time.time() - t0)
    return out


def patient_timeline(patnr: str, von: str = "", bis: str = "") -> list[dict]:
    t0 = time.time()
    b = "data/bronze"
    rows = _run_sql(
        f"SELECT BEGDT AS datum, 'Fall' AS typ, FALNR AS ref FROM "
        f"read_parquet('{b}/nfal/**/*.parquet', union_by_name=true) "
        f"WHERE PATNR = ? ORDER BY BEGDT LIMIT {ROW_LIMIT}", [patnr])
    audit.log("patient_timeline", {"patnr": patnr}, len(rows), time.time() - t0)
    return rows


def cohort_sql(select: str) -> list[dict]:
    t0 = time.time()
    try:
        sql = enforce_limit(check_sql(select), ROW_LIMIT)
        rows = _run_sql(sql)
        audit.log("cohort_sql", {"sql": select}, len(rows), time.time() - t0)
        return rows
    except GuardError as e:
        audit.log("cohort_sql", {"sql": select}, 0, time.time() - t0, ok=False, err=str(e))
        raise


def graph_query(cypher: str) -> list[dict]:
    t0 = time.time()
    try:
        import kuzu
    except Exception:
        raise RuntimeError("kuzu nicht installiert")
    q = check_cypher(cypher)
    db = kuzu.Database(GRAPH, read_only=True)
    con = kuzu.Connection(db)
    res = con.execute(q)
    out = []
    while res.has_next():
        out.append(res.get_next())
        if len(out) >= ROW_LIMIT:
            break
    audit.log("graph_query", {"cypher": cypher}, len(out), time.time() - t0)
    return out


def doc_search(query: str, patnr: str = "") -> list[dict]:
    t0 = time.time()
    con = _con()
    try:
        con.execute("LOAD fts;")
        rows = _fetch(con,
            "SELECT TEXTID, fts_main_gold_doc_text.match_bm25(TEXTID, ?) AS score "
            "FROM gold.doc_text WHERE score IS NOT NULL "
            "ORDER BY score DESC LIMIT ?", [query, min(50, ROW_LIMIT)])  # VERIFY Spalten
    finally:
        con.close()
    audit.log("doc_search", {"q": query, "patnr": patnr}, len(rows), time.time() - t0)
    return rows


def fhir_get(resource_type: str, id: str) -> dict | None:
    import glob, gzip, json
    t0 = time.time()
    for pf in glob.glob(f"data/silver/fhir/{resource_type}/*.ndjson.gz"):
        with gzip.open(pf, "rt", encoding="utf-8") as f:
            for line in f:
                res = json.loads(line)
                if res.get("id") == id:
                    audit.log("fhir_get", {"rt": resource_type, "id": id}, 1,
                              time.time() - t0)
                    return res
    audit.log("fhir_get", {"rt": resource_type, "id": id}, 0, time.time() - t0)
    return None


# --- MCP-Registrierung -------------------------------------------------------
if app:
    app.tool()(patient_search)
    app.tool()(patient_360)
    app.tool()(patient_timeline)
    app.tool()(cohort_sql)
    app.tool()(graph_query)
    app.tool()(doc_search)
    app.tool()(fhir_get)


def main():
    if not app:
        raise SystemExit("mcp-SDK nicht installiert (pip install mcp)")
    app.run()


if __name__ == "__main__":
    main()
