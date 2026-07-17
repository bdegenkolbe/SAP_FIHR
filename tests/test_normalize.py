# -*- coding: utf-8 -*-
"""Tests fuer die ISO-8601-Normalisierung (Pipeline-Schritt NACH Privacy-Shift, R13).
Ausfuehren: python -m pytest test_normalize.py -q
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from sapfhir.fhir.normalize import norm_value, normalize_resource


def test_dats_und_datetime():
    assert norm_value("20240115") == "2024-01-15"
    assert norm_value("20240115T081500") == "2024-01-15T08:15:00+01:00"   # Winter
    assert norm_value("20240715T081500") == "2024-07-15T08:15:00+02:00"   # Sommer (DST)
    assert norm_value("2024-01-15T08:15:00") == "2024-01-15T08:15:00+01:00"  # Offset ergaenzt


def test_sap_tagesende_und_dst():
    assert norm_value("20240115T240000") == "2024-01-15T23:59:59+01:00"   # SAP 24:00
    assert norm_value("20240331T030000") == "2024-03-31T03:00:00+02:00"   # DST-Fruehjahr
    assert norm_value("20240229") == "2024-02-29"                          # Schaltjahr


def test_unplausibles_bleibt_unangetastet():
    # KEIN Datenverlust: alles Nicht-Normalisierbare bleibt Original
    for raw in ("00000000", "", "99991231", "20240230", "20230229",
                "18500101", "0012345678"):
        assert norm_value(raw) == raw


def test_teilpraezision_und_iso_bleiben():
    # pseudonymisierte Teiljahre (birthDate='1957') und fertige ISO-Werte bleiben stehen
    for ok in ("1957", "2024-01", "2024-01-15", "2024-01-15T08:15:00+02:00"):
        assert norm_value(ok) == ok


def test_resource_walk_normalisiert_nur_datumsfelder():
    enc = {
        "resourceType": "Encounter",
        "identifier": [{"system": "urn:ish:falnr", "value": "0001-20240115"}],
        "period": {"start": "20240115T081500", "end": "20240116"},
        "hospitalization": {"admitSource": {"coding": [{"code": "01"}]}},
        "participant": [{"period": {"start": "20240101", "end": "20240105"}}],
        "contained": [{"resourceType": "Observation",
                       "effectiveDateTime": "20120728T093000",
                       "valueQuantity": {"value": 2.5}}],
    }
    normalize_resource(enc)
    assert enc["period"]["start"] == "2024-01-15T08:15:00+01:00"
    assert enc["period"]["end"] == "2024-01-16"
    assert enc["participant"][0]["period"]["start"] == "2024-01-01"
    assert enc["contained"][0]["effectiveDateTime"] == "2012-07-28T09:30:00+02:00"
    # Identifier/Codes duerfen NIE normalisiert werden (8-stellige Codes legitim)
    assert enc["identifier"][0]["value"] == "0001-20240115"
    assert enc["hospitalization"]["admitSource"]["coding"][0]["code"] == "01"


def test_patient_birthdate_und_pseudonymisierung():
    pat = {"resourceType": "Patient", "birthDate": "19570314", "deceasedDateTime": "20251201"}
    normalize_resource(pat)
    assert pat["birthDate"] == "1957-03-14"
    assert pat["deceasedDateTime"] == "2025-12-01"
    pat2 = {"resourceType": "Patient", "birthDate": "1957"}   # nach Privacy-Shift/Redaktion
    normalize_resource(pat2)
    assert pat2["birthDate"] == "1957"


def test_validityperiod_und_authoredon():
    mr = {"resourceType": "MedicationRequest", "authoredOn": "20120728T140000",
          "dispenseRequest": {"validityPeriod": {"start": "20120728", "end": "20120804"}}}
    normalize_resource(mr)
    assert mr["authoredOn"] == "2012-07-28T14:00:00+02:00"
    assert mr["dispenseRequest"]["validityPeriod"]["end"] == "2012-08-04"
