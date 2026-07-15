# -*- coding: utf-8 -*-
"""Golden-Record-Test (CONCEPT §15.5): ein fixierter Fixture-Patient, Sollwerte
ueber alle Kern-Ressourcentypen. Jede Mapper-Aenderung, die dieses Bild bricht,
ist ein bewusster, reviewter Diff. KEINE echten Daten — synthetischer Testfall.

Zweiter Teil: Datenschutz-Invarianten (CONCEPT §16.4) — bei privacy=pseudonymize
erscheint KEIN Quelldatum und kein Klarname in der Ausgabe, und der Date-Shift
ist ueber alle Ressourcen des Patienten konsistent (Intervalle bleiben erhalten).
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from sapfhir.fhir import ids as I
from sapfhir.fhir.privacy import Privacy
from sapfhir.fhir.mappers import core as M
from sapfhir.fhir import terminology as T

NS = I.make_ns("sapfhir")

# --- Fixture: der Golden-Record-Patient --------------------------------------
ROW_NPAT = {"MANDT": "100", "PATNR": "0007799001", "GSCHL": "2",
            "GBDAT": "1957-03-14", "NNAME": "Musterfrau", "VNAME": "Erika",
            "TODKZ": "", "STORN": ""}
ROW_NFAL = {"MANDT": "100", "EINRI": "0001", "FALNR": "0004499001",
            "FALAR": "1", "PATNR": "0007799001", "BEGDT": "2026-02-02",
            "ENDAT": "2026-02-09", "STORN": ""}
ROW_NBEW = {"MANDT": "100", "EINRI": "0001", "FALNR": "0004499001",
            "LFDNR": "00001", "BEWTY": "1", "BWIDT": "2026-02-02",
            "BWEDT": "2026-02-09", "ORGFA": "KARD", "ORGPF": None, "STORN": ""}
ROW_NDIA = {"MANDT": "100", "EINRI": "0001", "FALNR": "0004499001",
            "LFDNR": "001", "DKEY1": "I50.14", "DIADT": "2026-02-02",
            "DIATX": None, "STORN": ""}
ROW_NICP = {"MANDT": "100", "EINRI": "0001", "FALNR": "0004499001",
            "LFDNR": "001", "ICPML": "8-800.c0", "ICDAT": "2026-02-03",
            "STORN": ""}
ROW_LAB = {"MANDT": "100", "EINRI": "0001", "FALNR": "0004499001",
           "LFDNR": "001", "PARCD": "KREA", "PARTX": "Kreatinin",
           "WERT": "1.1", "EINH": "mg/dl", "REFBER": "0.6-1.4",
           "BEFDT": "2026-02-03", "STORN": ""}

PATNR = "0007799001"
QUELLDATEN_DATEN = {"1957-03-14", "2026-02-02", "2026-02-09", "2026-02-03"}


def _alle_ressourcen(priv):
    return {
        "Patient": M.map_patient(dict(ROW_NPAT), NS, priv),
        "Encounter": M.map_encounter(dict(ROW_NFAL), NS, priv),
        "EncounterBew": M.map_encounter_bewegung(dict(ROW_NBEW), NS, priv,
                                                 patnr=PATNR),
        "Condition": M.map_condition(dict(ROW_NDIA), NS, priv, patnr=PATNR),
        "Procedure": M.map_procedure(dict(ROW_NICP), NS, priv, patnr=PATNR),
        "Observation": M.map_observation_labor(dict(ROW_LAB), NS, priv,
                                               patnr=PATNR),
    }


# --- Teil 1: Golden Record im Klarbetrieb (privacy=off, deterministisch) ----
def test_golden_patient():
    res = M.map_patient(dict(ROW_NPAT), NS, None)
    assert res == {
        "resourceType": "Patient",
        "id": I.rid(NS, "Patient", "100", PATNR),
        "identifier": [{"system": "urn:ish:patnr", "value": PATNR}],
        "gender": "female",
        "meta": {"source": "sapfhir/NPAT"},
        "birthDate": "1957-03-14",
        "name": [{"family": "Musterfrau", "given": ["Erika"]}],
    }


def test_golden_encounter():
    res = M.map_encounter(dict(ROW_NFAL), NS, None)
    assert res["id"] == I.rid(NS, "Encounter", "100", "0001", "0004499001")
    assert res["class"] == {"system": T.V3_ACTCODE, "code": "IMP",
                            "display": "stationaer"}
    assert res["subject"]["reference"] == \
        "Patient/" + I.rid(NS, "Patient", "100", PATNR)
    assert res["period"] == {"start": "2026-02-02", "end": "2026-02-09"}
    assert res["status"] == "finished"


def test_golden_bewegung_hat_subject_und_partof():
    res = M.map_encounter_bewegung(dict(ROW_NBEW), NS, None, patnr=PATNR)
    assert res["partOf"]["reference"] == \
        "Encounter/" + I.rid(NS, "Encounter", "100", "0001", "0004499001")
    assert res["subject"]["reference"] == \
        "Patient/" + I.rid(NS, "Patient", "100", PATNR)   # ANALYSE A5
    assert res["location"][0]["location"]["display"] == "KARD"


def test_golden_condition():
    res = M.map_condition(dict(ROW_NDIA), NS, None, patnr=PATNR)
    assert res["code"]["coding"][0] == {"system": T.ICD10GM, "code": "I50.14"}
    assert res["subject"]["reference"].startswith("Patient/")
    assert res["recordedDate"] == "2026-02-02"
    assert "verificationStatus" not in res


def test_golden_procedure_und_observation():
    proc = M.map_procedure(dict(ROW_NICP), NS, None, patnr=PATNR)
    assert proc["code"]["coding"][0] == {"system": T.OPS, "code": "8-800.c0"}
    assert proc["status"] == "completed"
    obs = M.map_observation_labor(dict(ROW_LAB), NS, None, patnr=PATNR)
    assert obs["valueQuantity"]["value"] == 1.1
    assert obs["valueQuantity"]["code"] == "mg/dL"      # UCUM normalisiert
    assert obs["valueQuantity"]["system"] == T.UCUM
    assert obs["referenceRange"] == [{"text": "0.6-1.4"}]


def test_golden_ids_idempotent():
    a = _alle_ressourcen(None)
    b = _alle_ressourcen(None)
    assert {k: v["id"] for k, v in a.items()} == {k: v["id"] for k, v in b.items()}


# --- Teil 2: Datenschutz-Invarianten (privacy=pseudonymize) ------------------
def test_privacy_kein_quelldatum_in_ausgabe():
    priv = Privacy(mode="pseudonymize", secret="golden-test-secret")
    alle = _alle_ressourcen(priv)
    dump = repr(alle)
    for d in QUELLDATEN_DATEN:
        assert d not in dump, f"Quelldatum {d} unverschoben in der Ausgabe!"
    assert "Musterfrau" not in dump and "Erika" not in dump


def test_privacy_date_shift_konsistent():
    """Fall- und Bewegungszeitraum muessen um DENSELBEN Betrag verschoben sein
    (ANALYSE A4) — sonst ist der Shift rueckrechenbar und die Zeitachse kaputt."""
    priv = Privacy(mode="pseudonymize", secret="golden-test-secret")
    enc = M.map_encounter(dict(ROW_NFAL), NS, priv)
    bew = M.map_encounter_bewegung(dict(ROW_NBEW), NS, priv, patnr=PATNR)
    con = M.map_condition(dict(ROW_NDIA), NS, priv, patnr=PATNR)
    assert enc["period"]["start"] == bew["period"]["start"]
    assert enc["period"]["start"] == con["recordedDate"]
    # Intervall bleibt erhalten (Verweildauer unveraendert)
    d0 = dt.date.fromisoformat(enc["period"]["start"][:10])
    d1 = dt.date.fromisoformat(enc["period"]["end"][:10])
    assert (d1 - d0).days == 7
