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
    from fastapi import FastAPI, Header, HTTPException
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

# --- Berechtigung (docs/BERECHTIGUNGSKONZEPT.md) ---
_AZCFG = CFG.get("authz", {}) if isinstance(CFG, dict) else {}
AUTHZ_ENABLED = bool(_AZCFG.get("enabled", False))
try:
    from sapfhir.authz.service import Authz, DuckDBBackend
    AUTHZ = Authz(DuckDBBackend(WAREHOUSE), roles=_AZCFG.get("roles", {}),
                  expand=bool(_AZCFG.get("expand", True)))
except Exception:
    AUTHZ = None


def _audit_access(login, patnr, erlaubt):
    """Best-effort Zugriffs-Audit (eigene rw-Verbindung; blockiert nie)."""
    try:
        con = duckdb.connect(WAREHOUSE)
        try:
            con.execute("CREATE SCHEMA IF NOT EXISTS auth")
            con.execute("CREATE TABLE IF NOT EXISTS auth.zugriff_audit"
                        "(ts TIMESTAMP, login VARCHAR, patnr VARCHAR, erlaubt BOOLEAN)")
            con.execute("INSERT INTO auth.zugriff_audit VALUES (now(), ?, ?, ?)",
                        [login, patnr, bool(erlaubt)])
        finally:
            con.close()
    except Exception:
        pass


app = FastAPI(title="CliniBots Patient Insight") if FastAPI else None


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

    @app.get("/api/analytics/kpis")
    def kpis():
        one = lambda sql: (_q(sql) or [{}])[0]
        return JSONResponse({
            "faelle": one("SELECT COUNT(*) n FROM mcp.fall "
                          "WHERE COALESCE(TRIM(STORN),'') NOT IN ('X','1')").get("n"),
            "offen": one("SELECT COUNT(*) n FROM mcp.fall "
                         "WHERE COALESCE(TRIM(STORN),'') NOT IN ('X','1') AND (ENDDT IS NULL "
                         "OR substr(CAST(ENDDT AS VARCHAR),1,4) IN ('0101','9999'))"
                         ).get("n"),
            "patienten": one("SELECT COUNT(*) n FROM mcp.patient "
                             "WHERE COALESCE(TRIM(STORN),'') NOT IN ('X','1')").get("n"),
            "labor": one("SELECT COUNT(*) n FROM mcp.labor").get("n"),
            "vwd_mittel": one("SELECT AVG(vwd_tage) v FROM gold.verweildauer").get("v"),
            "vwd_median": one("SELECT MEDIAN(vwd_tage) v FROM gold.verweildauer").get("v"),
        })

    @app.get("/api/analytics/vwd_histogramm")
    def vwd_histogramm():
        return JSONResponse(_q(
            "SELECT bucket, COUNT(*) AS n FROM (SELECT CASE"
            " WHEN vwd_tage <= 1 THEN '0-1' WHEN vwd_tage <= 3 THEN '2-3'"
            " WHEN vwd_tage <= 6 THEN '4-6' WHEN vwd_tage <= 10 THEN '7-10'"
            " WHEN vwd_tage <= 15 THEN '11-15' WHEN vwd_tage <= 21 THEN '16-21'"
            " ELSE '>21' END AS bucket, vwd_tage FROM gold.verweildauer"
            " WHERE vwd_tage >= 0) GROUP BY bucket"))

    @app.get("/api/analytics/alter_geschlecht")
    def alter_geschlecht():
        # GBDAT ist in der maskierten Schicht nur das Geburtsjahr (pseudonymize).
        return JSONResponse(_q(
            "SELECT CAST(LEAST(FLOOR((year(current_date) - "
            "  TRY_CAST(substr(CAST(GBDAT AS VARCHAR),1,4) AS INT)) / 10) * 10, 90)"
            "  AS INT) AS band, GSCHL, COUNT(*) AS n "
            "FROM mcp.patient WHERE COALESCE(TRIM(STORN),'') NOT IN ('X','1') "
            "  AND TRY_CAST(substr(CAST(GBDAT AS VARCHAR),1,4) AS INT) "
            "      BETWEEN 1900 AND year(current_date) "
            "GROUP BY 1, 2 ORDER BY 1"))

    @app.get("/api/analytics/fachrichtungen")
    def fachrichtungen():
        return JSONResponse(_q(
            "SELECT COALESCE(NULLIF(TRIM(FACHR),''),'ohne') AS fachr, COUNT(*) AS n "
            "FROM mcp.fall WHERE COALESCE(TRIM(STORN),'') NOT IN ('X','1') "
            "GROUP BY 1 ORDER BY n DESC LIMIT 12"))

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
    @app.get("/api/authz/whoami")
    def whoami(x_user: str | None = Header(default=None)):
        if not AUTHZ_ENABLED:
            return JSONResponse({"authz": "disabled", "login": x_user,
                                 "hinweis": "authz.enabled=false → offener Dev-Betrieb"})
        who = AUTHZ.whoami(x_user) if AUTHZ else {"login": x_user, "scope": "NONE"}
        return JSONResponse({"authz": "enabled", **who})

    @app.get("/api/patient360/{patnr}")
    def patient360(patnr: str, x_user: str | None = Header(default=None)):
        # Deny-by-default, wenn Berechtigung aktiv (docs/BERECHTIGUNGSKONZEPT.md).
        if AUTHZ_ENABLED:
            erlaubt = bool(AUTHZ and AUTHZ.may_see_patient(x_user, patnr))
            _audit_access(x_user, patnr, erlaubt)
            if not erlaubt:
                raise HTTPException(status_code=403,
                                    detail="Kein Zugriff auf diesen Patienten (Berechtigung).")
        patient = _q(
            "SELECT GSCHL, GBDAT, TODKZ FROM mcp.patient "
            "WHERE PATNR = ? AND COALESCE(TRIM(STORN),'') NOT IN ('X','1')", [patnr])
        faelle = _q(
            "SELECT FALNR, FALAR, BEGDT, ENDDT, FACHR, "
            "  CASE WHEN ENDDT IS NULL OR substr(CAST(ENDDT AS VARCHAR),1,4)"
            "       IN ('0101','9999') THEN 1 ELSE 0 END AS offen "
            "FROM mcp.fall WHERE PATNR = ? AND COALESCE(TRIM(STORN),'') NOT IN ('X','1') "
            "ORDER BY BEGDT DESC LIMIT 50", [patnr])
        diagnosen = _q(
            "SELECT d.DIADT, d.DKEY1, d.DITXT, d.KHDIA, d.FALNR "
            "FROM mcp.diagnose d JOIN mcp.fall f USING (FALNR) "
            "WHERE f.PATNR = ? AND COALESCE(TRIM(d.STORN),'') NOT IN ('X','1') "
            "ORDER BY d.DIADT DESC LIMIT 50", [patnr])
        labor = _q(
            "SELECT KATTEXT, BEFDT, WERT, EINH, REFBER, ABNORMAL FROM mcp.labor "
            "WHERE PATNR = ? AND BEFDT IS NOT NULL "
            "ORDER BY KATTEXT, BEFDT LIMIT 500", [patnr])
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
            "   d.DKEY1 || COALESCE(' ' || d.DITXT, '')"
            "   FROM mcp.diagnose d JOIN mcp.fall f USING (FALNR) WHERE f.PATNR = ?"
            " UNION ALL SELECT p.BGDOP, 'Prozedur', p.FALNR,"
            "   COALESCE(p.BTEXT, CAST(p.ICPML AS VARCHAR))"
            "   FROM mcp.prozedur p JOIN mcp.fall f USING (FALNR) WHERE f.PATNR = ?"
            " UNION ALL SELECT l.BEFDT, 'Labor', l.FALNR,"
            "   l.KATTEXT || ': ' || l.WERT || ' ' || COALESCE(l.EINH,'')"
            "   FROM mcp.labor l WHERE l.PATNR = ?"
            " UNION ALL SELECT dk.DODAT, 'Dokument', dk.FALNR,"
            "   'Dokument ' || COALESCE(dk.DOKAR,'') FROM mcp.dokument dk"
            "   WHERE dk.PATNR = ? AND COALESCE(TRIM(dk.STORN),'') NOT IN ('X','1')"
            ") WHERE datum IS NOT NULL ORDER BY datum DESC LIMIT 300",
            [patnr] * 6)
        return JSONResponse({"patnr": patnr,
                             "patient": patient[0] if patient else None,
                             "faelle": faelle, "diagnosen": diagnosen,
                             "labor": labor, "timeline": timeline})

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
