# -*- coding: utf-8 -*-
"""Dashboard-Backend (FastAPI, nur 127.0.0.1). Liefert die SPA aus web/ und JSON-APIs
aus den Gold-Views. Kein Adminrecht: Port > 1024, Bind nur loopback.

Start: python -m sapfhir.api.app
"""
from __future__ import annotations
import os
import threading

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
    from sapfhir.authz import resolver as _azres
    AUTHZ = Authz(DuckDBBackend(WAREHOUSE), roles=_AZCFG.get("roles", {}),
                  expand=bool(_AZCFG.get("expand", True)),
                  max_set_leaves=int(_AZCFG.get("max_set_leaves",
                                                _azres.MAX_DEPT_SET_LEAVES)),
                  max_union_leaves=int(_AZCFG.get("max_union_leaves",
                                                  _azres.MAX_UNION_LEAVES)))
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

# --- Ladeknopf: Kohorten-Backfill "aktuelle Stationspatienten" (R21/R22/R23) -
# Scope ist ein EXPLIZITER Parameter, keine stille Annahme (Lehre aus R22):
#   "history" (DEFAULT) = inkl. kompletter Fallhistorie -> speist die
#     Patientensicht (Patient 360, siehe GESAMTKONZEPT UC-K1) mit echtem Kontext.
#   "current" = nur die aktuell offenen Faelle (schneller Probelauf).
# Details/Begruendung: docs/VERIFY_LOG_R8-R13.md R21-R23.
_COHORT_LOCK = threading.Lock()
_COHORT_JOB = {"state": "idle", "log": [], "result": None, "error": None,
              "finished_at": None, "load_scope": None}


def _cohort_progress(msg: str):
    _COHORT_JOB["log"].append(msg)
    _COHORT_JOB["log"] = _COHORT_JOB["log"][-40:]


def _run_cohort_job(load_scope: str, with_fhir: bool):
    import datetime as _dt
    try:
        if not os.environ.get("SAPFHIR_PRIVACY_SECRET"):
            try:
                import keyring
                env = (CFG or {}).get("source", {}).get("environment", "higl-main")
                v = keyring.get_password("sapfhir:privacy", env)
                if v:
                    os.environ["SAPFHIR_PRIVACY_SECRET"] = v
            except Exception:
                pass
        from sapfhir.extract import cohort as _cohort
        from sapfhir.gold import build as _gold
        rep = _cohort.run("config/connection.yaml", "current_inpatients",
                          os.path.dirname(WAREHOUSE) or "data",
                          load_scope=load_scope, progress=_cohort_progress)
        # Das Dashboard (kpis/belegung/patient360/DQ) liest ausschliesslich
        # gold.*/mcp.*-Views ueber bronze_current — die FHIR-NDJSON-Ausleitung
        # (silver.fhir_index) speist NUR den separaten MCP-Tool-Server und ist
        # mit dem grossen NGPA/NPER-Practitioner-Merge (~500k Zeilen) der
        # dominante Zeitkostenfaktor. Deshalb standardmaessig UEBERSPRUNGEN;
        # separat erzeugbar (with_fhir=True bzw. CLI `sapfhir.fhir.ndjson --full`).
        if with_fhir:
            from sapfhir.fhir import ndjson as _ndjson
            _cohort_progress("FHIR-Ausleitung (fuer MCP-Server) ...")
            fhir_res = _ndjson.run(CFG, warehouse=WAREHOUSE, full=True)
            _cohort_progress(f"FHIR: {fhir_res.get('counts')}")
        else:
            _cohort_progress("FHIR-Ausleitung uebersprungen (Dashboard braucht sie nicht; "
                             "fuer MCP-Zugriff separat erzeugen).")
        _cohort_progress("Gold-Marts + DQ ...")
        _gold.build(warehouse=WAREHOUSE)
        _cohort_progress("fertig.")
        _COHORT_JOB["result"] = rep
        _COHORT_JOB["state"] = "done"
    except Exception as e:
        _COHORT_JOB["error"] = str(e)
        _COHORT_JOB["state"] = "error"
    finally:
        _COHORT_JOB["finished_at"] = _dt.datetime.now().isoformat(timespec="seconds")


def _start_cohort_job(load_scope: str = "history", with_fhir: bool = False) -> dict:
    if load_scope not in ("current", "history"):
        load_scope = "history"
    with _COHORT_LOCK:
        if _COHORT_JOB["state"] == "running":
            return {"started": False, "error": "Kohorten-Ladung laeuft bereits"}
        _COHORT_JOB.update(state="running", log=[], result=None, error=None,
                           finished_at=None, load_scope=load_scope)
    t = threading.Thread(target=_run_cohort_job, args=(load_scope, with_fhir), daemon=True)
    t.start()
    return {"started": True, "load_scope": load_scope}


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
    @app.post("/api/cohort/load")
    def cohort_load(scope: str = "history", fhir: bool = False):
        return JSONResponse(_start_cohort_job(load_scope=scope, with_fhir=fhir))

    @app.get("/api/cohort/status")
    def cohort_status():
        return JSONResponse(_COHORT_JOB)

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

    @app.get("/api/patients")
    def patients_list(page: int = 1, page_size: int = 50, q: str = "",
                      x_user: str | None = Header(default=None)):
        """Gepagte Patientenliste (Facettensuche v0, ROADMAP P1.2) fuer den
        Patient-360-Tab — Auswahl statt Blindeingabe der PATNR."""
        page = max(1, page)
        page_size = page_size if page_size in (50, 100, 200) else 50
        where = ["COALESCE(TRIM(p.STORN),'') NOT IN ('X','1')"]
        params: list = []
        q = q.strip()
        if q:
            where.append('p.PATNR LIKE ?')
            params.append(f"%{q}%")
        where_sql = " AND ".join(where)
        total = (_q(f"SELECT COUNT(*) n FROM mcp.patient p WHERE {where_sql}",
                    params) or [{}])[0].get("n", 0)
        rows = _q(
            f"SELECT p.PATNR, p.GSCHL, p.GBDAT, p.TODKZ, "
            f"  COUNT(f.FALNR) AS faelle, "
            f"  SUM(CASE WHEN f.ENDDT IS NULL OR substr(CAST(f.ENDDT AS VARCHAR),1,4) "
            f"       IN ('0101','9999') THEN 1 ELSE 0 END) AS offene_faelle, "
            f"  MAX(f.BEGDT) AS letzte_aufnahme "
            f"FROM mcp.patient p "
            f"LEFT JOIN mcp.fall f ON f.PATNR = p.PATNR "
            f"  AND COALESCE(TRIM(f.STORN),'') NOT IN ('X','1') "
            f"WHERE {where_sql} "
            f"GROUP BY p.PATNR, p.GSCHL, p.GBDAT, p.TODKZ "
            f"ORDER BY letzte_aufnahme DESC NULLS LAST, p.PATNR "
            f"LIMIT ? OFFSET ?",
            [*params, page_size, (page - 1) * page_size])
        if AUTHZ_ENABLED and AUTHZ:
            # Best-effort Zeilenfilter (Phase-1-Stand, docs/BERECHTIGUNGSKONZEPT.md):
            # kein SQL-Push-down der Berechtigungskette, daher kann die Seite dann
            # weniger als page_size sichtbare Zeilen enthalten.
            rows = [r for r in rows if AUTHZ.may_see_patient(x_user, r["PATNR"])]
        return JSONResponse({"total": total, "page": page, "page_size": page_size,
                             "rows": rows})

    @app.get("/api/fall/{falnr}")
    def fall_detail(falnr: str, x_user: str | None = Header(default=None)):
        """Fall-Drilldown (ROADMAP P2.5 v1): Kopf + Bewegungskette + Diagnosen +
        Prozeduren. Bewegungskette per ORDER BY BWIDT/LFDNR (Methodik: NBEW-Kette,
        nicht NFAL-Daten). DRG/Erloes + MD-Badge folgen, sobald NDRG/ZNRKT in der
        Kohorte liegen."""
        kopf = _q(
            "SELECT f.FALNR, f.PATNR, f.FALAR, f.BEGDT, f.ENDDT, f.FACHR, f.STATU, "
            "  CASE WHEN f.ENDDT IS NULL OR substr(CAST(f.ENDDT AS VARCHAR),1,4) "
            "       IN ('0101','9999') THEN 1 ELSE 0 END AS offen "
            "FROM mcp.fall f WHERE f.FALNR = ? "
            "  AND COALESCE(TRIM(f.STORN),'') NOT IN ('X','1')", [falnr])
        if not kopf:
            raise HTTPException(status_code=404, detail="Fall nicht gefunden")
        if AUTHZ_ENABLED:
            patnr = kopf[0].get("PATNR")
            erlaubt = bool(AUTHZ and AUTHZ.may_see_patient(x_user, patnr))
            _audit_access(x_user, patnr, erlaubt)
            if not erlaubt:
                raise HTTPException(status_code=403, detail="Kein Zugriff (Berechtigung).")
        bewegungen = _q(
            "SELECT b.LFDNR, b.BEWTY, b.BWART, b.BWIDT, b.BWEDT, "
            "  COALESCE(b.ORGPF, b.ORGFA) AS oe, r.\"TEXT\" AS typ_text, "
            "  ro.\"TEXT\" AS oe_name "
            "FROM mcp.bewegung b "
            "LEFT JOIN ref.bewegungstyp r ON CAST(b.BEWTY AS VARCHAR) = r.\"BEWTY\" "
            "LEFT JOIN ref.oe ro ON CAST(COALESCE(b.ORGPF,b.ORGFA) AS VARCHAR) = ro.ORGID "
            "WHERE b.FALNR = ? AND COALESCE(TRIM(b.STORN),'') NOT IN ('X','1') "
            "ORDER BY b.BWIDT, b.LFDNR", [falnr])
        diagnosen = _q(
            "SELECT DIADT, DKEY1, DITXT, KHDIA FROM mcp.diagnose "
            "WHERE FALNR = ? AND COALESCE(TRIM(STORN),'') NOT IN ('X','1') "
            "ORDER BY DIADT DESC LIMIT 100", [falnr])
        prozeduren = _q(
            "SELECT BGDOP, ICPML, BTEXT FROM mcp.prozedur "
            "WHERE FALNR = ? AND COALESCE(TRIM(STORN),'') NOT IN ('X','1') "
            "ORDER BY BGDOP DESC LIMIT 100", [falnr])
        return JSONResponse({"kopf": kopf[0], "bewegungen": bewegungen,
                             "diagnosen": diagnosen, "prozeduren": prozeduren})

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
        # Anreicherung je Fall: Hauptdiagnose + DRG (mit Bezeichner aus dem Katalog).
        # mcp.drg/drg_katalog existieren erst nach einem Kohorten-Lauf mit NDRG —
        # deshalb defensiv (R26-Muster: Existenz pruefen statt UNION-Blindflug).
        # Diagnose je Fall: Hauptdiagnose (KHDIA='X') bevorzugt; ambulante Faelle
        # haben meist keine formale HD -> Fallback = juengste dokumentierte Diagnose.
        # EINE Zeile je Fall via QUALIFY (Review-Fix: arg_max-Aggregate liefen
        # unabhaengig und konnten hd_icd/hd_text/ist_hd aus VERSCHIEDENEN Zeilen
        # mischen; NULL-KHDIA sortierte in DuckDB-Structs zudem VOR 'X').
        # Kodetext-Fallback aus ref.icd (NKDI), wenn DITXT leer ist. Join ueber
        # (DKAT1, DKEY1) — NDIA fuehrt den Katalog je Diagnose selbst; ein Join nur
        # ueber den Kode traf sonst z.B. bei C-Kodes den ICD-O-Katalog '90'
        # (Topographie) statt ICD-10-GM (R30). ref.icd optional -> Existenzcheck,
        # sonst reisst ein fehlender NKDI-Load die ganze Diagnose-Spalte mit.
        hat_icd = bool(_q("SELECT 1 FROM information_schema.tables "
                          "WHERE table_schema='ref' AND table_name='icd'"))
        txt_expr = ("COALESCE(NULLIF(TRIM(d.DITXT),''), NULLIF(TRIM(k.\"TEXT\"),''))"
                    if hat_icd else "NULLIF(TRIM(d.DITXT),'')")
        icd_join = ("LEFT JOIN ref.icd k ON TRIM(k.DKAT) = TRIM(d.DKAT1) "
                    "  AND TRIM(k.DKEY) = TRIM(d.DKEY1) " if hat_icd else "")
        hd = {r["FALNR"]: r for r in _q(
            f"SELECT d.FALNR, d.DKEY1 AS hd_icd, {txt_expr} AS hd_text, "
            "  (COALESCE(d.KHDIA,'')='X') AS ist_hd "
            "FROM mcp.diagnose d JOIN mcp.fall f USING (FALNR) "
            f"{icd_join}"
            "WHERE f.PATNR = ? "
            "  AND COALESCE(TRIM(d.STORN),'') NOT IN ('X','1') "
            "QUALIFY row_number() OVER (PARTITION BY d.FALNR "
            "  ORDER BY (COALESCE(d.KHDIA,'')='X') DESC, d.DIADT DESC, d.DKEY1) = 1",
            [patnr])}
        # Fachabteilung + Station je Fall: juengste Bewegung; Namen per LEFT JOIN
        # ref.oe (kein Voll-Katalog-Fetch je Request; fehlt ref.oe -> Namen NULL)
        oe = {r["FALNR"]: r for r in _q(
            "SELECT x.FALNR, x.orgfa, x.orgpf, ra.\"TEXT\" AS fach_name, "
            "  rp.\"TEXT\" AS station_name FROM ("
            "  SELECT b.FALNR, "
            "    arg_max(NULLIF(TRIM(b.ORGFA),''), b.BWIDT) AS orgfa, "
            "    arg_max(NULLIF(TRIM(b.ORGPF),''), b.BWIDT) AS orgpf "
            "  FROM mcp.bewegung b JOIN mcp.fall f USING (FALNR) "
            "  WHERE f.PATNR = ? AND COALESCE(TRIM(b.STORN),'') NOT IN ('X','1') "
            "  GROUP BY b.FALNR) x "
            "LEFT JOIN ref.oe ra ON x.orgfa = ra.ORGID "
            "LEFT JOIN ref.oe rp ON x.orgpf = rp.ORGID", [patnr])}
        drg = {r["FALNR"]: r for r in _q(
            "SELECT g.PATCASEID AS FALNR, "
            "  arg_max(g.DRG_CODE, g.DRG_SEQNO) AS drg, "
            "  arg_max(g.COST_WEIGHT, g.DRG_SEQNO) AS bwr "
            "FROM mcp.drg g JOIN mcp.fall f ON f.FALNR = g.PATCASEID "
            "WHERE f.PATNR = ? AND COALESCE(TRIM(g.CANCEL_FLAG),'') NOT IN ('X','1') "
            "GROUP BY g.PATCASEID", [patnr])}
        # Katalog-Schluessel = 'DRG'+<Katalogjahr 2-stellig>+<Kode> (z.B. DRG23H41C,
        # R27 live entschluesselt) -> Kode extrahieren, juengstes Jahr gewinnt.
        kat = {r["code"]: (r["bez"] or "").strip() for r in _q(
            "SELECT substr(DRG, 6) AS code, "
            "  arg_max(DRG_Bezeichnung, substr(DRG, 4, 2)) AS bez "
            "FROM mcp.drg_katalog WHERE DRG LIKE 'DRG%' GROUP BY 1")} if drg else {}
        for f in faelle:
            h = hd.get(f["FALNR"], {})
            g = drg.get(f["FALNR"], {})
            o = oe.get(f["FALNR"], {})
            f["hd_icd"] = h.get("hd_icd")
            f["hd_text"] = h.get("hd_text")
            f["ist_hd"] = bool(h.get("ist_hd"))
            f["drg"] = g.get("drg")
            f["drg_bez"] = kat.get(g.get("drg"))
            f["bwr"] = g.get("bwr")
            f["fach"] = o.get("orgfa")
            f["fach_name"] = o.get("fach_name")
            f["station"] = o.get("orgpf")
            f["station_name"] = o.get("station_name")
        diagnosen = _q(
            "SELECT d.DIADT, d.DKEY1, d.DITXT, d.KHDIA, d.FALNR "
            "FROM mcp.diagnose d JOIN mcp.fall f USING (FALNR) "
            "WHERE f.PATNR = ? AND COALESCE(TRIM(d.STORN),'') NOT IN ('X','1') "
            "ORDER BY d.DIADT DESC LIMIT 200", [patnr])
        # Problemliste: Diagnosen nach ICD gruppiert (CONCEPT_P360_DARSTELLUNG §2.3 —
        # POV-Evidenz: -16% Zeit, 3,4% statt 7,7% Fehler vs. flache Encounter-Liste)
        diagnosen_gruppen = _q(
            "SELECT d.DKEY1, MAX(NULLIF(TRIM(d.DITXT),'')) AS text, COUNT(*) AS n, "
            "  MIN(d.DIADT) AS erst, MAX(d.DIADT) AS letzt, "
            "  MAX(CASE WHEN d.KHDIA='X' THEN 1 ELSE 0 END) AS hd "
            "FROM mcp.diagnose d JOIN mcp.fall f USING (FALNR) "
            "WHERE f.PATNR = ? AND COALESCE(TRIM(d.STORN),'') NOT IN ('X','1') "
            "  AND COALESCE(TRIM(d.DKEY1),'') <> '' "
            "GROUP BY d.DKEY1 ORDER BY letzt DESC", [patnr])
        labor = _q(
            "SELECT KATTEXT, BEFDT, WERT, EINH, REFBER, ABNORMAL FROM mcp.labor "
            "WHERE PATNR = ? AND BEFDT IS NOT NULL "
            "ORDER BY KATTEXT, BEFDT LIMIT 500", [patnr])
        # Timeline-UNION nur aus tatsaechlich vorhandenen mcp.*-Tabellen bauen:
        # in Kohorten-Phase 0 fehlen mcp.labor/mcp.dokument (NDOC/N2LABOR nicht
        # geladen) — eine fehlende Tabelle liess frueher die GANZE UNION scheitern
        # und die Timeline blieb leer (R26).
        vorhandene = {r["table_name"] for r in _q(
            "SELECT table_name FROM information_schema.tables "
            "WHERE table_schema='mcp'")}
        teile = [
            ("fall", " SELECT BEGDT AS datum, 'Fall' AS typ, FALNR AS ref,"
                     "        FALAR AS detail FROM mcp.fall WHERE PATNR = ?"),
            ("bewegung", " SELECT b.BWIDT, 'Bewegung', b.FALNR,"
                         "   COALESCE(rb.\"TEXT\", CAST(b.BEWTY AS VARCHAR))"
                         "   FROM mcp.bewegung b JOIN mcp.fall f USING (FALNR)"
                         "   LEFT JOIN ref.bewegungstyp rb"
                         "     ON CAST(b.BEWTY AS VARCHAR) = rb.\"BEWTY\" WHERE f.PATNR = ?"),
            ("diagnose", " SELECT d.DIADT, 'Diagnose', d.FALNR,"
                         "   d.DKEY1 || COALESCE(' ' || d.DITXT, '')"
                         "   FROM mcp.diagnose d JOIN mcp.fall f USING (FALNR) WHERE f.PATNR = ?"),
            ("prozedur", " SELECT p.BGDOP, 'Prozedur', p.FALNR,"
                         "   COALESCE(p.BTEXT, CAST(p.ICPML AS VARCHAR))"
                         "   FROM mcp.prozedur p JOIN mcp.fall f USING (FALNR) WHERE f.PATNR = ?"),
            ("labor", " SELECT l.BEFDT, 'Labor', l.FALNR,"
                      "   l.KATTEXT || ': ' || l.WERT || ' ' || COALESCE(l.EINH,'')"
                      "   FROM mcp.labor l WHERE l.PATNR = ?"),
            ("dokument", " SELECT dk.DODAT, 'Dokument', dk.FALNR,"
                         "   'Dokument ' || COALESCE(dk.DOKAR,'') FROM mcp.dokument dk"
                         "   WHERE dk.PATNR = ? AND COALESCE(TRIM(dk.STORN),'') NOT IN ('X','1')"),
        ]
        aktiv = [(t, sql) for t, sql in teile if t in vorhandene]
        timeline = _q(
            "SELECT * FROM (" + " UNION ALL".join(sql for _, sql in aktiv) +
            ") WHERE datum IS NOT NULL ORDER BY datum DESC LIMIT 300",
            [patnr] * len(aktiv)) if aktiv else []
        return JSONResponse({"patnr": patnr,
                             "patient": patient[0] if patient else None,
                             "faelle": faelle, "diagnosen": diagnosen,
                             "diagnosen_gruppen": diagnosen_gruppen,
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
