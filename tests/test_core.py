# -*- coding: utf-8 -*-
"""Tests ohne Live-DB (Fixtures). Deckt IDs, Privacy, Mapper und Guard ab.
Ausfuehren: python -m pytest tests/ -q
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from sapfhir.fhir import ids as I
from sapfhir.fhir.privacy import Privacy
from sapfhir.fhir.mappers import core as M
from sapfhir.mcp import guard as G
import pytest


def test_ids_stable():
    ns = I.make_ns("sapfhir")
    a = I.rid(ns, "Patient", "100", "000123")
    b = I.rid(ns, "Patient", "100", "000123")
    c = I.rid(ns, "Patient", "100", "000124")
    assert a == b and a != c


def test_privacy_pseudonym_stable_and_shift():
    p = Privacy(mode="pseudonymize", secret="geheim")
    assert p.pseudonym("3659") == p.pseudonym("3659")
    assert p.pseudonym("3659") != p.pseudonym("3660")
    # Date-Shift patientenfix, im Bereich +/-365
    d1 = p.shift("3659", "2025-01-01T00:00:00")
    d2 = p.shift("3659", "2025-01-01T00:00:00")
    assert d1 == d2
    p_off = Privacy(mode="off")
    assert p_off.shift("3659", "2025-01-01") == "2025-01-01"


def test_privacy_hash_id_value_based():
    p = Privacy(mode="pseudonymize", secret="s")
    # gleiche KVNR -> gleicher Hash, patientenuebergreifend
    assert p.hash_id("A123456789", "kvnr") == p.hash_id("A123456789", "kvnr")
    assert p.hash_id(None) is None


def test_privacy_free_text_deid():
    p = Privacy(mode="pseudonymize", secret="s")
    out = p.text("1", "Patient Herr Mustermann, geb. 14.03.1957, mail a@b.de")
    assert "[NAME]" in out and "[DATUM]" in out and "[EMAIL]" in out


def test_map_patient_redacted():
    ns = I.make_ns()
    p = Privacy(mode="pseudonymize", secret="s")
    row = {"MANDT": "100", "PATNR": "000123", "GSCHL": "2",
           "GBDAT": "1957-03-14", "NNAME": "Mustermann", "VNAME": "Erika"}
    res = M.map_patient(row, ns, p)
    assert res["resourceType"] == "Patient"
    assert "name" not in res and "address" not in res
    assert res["gender"] == "female"
    assert res["birthDate"] == "1957"          # nur Jahr bei Pseudonymisierung
    assert res["identifier"][0]["system"] == "urn:pseudonym"


def test_map_encounter_storno():
    ns = I.make_ns()
    row = {"MANDT": "100", "EINRI": "0001", "FALNR": "4471193", "PATNR": "000123",
           "FALAR": "1", "BEGDT": "2026-02-02", "ENDAT": "2026-02-09", "STORN": "X"}
    res = M.map_encounter(row, ns, None)
    assert res["status"] == "entered-in-error"
    assert res["class"]["code"] == "IMP"


def test_guard_blocks_dml():
    with pytest.raises(G.GuardError):
        G.check_sql("DELETE FROM x")
    with pytest.raises(G.GuardError):
        G.check_sql("SELECT 1; DROP TABLE y")
    assert G.check_sql("SELECT 1").upper().startswith("SELECT")
    assert "LIMIT" in G.enforce_limit("SELECT 1", 1000)


def test_guard_cypher():
    with pytest.raises(G.GuardError):
        G.check_cypher("MATCH (n) DETACH DELETE n")
    assert G.check_cypher("MATCH (p:Patient) RETURN p").upper().startswith("MATCH")
