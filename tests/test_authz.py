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


def test_groessengrenze_konfigurierbar():
    gruppe = [("TEAM", "K1"), ("TEAM", "KA"), ("TEAM", "KB")]
    eng = resolver.department_kostl(SETNODE, SETLEAF + gruppe, ["K1"],
                                   expand=True, max_set_leaves=2)
    assert eng == {"K1"}                      # TEAM (3 Blaetter) verworfen
    weit = resolver.department_kostl(SETNODE, SETLEAF + gruppe, ["K1"],
                                    expand=True, max_set_leaves=10)
    assert weit == {"K1"}                     # STA-A (1 Blatt) bleibt spezifischer


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
