# -*- coding: utf-8 -*-
"""Tests der Berechtigungsschicht: SETNODE-Rollup, Rollen, Sichtbarkeit, deny-by-default."""
from sapfhir.authz import resolver
from sapfhir.authz.service import Authz, InMemoryBackend


# Synthetisches Modell: Department CHIR mit zwei Stationen; Kostenstellen als Blaetter.
SETNODE = [("DEP-CHIR", "STA-A"), ("DEP-CHIR", "STA-B")]
SETLEAF = [("STA-A", "K1"), ("STA-B", "K2"), ("DEP-CHIR", "KM")]  # KM = Leitungs-KoStl


def _authz():
    be = InMemoryBackend(
        login_pernr={"MUELLER": ["100"], "CHEF": ["200"], "MC": ["300"], "GHOST": ["999"]},
        pernr_kostl={"100": ["K1"], "200": ["KM"], "300": ["K1"], "999": ["K1"]},
        setnode=SETNODE, setleaf=SETLEAF,
        fall_kostl=[("P1", "F1", "K1"), ("P2", "F2", "K2"), ("P3", "F3", "K9")])
    roles = {"MUELLER": "abteilung", "CHEF": "abteilung", "MC": "medizincontrolling"}
    return Authz(be, roles=roles, expand=True)


# ---------- reine Logik ----------

def test_descendant_sets_zyklensicher():
    adj = resolver.build_adjacency([("A", "B"), ("B", "C"), ("C", "A")])  # Zyklus
    assert resolver.descendant_sets(adj, ["A"]) == {"A", "B", "C"}


def test_department_kostl_station_nur_eigene():
    # Stations-Mitarbeiter (K1 nur in STA-A) sieht nur K1
    got = resolver.department_kostl(SETNODE, SETLEAF, ["K1"], expand=True)
    assert got == {"K1"}


def test_department_kostl_leitung_erbt_unter_oes():
    # Leitung (KM in DEP-CHIR) erbt STA-A + STA-B
    got = resolver.department_kostl(SETNODE, SETLEAF, ["KM"], expand=True)
    assert got == {"KM", "K1", "K2"}


def test_role_scope():
    assert resolver.role_scope("Medizincontrolling") == "ALL"
    assert resolver.role_scope("abteilung") == "DEPT"
    assert resolver.role_scope(None) == "NONE"


# ---------- R29: Sammel-/Auswertungsgruppen duerfen NICHT berechtigen ----------

def test_grosse_sammelgruppe_erweitert_nicht(sammel=None):
    """Live-Befund R29: SETLEAF enthaelt Auswertungs-/Testgruppen (z.B. TEST_PFL mit
    1.964 Kostenstellen). Wer darin vorkommt, darf NICHT alle darin enthaltenen OEs
    sehen — sonst Fail-Open (real gemessen: 2.003 statt 12 Kostenstellen)."""
    sammel = [("SAMMEL_REPORT", f"F{i}") for i in range(80)] + [("SAMMEL_REPORT", "K1")]
    got = resolver.department_kostl(SETNODE, SETLEAF + sammel, ["K1"], expand=True)
    assert got == {"K1"}, "grosse Sammelgruppe darf die Sicht nicht aufblaehen"
    assert "F0" not in got


def test_spezifischste_gruppe_gewinnt():
    """Steckt eine Kostenstelle in mehreren zulaessigen Gruppen, gilt die kleinste
    (= die tatsaechliche Organisationseinheit), nicht die Vereinigung."""
    weiter = [("BEREICH", "K1"), ("BEREICH", "KX"), ("BEREICH", "KY")]
    got = resolver.department_kostl(SETNODE, SETLEAF + weiter, ["K1"], expand=True)
    assert got == {"K1"}
    assert "KX" not in got and "KY" not in got


def test_groessengrenze_greift_nachweisbar():
    """Die Grenze muss WIRKEN: dieselbe Struktur, nur die Grenze unterscheidet sich.
    Ohne eigenes STA-A-Blatt ist TEAM die spezifischste Gruppe — sie zaehlt nur,
    wenn sie unter der Grenze liegt."""
    leaf = [("TEAM", "T1"), ("TEAM", "TA"), ("TEAM", "TB")]
    eng = resolver.department_kostl([], leaf, ["T1"], expand=True, max_set_leaves=2)
    assert eng == {"T1"}, "TEAM (3 Blaetter) muss bei Grenze 2 verworfen werden"
    weit = resolver.department_kostl([], leaf, ["T1"], expand=True, max_set_leaves=10)
    assert weit == {"T1", "TA", "TB"}, "bei Grenze 10 ist TEAM die Abteilung"


def test_rollup_bricht_an_uebergrossem_knoten_ab():
    """Review-Fund: ein kleines Set mit vielen kleinen Kindsets darf das Haus nicht
    freigeben — der Rollup laeuft NICHT durch einen uebergrossen Knoten hindurch."""
    leaf = [("WURZEL", "W1"), ("WURZEL", "W2")]
    leaf += [("SAMMEL", f"S{i}") for i in range(100)]          # uebergross
    leaf += [(f"KIND{i}", f"C{i}") for i in range(100)]        # je 1 Blatt
    node = [("WURZEL", "SAMMEL")] + [("SAMMEL", f"KIND{i}") for i in range(100)]
    got = resolver.department_kostl(node, leaf, ["W1"], expand=True, max_set_leaves=60)
    assert got == {"W1", "W2"}, f"Rollup lief durch SAMMEL hindurch: {len(got)} KOSTL"
    assert "C0" not in got and "S0" not in got


def test_vereinigungsgrenze_begrenzt_gesamtsicht():
    """Viele kleine, je zulaessige Kindsets duerfen sich nicht zur Haussicht summieren."""
    leaf = [("WURZEL", "W1")]
    node = []
    for i in range(60):
        leaf += [(f"G{i}", f"K{i}_{j}") for j in range(10)]   # je 10 Blaetter (zulaessig)
        node.append(("WURZEL", f"G{i}"))
    got = resolver.department_kostl(node, leaf, ["W1"], expand=True,
                                   max_set_leaves=60, max_union_leaves=100)
    assert len(got) <= 100, f"Vereinigung nicht begrenzt: {len(got)}"


# ---------- Service / Sichtbarkeit ----------

def test_station_sieht_nur_eigene_patienten():
    az = _authz()
    assert az.may_see_patient("MUELLER", "P1") is True
    assert az.may_see_patient("MUELLER", "P2") is False   # andere Station
    assert az.may_see_patient("MUELLER", "P3") is False   # anderes Department


def test_leitung_sieht_department():
    az = _authz()
    assert az.may_see_patient("CHEF", "P1") is True
    assert az.may_see_patient("CHEF", "P2") is True
    assert az.may_see_patient("CHEF", "P3") is False


def test_medizincontrolling_sieht_alle():
    az = _authz()
    assert all(az.may_see_patient("MC", p) for p in ("P1", "P2", "P3"))
    assert az.scope("MC") == "ALL"


def test_deny_by_default_unbekannt():
    az = _authz()
    assert az.scope("UNBEKANNT") == "NONE"
    assert az.may_see_patient("UNBEKANNT", "P1") is False
    assert az.may_see_patient(None, "P1") is False


def test_ghost_hat_rolle_aber_keine_treffer():
    # GHOST hat keine Rolle -> NONE, trotz Kostenstelle
    az = _authz()
    assert az.may_see_patient("GHOST", "P1") is False


def test_filter_patnr():
    az = _authz()
    assert set(az.filter_patnr("CHEF", ["P1", "P2", "P3"])) == {"P1", "P2"}
    assert az.filter_patnr("MC", ["P1", "P2", "P3"]) == ["P1", "P2", "P3"]
    assert az.filter_patnr("UNBEKANNT", ["P1", "P2"]) == []


def test_whoami():
    az = _authz()
    assert az.whoami("MC")["sieht_alle"] is True
    assert az.whoami("MUELLER")["scope"] == "DEPT"
    assert az.whoami("x")["scope"] == "NONE"


# ---------- R31: Zeitscheiben — abgelaufene HR-Zuordnungen duerfen NICHT berechtigen ----------

def test_duckdb_backend_filtert_abgelaufene_zeitscheiben(tmp_path):
    """PA0105/PA0001 sind historisiert. Ein ausgeschiedener Login bzw. eine alte
    Kostenstellen-Zuordnung darf keinen Zugriff mehr geben (live gemessen: ohne
    Filter sah ein Mitarbeiter 20 statt 1 Kostenstelle)."""
    import duckdb
    from sapfhir.authz.service import DuckDBBackend
    db = str(tmp_path / "wh.duckdb")
    con = duckdb.connect(db)
    con.execute("CREATE SCHEMA auth")
    con.execute("CREATE TABLE auth.login_pernr (login VARCHAR, PERNR VARCHAR, "
                "begda DATE, endda DATE)")
    con.execute("CREATE TABLE auth.pernr_kostl (PERNR VARCHAR, kostl VARCHAR, "
                "orgeh VARCHAR, begda DATE, endda DATE)")
    con.execute("INSERT INTO auth.login_pernr VALUES "
                "('AKTIV','1',DATE '2020-01-01',DATE '9999-12-31'),"
                "('RAUS','2',DATE '2015-01-01',DATE '2019-12-31')")   # ausgeschieden
    con.execute("INSERT INTO auth.pernr_kostl VALUES "
                "('1','K_HEUTE','O1',DATE '2024-01-01',DATE '9999-12-31'),"
                "('1','K_ALT','O9',DATE '2010-01-01',DATE '2012-12-31'),"   # abgelaufen
                "('2','K_EGAL','O2',DATE '2015-01-01',DATE '9999-12-31')")
    con.close()

    be = DuckDBBackend(db)
    assert be.employee_kostl("AKTIV") == {"K_HEUTE"}, "alte Zuordnung darf nicht zaehlen"
    assert be.employee_kostl("RAUS") == set(), "ausgeschiedener Login darf nichts sehen"

    # Und ueber den vollen Service: kein Zugriff fuer den Ausgeschiedenen
    az = Authz(be, roles={"AKTIV": "abteilung", "RAUS": "abteilung"}, expand=False)
    assert az.visible_kostl("AKTIV") == {"K_HEUTE"}
    assert az.visible_kostl("RAUS") == set()
