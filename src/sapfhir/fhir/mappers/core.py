# -*- coding: utf-8 -*-
"""IS-H / i.s.h.med -> FHIR R4 Kernmapper.

Jede Funktion nimmt eine Bronze-Zeile (dict) plus Kontext (ids-Namespace, privacy) und
liefert eine FHIR-Ressource (dict). Feldkennungen, die noch nicht gegen Live-DB bzw.
offizielle SAP-IS-H-Doku (sapdatasheet.org) verifiziert sind, sind mit # VERIFY markiert.

Verifiziert gegen Live-replicate: NPAT-, NFAL-, NBEW-Spalten existieren wie referenziert.
Enum-Belegungen (FALAR, BEWTY, GSCHL) sind fachlich zu bestaetigen -> # VERIFY.
"""
from __future__ import annotations
from .. import ids as _ids

# --- Enum-Tabellen (VERIFY gegen Customizing der Einrichtung) ---------------
GESCHLECHT = {  # NPAT.GSCHL   # VERIFY: IS-H nutzt i.d.R. 1=maennl., 2=weibl., 3=divers
    "1": "male", "2": "female", "3": "other", "0": "unknown",
}
FALLART = {     # NFAL.FALAR   # VERIFY
    "1": ("IMP", "stationaer"),
    "2": ("AMB", "ambulant"),
    "3": ("SS",  "teilstationaer"),
}
BEWEGUNGSART = {  # NBEW.BEWTY # VERIFY
    "1": "Aufnahme",
    "2": "Verlegung",
    "3": "Entlassung",
    "4": "ambulanter Besuch",
}


def _shift(priv, pid, iso):
    return priv.shift(pid, iso) if priv else iso


def map_patient(row: dict, ns, priv=None, adr: dict | None = None) -> dict:
    pid = row.get("PATNR")
    res = {
        "resourceType": "Patient",
        "id": _ids.rid(ns, "Patient", row.get("MANDT"), pid),
        "identifier": [{"system": "urn:ish:patnr", "value": pid}],
        "gender": GESCHLECHT.get(str(row.get("GSCHL", "")), "unknown"),  # VERIFY
        "meta": {"source": "sapfhir/NPAT"},
    }
    gb = row.get("GBDAT")   # VERIFY Geburtsdatum-Spalte
    if gb:
        res["birthDate"] = _shift(priv, pid, gb)
    # Name/Adresse nur bei Klarbetrieb
    if priv is None or priv.mode == "off":
        nn = row.get("NNAME"); vn = row.get("VNAME")   # VERIFY
        if nn or vn:
            res["name"] = [{"family": nn, "given": [vn] if vn else []}]
        if adr:
            res["address"] = [{
                "line": [adr.get("STRAS")], "city": adr.get("ORT01"),
                "postalCode": adr.get("PSTLZ"), "country": adr.get("LAND1"),
            }]
    if priv:
        res = priv.redact_patient(res, pid)
    return res


def map_encounter(row: dict, ns, priv=None) -> dict:
    pid = row.get("PATNR"); falnr = row.get("FALNR"); mandt = row.get("MANDT")
    cls, disp = FALLART.get(str(row.get("FALAR", "")), ("IMP", "stationaer"))  # VERIFY
    res = {
        "resourceType": "Encounter",
        "id": _ids.rid(ns, "Encounter", mandt, row.get("EINRI"), falnr),
        "identifier": [{"system": "urn:ish:falnr",
                        "value": f"{row.get('EINRI')}-{falnr}"}],
        "status": "finished" if row.get("STORN") not in (None, "") and False else "finished",
        "class": {"code": cls, "display": disp},
        "subject": {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, pid)},
        "period": {"start": _shift(priv, pid, row.get("BEGDT")),
                   "end": _shift(priv, pid, row.get("ENDAT"))},
        "meta": {"source": "sapfhir/NFAL"},
    }
    if str(row.get("STORN") or "") not in ("", "0"):
        res["status"] = "entered-in-error"
    return res


def map_encounter_bewegung(row: dict, ns, priv=None) -> dict:
    """NBEW -> Sub-Encounter je Bewegung (partOf Fall-Encounter)."""
    pid = None  # NBEW hat keine PATNR; Verknuepfung ueber FALNR
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    res = {
        "resourceType": "Encounter",
        "id": _ids.rid(ns, "EncounterBew", mandt, einri, falnr, lfdnr),
        "status": "finished",
        "class": {"code": "IMP"},
        "type": [{"text": BEWEGUNGSART.get(str(row.get("BEWTY", "")), "Bewegung")}],  # VERIFY
        "partOf": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "period": {"start": row.get("BWIDT"), "end": row.get("BWEDT")},
        "location": [{"location": {"display": row.get("ORGPF") or row.get("ORGFA")}}],
        "meta": {"source": "sapfhir/NBEW"},
    }
    if str(row.get("STORN") or "") not in ("", "0"):
        res["status"] = "entered-in-error"
    return res


def map_condition(row: dict, ns, priv=None) -> dict:
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    icd = row.get("DKEY1") or row.get("DIAID")   # VERIFY ICD-Spalte NDIA
    res = {
        "resourceType": "Condition",
        "id": _ids.rid(ns, "Condition", mandt, einri, falnr, lfdnr),
        "code": {"coding": [{
            "system": "http://fhir.de/CodeSystem/bfarm/icd-10-gm",
            "code": icd}], "text": row.get("DIATX")},   # VERIFY Freitext-Spalte
        "encounter": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "recordedDate": row.get("DIADT"),   # VERIFY
        "meta": {"source": "sapfhir/NDIA"},
    }
    if str(row.get("STORN") or "") not in ("", "0"):
        res["verificationStatus"] = {"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status",
            "code": "entered-in-error"}]}
    return res


def map_procedure(row: dict, ns, priv=None) -> dict:
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    ops = row.get("ICPML") or row.get("ICPK1")   # VERIFY OPS-Spalte NICP
    return {
        "resourceType": "Procedure",
        "id": _ids.rid(ns, "Procedure", mandt, einri, falnr, lfdnr),
        "status": "completed",
        "code": {"coding": [{
            "system": "http://fhir.de/CodeSystem/bfarm/ops", "code": ops}]},
        "subject": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "performedDateTime": row.get("ICDAT"),   # VERIFY
        "meta": {"source": "sapfhir/NICP"},
    }


def map_observation_labor(row: dict, ns, priv=None, loinc: dict | None = None) -> dict:
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    code_local = row.get("PARCD") or row.get("LABCD")   # VERIFY i.s.h.med Laborcode
    coding = []
    if loinc and code_local in loinc:
        coding.append({"system": "http://loinc.org", "code": loinc[code_local]})
    return {
        "resourceType": "Observation",
        "id": _ids.rid(ns, "ObsLab", mandt, einri, falnr, lfdnr),
        "status": "final",
        "category": [{"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/observation-category",
            "code": "laboratory"}]}],
        "code": {"coding": coding, "text": row.get("PARTX") or code_local},   # VERIFY
        "valueQuantity": {"value": row.get("WERT"), "unit": row.get("EINH")},  # VERIFY
        "referenceRange": [{"text": row.get("REFBER")}] if row.get("REFBER") else [],
        "meta": {"source": "sapfhir/N2LABOR"},
    }


def map_document_reference(row: dict, ns, priv=None) -> dict:
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    docid = row.get("DOCID")   # VERIFY
    return {
        "resourceType": "DocumentReference",
        "id": _ids.rid(ns, "DocRef", mandt, einri, docid),
        "status": "current",
        "type": {"text": row.get("DOCKA") or row.get("DOCTY")},   # VERIFY Dokumentkategorie
        "date": row.get("DOCDT"),   # VERIFY
        "description": priv.text(None, row.get("DOCTX")) if priv else row.get("DOCTX"),
        "meta": {"source": "sapfhir/NDOC"},
        # Volltext bewusst NICHT hier -> DuckDB-FTS (doc_search)
    }


# Registry: FHIR-Ressourcentyp -> Mapperfunktion (fuer ndjson.py)
MAPPERS = {
    "Patient": map_patient,
    "Encounter": map_encounter,
    "EncounterBewegung": map_encounter_bewegung,
    "Condition": map_condition,
    "Procedure": map_procedure,
    "Observation": map_observation_labor,
    "DocumentReference": map_document_reference,
}
