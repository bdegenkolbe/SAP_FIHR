# -*- coding: utf-8 -*-
"""Tests Live-Analyse-MCP (sapfhir.live): T-SQL-Guard, Verkryptung, lernende
Wissensschicht, Service-Werkzeuge — ohne Datenbank (FakeDB)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import pytest
import yaml

from sapfhir.live import tsql_guard as G
from sapfhir.live.knowledge import Knowledge
from sapfhir.live.server import LiveService, register, _make_app

ROOT = os.path.join(os.path.dirname(__file__), "..")
PCFG = yaml.safe_load(open(os.path.join(ROOT, "config", "live_mcp.yaml"), encoding="utf-8"))


def _pol(**kw):
    base = dict(pii={"NPAT": {"NNAME", "VNAME", "GBDAT", "STRAS"}, "NFAL": {"KZTXT"}},
                pii_dates={"GBDAT"}, mass_tables={"NLEI"})
    base.update(kw)
    return G.Policy(**base)


# --- Guard: Grundregeln --------------------------------------------------------
@pytest.mark.parametrize("sql", [
    "DELETE FROM sap.NPAT",
    "SELECT 1; DROP TABLE sap.NPAT",
    "SELECT * INTO sap.X FROM sap.NFAL",
    "EXEC xp_cmdshell 'dir'",
    "SELECT * FROM OPENROWSET('SQLNCLI','x','select 1')",
    "SELECT PATNR FROM sap.NFAL -- kommentar",
    "SELECT PATNR /* x */ FROM sap.NFAL",
    "SELECT @@VERSION",
    "SELECT PATNR FROM sap.NFAL WITH (UPDLOCK)",
    "SELECT * FROM hrp.PA0002",
    "SELECT * FROM srv.Replicate.sap.NFAL",
    "SELECT * FROM Analysen.dbo.X",
    "SELECT PATNR FROM NFAL",
    "WAITFOR DELAY '00:00:10'",
])
def test_guard_rejects(sql):
    with pytest.raises(G.GuardError):
        G.check(sql, _pol())


def test_guard_accepts_and_extracts_tables_joins():
    c = G.check("SELECT f.FALNR, COUNT(*) n FROM sap.NFAL f "
                "JOIN Replicate.sap.NBEW b ON b.FALNR = f.FALNR AND b.MANDT = f.MANDT "
                "WHERE f.MANDT = '100' GROUP BY f.FALNR", _pol())
    assert c.tables == ["NFAL", "NBEW"]
    assert ("NBEW", "FALNR", "NFAL", "FALNR") in c.join_pairs
    assert not c.uses_salt


def test_guard_literals_do_not_trigger():
    # Schluesselwoerter/Kommentarzeichen in Literalen sind harmlos
    G.check("SELECT FALNR FROM sap.NFAL WHERE FALAR = 'DELETE -- ;'", _pol())


def test_guard_cte_names_allowed():
    G.check("WITH x AS (SELECT FALNR FROM sap.NFAL) SELECT COUNT(*) FROM x", _pol())


# --- Verkryptung -----------------------------------------------------------------
@pytest.mark.parametrize("sql", [
    "SELECT NNAME FROM sap.NPAT",
    "SELECT p.NNAME AS x FROM sap.NPAT p",
    "SELECT [NNAME] FROM sap.NPAT",
    "SELECT PATNR FROM sap.NPAT WHERE NNAME = 'X'",          # Orakel
    "SELECT * FROM sap.NPAT",
    "SELECT p.* FROM sap.NPAT p",
    "SELECT GBDAT FROM sap.NPAT",
    "SELECT LEFT(NNAME, 3) FROM sap.NPAT",
    "WITH x AS (SELECT NNAME n FROM sap.NPAT) SELECT n FROM x",
    "SELECT f.KZTXT FROM sap.NFAL f",
])
def test_pii_rejected(sql):
    with pytest.raises(G.GuardError):
        G.check(sql, _pol())


@pytest.mark.parametrize("sql", [
    "SELECT PSEUDO(NNAME) AS n_h FROM sap.NPAT",
    "SELECT LEN(p.NNAME), LEFT(p.VNAME, 1) FROM sap.NPAT p",
    "SELECT COUNT(DISTINCT NNAME), COUNT(STRAS) FROM sap.NPAT",
    "SELECT YEAR(GBDAT) j, COUNT(*) FROM sap.NPAT GROUP BY YEAR(GBDAT)",
    "SELECT COUNT(*) FROM sap.NPAT WHERE NNAME IS NOT NULL",
    "SELECT COUNT(*) FROM sap.NPAT",
    "SELECT FALNR * 2 FROM sap.NFAL",
])
def test_pii_wrapped_ok(sql):
    G.check(sql, _pol())


def test_pii_only_for_referenced_tables():
    # KZTXT ist nur in NFAL verkryptet — Abfrage ohne NFAL darf es nicht blocken
    G.check("SELECT KZTXT FROM sap.NDIA", _pol())


def test_pseudo_rewrite_uses_salt_variable():
    c = G.check("SELECT PSEUDO(p.NNAME) h, PATNR FROM sap.NPAT p WHERE NNAME IS NULL", _pol())
    assert c.uses_salt
    assert "HASHBYTES('SHA2_256', CONCAT(@__salt, p.NNAME))" in c.sql
    assert "PSEUDO" not in c.sql.upper()


def test_mass_table_needs_where():
    with pytest.raises(G.GuardError):
        G.check("SELECT COUNT(*) FROM sap.NLEI", _pol())
    G.check("SELECT TOP 10 LNRLS FROM sap.NLEI WHERE FALNR = '0001234567'", _pol())


def test_mask_row_second_line():
    r = G.mask_row({"NNAME": "Klartext", "NNAME_H": "ABCDEF0123456789", "PATNR": "1"},
                   {"NNAME"})
    assert r["NNAME"] == "<maskiert>" and r["PATNR"] == "1"


def test_literal_free():
    assert G.literal_free("SELECT 1 FROM sap.NFAL WHERE FALNR = '0815'") == \
        "SELECT 1 FROM sap.NFAL WHERE FALNR = '?'"


# --- Wissensschicht ------------------------------------------------------------
@pytest.fixture
def kn():
    return Knowledge(":memory:", ROOT, ("docs/Analyse_Datenbank.md",))


def test_knowledge_loads_registry_and_docs(kn):
    assert "NPAT" in kn.registry
    hits = kn.search("Verkryptung")
    assert any(h["quelle"] == "doku" for h in hits)
    ctx = kn.context("NFAL")
    assert ctx["registry"]["pk"] == ["MANDT", "EINRI", "FALNR"]


def test_knowledge_learns_joins_errors_facts(kn):
    kn.log_query("SELECT ...", ["NFAL", "NBEW"], True, 5, 0.1, zweck="Fall-Bewegung",
                 join_pairs=[("NBEW", "FALNR", "NFAL", "FALNR")])
    kn.log_query("SELECT ...", ["NFAL", "NBEW"], True, 5, 0.1,
                 join_pairs=[("NFAL", "FALNR", "NBEW", "FALNR")])
    j = kn.joins_for("NFAL")
    assert j[0]["n"] == 2  # richtungsunabhaengig gezaehlt
    kn.log_query("SELECT ENDAT ...", ["NFAL"], False, 0, 0.1,
                 err="Invalid column name 'ENDAT'.")
    assert kn.pitfalls_for("NFAL")[0]["muster"] == "spalte_fehlt:ENDAT"
    fid = kn.add_fact("ENDTYP in diesem Haus tot", "NFAL", "ENDTYP")
    kn.set_fact_status(fid, "verifiziert", "Fuellgrad 0")
    ctx = kn.context("NFAL")
    assert ctx["fakten"][0]["status"] == "verifiziert"
    assert ctx["bewaehrte_abfragen"]
    assert any(h["quelle"] == "fakt" for h in kn.search("ENDTYP"))
    md = kn.export_markdown()
    assert "ENDTYP in diesem Haus tot" in md and "Invalid" not in md


def test_knowledge_mass_learning(kn):
    kn.put_stat("N2LABOR001", "zeilen", 322_000_000)
    kn.put_stat("NPAT", "zeilen", 800_000)
    assert kn.learned_mass_tables(50_000_000) == {"N2LABOR001"}


# --- Service mit FakeDB -----------------------------------------------------------
class FakeDB:
    """Imitiert LiveDB.run: protokolliert SQL/Salt, liefert Antworten je Muster."""

    def __init__(self):
        self.calls = []
        self.fail = None

    def run(self, sql, salt=None, params=(), max_rows=500):
        self.calls.append((sql, salt))
        if self.fail:
            raise RuntimeError(self.fail)
        if "INFORMATION_SCHEMA.COLUMNS" in sql and "NADR" in sql and "COLUMN_NAME" in sql \
                and "DATA_TYPE" not in sql:
            rows = [{"COLUMN_NAME": c} for c in ("MANDT", "ADRNR", "STRAS", "ORT01")]
            return ["COLUMN_NAME"], rows, False
        if "DATA_TYPE" in sql:
            rows = [{"spalte": "MANDT", "typ": "nvarchar", "laenge": 3, "nullable": 0, "ordinal": 1},
                    {"spalte": "PATNR", "typ": "nvarchar", "laenge": 10, "nullable": 0, "ordinal": 2},
                    {"spalte": "NNAME", "typ": "nvarchar", "laenge": 35, "nullable": 1, "ordinal": 3},
                    {"spalte": "GSCHL", "typ": "nvarchar", "laenge": 1, "nullable": 1, "ordinal": 4}]
            return list(rows[0]), rows, False
        if "PRIMARY KEY" in sql:
            return ["spalte"], [{"spalte": "MANDT"}, {"spalte": "PATNR"}], False
        if "SUM(p.rows)" in sql and "t.name LIKE" not in sql:
            return ["zeilen"], [{"zeilen": 812345}], False
        if "SUM(CASE WHEN" in sql:
            return [], [{"__n": 100, "PATNR": 100, "GSCHL": 0}], False
        if "doppelte_schluessel" in sql:
            return [], [{"zeilen": 100, "doppelte_schluessel": 0}], False
        return ["X"], [{"X": i} for i in range(min(max_rows + 1, 3))], False


@pytest.fixture
def svc():
    return LiveService(PCFG, Knowledge(":memory:", ROOT, ()), FakeDB(), None, salt="s3cr3t")


def test_service_sql_lesen_learns(svc):
    out = svc.sql_lesen("SELECT f.FALNR FROM sap.NFAL f JOIN sap.NBEW b "
                        "ON b.FALNR = f.FALNR WHERE f.FALNR = '0815'", zweck="Test")
    assert out["anzahl"] == 3
    assert svc.k.joins_for("NBEW")
    q = svc.k.proven_queries("NFAL")[0]
    assert "0815" not in q["sql_norm"]  # Literale nie im Wissensspeicher


def test_service_pseudo_passes_salt_only_when_needed(svc):
    svc.sql_lesen("SELECT PSEUDO(NNAME) h FROM sap.NPAT")
    assert svc.db.calls[-1][1] == "s3cr3t"
    svc.sql_lesen("SELECT COUNT(*) FROM sap.NPAT")
    assert svc.db.calls[-1][1] is None


def test_service_guard_and_db_errors_are_returned_and_learned(svc):
    assert "Abgewiesen" in svc.sql_lesen("SELECT NNAME FROM sap.NPAT")["fehler"]
    svc.db.fail = "Invalid column name 'ENDAT'."
    out = svc.sql_lesen("SELECT ENDAT FROM sap.NFAL")
    assert "ENDAT" in out["fehler"]
    out = svc.sql_lesen("SELECT ENDAT FROM sap.NFAL")
    assert out["bekannte_fallstricke"] == ["Spalte ENDAT existiert nicht"]


def test_service_describe_caches_schema_and_flags_pii(svc):
    d = svc.tabelle_beschreiben("NPAT")
    assert d["pk_db"] == ["MANDT", "PATNR"] and not d["pk_abweichung"]
    assert {c["spalte"]: c["verkryptet"] for c in d["spalten"]}["NNAME"] is True
    assert svc.k.rowcount("NPAT") == 812345


def test_service_stichprobe_masks_pii(svc):
    svc.tabelle_beschreiben("NPAT")
    svc.stichprobe("NPAT", ["PATNR", "NNAME", "GBDAT"], n=5)
    sql, salt = svc.db.calls[-1]
    assert "HASHBYTES" in sql and "YEAR([GBDAT])" in sql and salt == "s3cr3t"
    assert "TOP (5)" in sql


def test_service_stichprobe_where_is_guarded(svc):
    out = svc.stichprobe("NPAT", ["PATNR"], where="NNAME LIKE 'M%'")
    assert "fehler" in out


def test_service_full_pii_table_resolved_live(svc):
    with pytest.raises(G.GuardError):
        svc.check("SELECT STRAS FROM sap.NADR")
    svc.check("SELECT ADRNR, LEN(STRAS) FROM sap.NADR")


def test_service_profiles(svc):
    assert svc.pk_pruefen("NFAL")["eindeutig"] is True
    f = svc.fuellgrade("NPAT", ["PATNR", "GSCHL"])
    assert f["tote_felder"] == ["GSCHL"]
    assert "fehler" in svc.werteverteilung("NPAT", "NNAME")
    assert "fehler" in svc.fuellgrade("NLEI")


def test_service_ident_validation(svc):
    with pytest.raises(G.GuardError):
        svc.werteverteilung("NFAL", "FALAR] FROM x--")


def test_service_learned_mass_table(svc):
    svc.k.put_stat("ZNRKT_BIG", "zeilen", 90_000_000)
    with pytest.raises(G.GuardError):
        svc.check("SELECT COUNT(*) FROM sap.ZNRKT_BIG")


def test_service_saved_queries_and_export(svc, tmp_path):
    svc.pcfg = {**svc.pcfg, "knowledge": {"export_dir": str(tmp_path)}}
    svc.abfrage_speichern("faelle_je_art", "SELECT FALAR, COUNT(*) n FROM sap.NFAL "
                          "GROUP BY FALAR", "Fallarten")
    assert svc.abfrage_ausfuehren("faelle_je_art")["anzahl"] == 3
    with pytest.raises(G.GuardError):
        svc.abfrage_speichern("boese", "SELECT NNAME FROM sap.NPAT", "x")
    svc.merken("FALAR 1=stationaer", "NFAL", "FALAR", "verifiziert")
    ex = svc.wissen_export()
    assert os.path.exists(ex["datei"]) and "FALAR 1=stationaer" in ex["inhalt"]


def test_mcp_registration():
    app = _make_app()
    if app is None:
        pytest.skip("mcp-SDK fehlt")
    svc = LiveService(PCFG, Knowledge(":memory:", ROOT, ()), FakeDB(), None, salt="x")
    register(app, svc)


def test_windows_scripts_are_ascii():
    """Windows PowerShell 5.1 liest .ps1 ohne BOM als ANSI: ein UTF-8-Gedankenstrich
    wird zu 'â€”' und dessen Byte 0x94 (”) beendet Strings -> Parserfehler.
    Skripte deshalb rein ASCII halten (BOM nur als Zusatzschutz)."""
    for rel in ("tools/setup_live_mcp.ps1", "tools/set_db_password.ps1", "Start-LiveMCP.bat"):
        raw = open(os.path.join(ROOT, rel), "rb").read()
        if raw.startswith(b"\xef\xbb\xbf"):
            raw = raw[3:]
        bad = [i for i, b in enumerate(raw) if b > 127]
        assert not bad, f"{rel}: Nicht-ASCII-Bytes an Position {bad[:5]}"


def test_cli_beispiel_passes_guard():
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import live_query
    svc = LiveService(PCFG, Knowledge(":memory:", ROOT, ()), FakeDB(), None, salt="x")
    assert svc.check(live_query.BEISPIEL_SQL).tables == ["NFAL"]


def test_zustandspfad_weicht_bei_schreibschutz_aus(tmp_path, monkeypatch):
    """Vorfall R36: Claude Desktop (ohne Adminrechte) konnte live.sqlite im per
    Admin-Shell angelegten Repo nicht schreiben -> Absturz beim Start. Der Server
    muss stattdessen in ein Benutzerverzeichnis ausweichen."""
    from sapfhir.live import server as S
    monkeypatch.setenv("SAPFHIR_STATE_DIR", str(tmp_path / "state"))
    echt = S._beschreibbar
    monkeypatch.setattr(S, "_beschreibbar",
                        lambda p: False if p.startswith("data/") else echt(p))
    alt = S._zustandspfad("data/knowledge/live.sqlite")
    assert alt == str(tmp_path / "state" / "data" / "knowledge" / "live.sqlite")
    from sapfhir.live.knowledge import Knowledge
    k = Knowledge(alt, ".", ())
    assert os.path.exists(alt) and k.db is not None


def test_zustandspfad_bleibt_wenn_schreibbar(tmp_path):
    from sapfhir.live import server as S
    p = str(tmp_path / "k" / "live.sqlite")
    assert S._zustandspfad(p) == p
