# -*- coding: utf-8 -*-
"""Golden-Record-/Pipeline-Invarianten (CONCEPT §15.5/§16.4) fuer die
Ausleitungskette  Mapper -> _shift_resource_dates -> normalize_resource.

Die Mapper selbst sind in tests/test_core.py (R8-R16, 55 Tests) abgedeckt;
hier geht es um das Zusammenspiel in der NDJSON-Pipeline:
- Date-Shift ist patientenfix und ueber ALLE Ressourcen eines Patienten konsistent
  (ANALYSE A4) — auch fuer Mapper, die nicht selbst shiften (NDIA/NICP/NBEW).
- Kein Quelldatum und kein Klarname erscheint bei privacy=pseudonymize.
- NPAT/NFAL (Mapper-interner Shift) werden NICHT doppelt geschoben.
- normalize_resource liefert ISO-8601 mit Offset.
"""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from sapfhir.fhir import ids as I
from sapfhir.fhir.privacy import Privacy
from sapfhir.fhir.mappers import core as M
from sapfhir.fhir.ndjson import _shift_resource_dates
from sapfhir.fhir.normalize import normalize_resource

NS = I.make_ns("sapfhir")
PATNR = "0007799001"

ROW_NFAL = {"MANDT": "100", "EINRI": "0001", "FALNR": "0004499001",
            "FALAR": "1", "PATNR": PATNR, "BEGDT": "2026-02-02",
            "ENDDT": "2026-02-09", "STORN": ""}
ROW_NBEW = {"MANDT": "100", "EINRI": "0001", "FALNR": "0004499001",
            "LFDNR": "00001", "BEWTY": "1", "BWIDT": "2026-02-02",
            "BWEDT": "2026-02-09", "ORGFA": "KARD", "STORN": ""}
ROW_NDIA = {"MANDT": "100", "EINRI": "0001", "FALNR": "0004499001",
            "LFDNR": "001", "DKAT1": "56", "DKEY1": "I50.14",
            "DIADT": "2026-02-02", "STORN": ""}
QUELLDATEN = {"2026-02-02", "2026-02-09"}


def _pipeline(res, priv, patnr):
    _shift_resource_dates(res, priv, patnr)
    return normalize_resource(res)


def test_shift_konsistent_ueber_ressourcen():
    """Fall (Mapper-Shift) und Bewegung/Diagnose (Pipeline-Shift) muessen um
    DENSELBEN Betrag verschoben sein — sonst ist der Shift rueckrechenbar."""
    priv = Privacy(mode="pseudonymize", secret="golden-test-secret")
    enc = _pipeline(M.map_encounter(dict(ROW_NFAL), NS, priv), priv, PATNR)
    bew = _pipeline(M.map_encounter_bewegung(dict(ROW_NBEW), NS, priv), priv, PATNR)
    con = _pipeline(M.map_condition(dict(ROW_NDIA), NS, priv), priv, PATNR)
    assert enc["period"]["start"][:10] == bew["period"]["start"][:10]
    assert enc["period"]["start"][:10] == con["recordedDate"][:10]
    # Intervall bleibt erhalten (Verweildauer unveraendert)
    d0 = dt.date.fromisoformat(enc["period"]["start"][:10])
    d1 = dt.date.fromisoformat(enc["period"]["end"][:10])
    assert (d1 - d0).days == 7


def test_kein_quelldatum_bei_pseudonymisierung():
    priv = Privacy(mode="pseudonymize", secret="golden-test-secret")
    alle = [
        _pipeline(M.map_encounter(dict(ROW_NFAL), NS, priv), priv, PATNR),
        _pipeline(M.map_encounter_bewegung(dict(ROW_NBEW), NS, priv), priv, PATNR),
        _pipeline(M.map_condition(dict(ROW_NDIA), NS, priv), priv, PATNR),
    ]
    dump = repr(alle)
    for d in QUELLDATEN:
        assert d not in dump, f"Quelldatum {d} unverschoben in der Ausgabe!"


def test_kein_doppel_shift_bei_nfal():
    """map_encounter shiftet intern (meta.source=sapfhir/NFAL) — der
    Pipeline-Schritt darf NICHT nochmal schieben."""
    priv = Privacy(mode="pseudonymize", secret="golden-test-secret")
    einmal = M.map_encounter(dict(ROW_NFAL), NS, priv)
    start_nach_mapper = einmal["period"]["start"]
    _shift_resource_dates(einmal, priv, PATNR)
    assert einmal["period"]["start"] == start_nach_mapper


def test_normalize_iso8601():
    priv = Privacy(mode="off")
    row = dict(ROW_NBEW, BWIZT="08:15:00")
    res = M.map_encounter_bewegung(row, NS, None)
    normalize_resource(res)
    assert res["period"]["start"].startswith("2026-02-02T08:15:00+")


def test_klarbetrieb_unveraendert():
    enc = _pipeline(M.map_encounter(dict(ROW_NFAL), NS, None), None, PATNR)
    assert enc["period"] == {"start": "2026-02-02", "end": "2026-02-09"}
    assert enc["status"] == "finished"


def test_offener_fall_in_progress():
    """R16: ENDDT=0101-01-01 (SAP-Leerdatum via Qlik) = offener Fall."""
    row = dict(ROW_NFAL, ENDDT="0101-01-01")
    res = M.map_encounter(row, NS, None)
    assert res["status"] == "in-progress"
    assert "end" not in res["period"]
