# -*- coding: utf-8 -*-
"""Dashboard-Backend (FastAPI, nur 127.0.0.1). Liefert die SPA aus web/ und JSON-APIs
aus den Gold-Views. Kein Adminrecht: Port > 1024, Bind nur loopback.

Start: python -m sapfhir.api.app
"""
from __future__ import annotations
import os

import duckdb
import yaml

try:
    from fastapi import FastAPI
    from fastapi.responses import JSONResponse
    from fastapi.staticfiles import StaticFiles
    import uvicorn
except Exception:
    FastAPI = None

CFG = {}
if os.path.exists("config/connection.yaml"):
    with open("config/connection.yaml") as f:
        CFG = yaml.safe_load(f)
WAREHOUSE = os.environ.get("SAPFHIR_WAREHOUSE", "data/warehouse.duckdb")

app = FastAPI(title="SAP_FIHR Dashboard") if FastAPI else None


def _q(sql: str, params: list | None = None):
    con = duckdb.connect(WAREHOUSE, read_only=True)
    try:
        cur = con.execute(sql, params or [])
        cols = [c[0] for c in cur.description]
        return [{c: (v.isoformat() if hasattr(v, "isoformat") else v)
                 for c, v in zip(cols, r)} for r in cur.fetchall()]
    except duckdb.Error:
        return []
    finally:
        con.close()


if app:
    @app.get("/api/monitor/state")
    def monitor_state():
        return JSONResponse(_q(
            "SELECT schema_name, table_name, phase, rows_seen, change_seq, "
            "last_run_ts, last_duration FROM _meta.extract_state ORDER BY rows_seen DESC"))

    @app.get("/api/monitor/reconciliation")
    def monitor_reconciliation():
        return JSONResponse(_q(
            "SELECT table_name, source_rows, local_rows, delta, status, ts FROM ("
            "  SELECT *, row_number() OVER (PARTITION BY table_name "
            "         ORDER BY ts DESC) rn FROM _meta.reconciliation"
            ") WHERE rn = 1 ORDER BY table_name"))

    @app.get("/api/monitor/runs")
    def monitor_runs():
        return JSONResponse(_q(
            "SELECT ts, schema_name, table_name, phase, rows, note "
            "FROM _meta.run_log ORDER BY ts DESC LIMIT 100"))

    @app.get("/api/monitor/dias")
    def monitor_dias():
        return JSONResponse(_q(
            "SELECT ts, dias_genutzt, in_registry, luecken "
            "FROM _meta.dias_coverage ORDER BY ts DESC LIMIT 1"))

    @app.get("/api/monitor/silver")
    def monitor_silver():
        return JSONResponse(_q(
            "SELECT run_id, table_name, rows, ts FROM silver.silver_runs "
            "ORDER BY ts DESC LIMIT 100"))

    @app.get("/api/analytics/faelle_monat")
    def faelle_monat():
        return JSONResponse(_q("SELECT * FROM gold.faelle_monat"))

    @app.get("/api/analytics/top_diagnosen")
    def top_diagnosen():
        return JSONResponse(_q("SELECT * FROM gold.top_diagnosen"))

    @app.get("/api/analytics/top_prozeduren")
    def top_prozeduren():
        return JSONResponse(_q("SELECT * FROM gold.top_prozeduren"))

    @app.get("/api/analytics/verweildauer")
    def verweildauer():
        return JSONResponse(_q(
            "SELECT AVG(vwd_tage) AS mittel, MEDIAN(vwd_tage) AS median, "
            "COUNT(*) AS n FROM gold.verweildauer"))

    @app.get("/api/analytics/belegung")
    def belegung():
        return JSONResponse(_q("SELECT * FROM gold.belegung_oe"))

    # Patient 360 (CONCEPT §8, Seite 3): Read-only-Zeitstrahl aus der
    # MASKIERTEN mcp.*-Schicht — dieselbe Datenoberflaeche wie der MCP-Server,
    # d.h. pseudonymize_view greift auch hier.
    @app.get("/api/patient360/{patnr}")
    def patient360(patnr: str):
        faelle = _q(
            "SELECT FALNR, FALAR, BEGDT, ENDDT, FACHR FROM mcp.fall "
            "WHERE PATNR = ? AND COALESCE(STORN,'') IN ('','0') "
            "ORDER BY BEGDT DESC LIMIT 50", [patnr])
        timeline = _q(
            "SELECT * FROM ("
            " SELECT BEGDT AS datum, 'Fall' AS typ, FALNR AS ref,"
            "        FALAR AS detail FROM mcp.fall WHERE PATNR = ?"
            " UNION ALL SELECT b.BWIDT, 'Bewegung', b.FALNR,"
            "   COALESCE(rb.\"TEXT\", CAST(b.BEWTY AS VARCHAR))"
            "   FROM mcp.bewegung b JOIN mcp.fall f USING (FALNR)"
            "   LEFT JOIN ref.bewegungstyp rb"
            "     ON CAST(b.BEWTY AS VARCHAR) = rb.\"BEWTY\" WHERE f.PATNR = ?"
            " UNION ALL SELECT d.DIADT, 'Diagnose', d.FALNR,"
            "   COALESCE(d.DITXT, d.DKEY1)"
            "   FROM mcp.diagnose d JOIN mcp.fall f USING (FALNR) WHERE f.PATNR = ?"
            " UNION ALL SELECT p.BGDOP, 'Prozedur', p.FALNR,"
            "   COALESCE(p.BTEXT, CAST(p.ICPML AS VARCHAR))"
            "   FROM mcp.prozedur p JOIN mcp.fall f USING (FALNR) WHERE f.PATNR = ?"
            " UNION ALL SELECT l.BEFDT, 'Labor', l.FALNR,"
            "   l.KATTEXT || ': ' || l.WERT || ' ' || COALESCE(l.EINH,'')"
            "   FROM mcp.labor l WHERE l.PATNR = ?"
            ") WHERE datum IS NOT NULL ORDER BY datum DESC LIMIT 300",
            [patnr] * 5)
        return JSONResponse({"patnr": patnr, "faelle": faelle,
                             "timeline": timeline})

    web_dir = os.path.join(os.path.dirname(__file__), "..", "..", "..", "web")
    if os.path.isdir(web_dir):
        app.mount("/", StaticFiles(directory=web_dir, html=True), name="web")


def main():
    if not app:
        raise SystemExit("fastapi/uvicorn nicht installiert")
    a = CFG.get("api", {})
    uvicorn.run(app, host=a.get("host", "127.0.0.1"), port=int(a.get("port", 8471)))


if __name__ == "__main__":
    main()
