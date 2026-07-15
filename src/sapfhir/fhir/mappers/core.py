# -*- coding: utf-8 -*-
"""IS-H / i.s.h.med -> FHIR R4 Kernmapper (v2, CONCEPT §16).

Jede Funktion nimmt eine Bronze-Zeile (dict) plus Kontext (ids-Namespace, privacy,
aufgeloeste PATNR) und liefert eine FHIR-Ressource (dict).

Invarianten (ANALYSE A4/A5):
- Jede Ressource mit Patientenbezug traegt subject/patient-Referenz. Die PATNR wird
  fuer NDIA/NICP/N2LABOR/NDOC ueber den FALNR->PATNR-Lookup (ndjson.py) uebergeben.
- JEDES Datum laeuft durch priv.shift(patnr, ...) — auch Bewegungen, Diagnosen,
  Prozeduren, Befunde, Dokumente. Nur so ist der Date-Shift nicht rueckrechenbar.

Feldkennungen, die noch nicht gegen Live-DB bzw. offizielle SAP-IS-H-Doku
(sapdatasheet.org) verifiziert sind, sind mit # VERIFY markiert.
Verifiziert gegen Live-replicate: NPAT-, NFAL-, NBEW-Spalten existieren wie
referenziert. Enum-Belegungen (FALAR, BEWTY, GSCHL) fachlich bestaetigen -> # VERIFY.
"""
from __future__ import annotations
from .. import ids as _ids
from .. import terminology as T

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


def _storniert(row: dict) -> bool:
    return str(row.get("STORN") or "") not in ("", "0")


def _patient_ref(ns, mandt, patnr) -> dict:
    return {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, patnr)}


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
    if str(row.get("TODKZ") or "") not in ("", "0"):   # VERIFY Verstorben-Kz
        tod = row.get("TODDT")
        res["deceasedDateTime" if tod else "deceasedBoolean"] = (
            _shift(priv, pid, tod) if tod else True)
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
        "status": "entered-in-error" if _storniert(row) else "finished",
        "class": {"system": T.V3_ACTCODE, "code": cls, "display": disp},
        "subject": _patient_ref(ns, mandt, pid),
        "period": {"start": _shift(priv, pid, row.get("BEGDT")),
                   "end": _shift(priv, pid, row.get("ENDAT"))},
        "meta": {"source": "sapfhir/NFAL"},
    }
    return res


def map_encounter_bewegung(row: dict, ns, priv=None, patnr=None) -> dict:
    """NBEW -> Sub-Encounter je Bewegung (partOf Fall-Encounter).
    NBEW hat keine PATNR — sie kommt aus dem FALNR->PATNR-Lookup (fuer subject
    UND Date-Shift; ANALYSE A4)."""
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    res = {
        "resourceType": "Encounter",
        "id": _ids.rid(ns, "EncounterBew", mandt, einri, falnr, lfdnr),
        "status": "entered-in-error" if _storniert(row) else "finished",
        "class": {"system": T.V3_ACTCODE, "code": "IMP"},
        "type": [{"text": BEWEGUNGSART.get(str(row.get("BEWTY", "")), "Bewegung")}],  # VERIFY
        "partOf": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "period": {"start": _shift(priv, patnr, row.get("BWIDT")),
                   "end": _shift(priv, patnr, row.get("BWEDT"))},
        "location": [{"location": {"display": row.get("ORGPF") or row.get("ORGFA")}}],
        "meta": {"source": "sapfhir/NBEW"},
    }
    if patnr:
        res["subject"] = _patient_ref(ns, mandt, patnr)
    return res


def map_condition(row: dict, ns, priv=None, patnr=None) -> dict:
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    patnr = patnr or row.get("PATNR")
    icd = row.get("DKEY1") or row.get("DIAID")   # VERIFY ICD-Spalte NDIA
    coding = {"system": T.ICD10GM, "code": icd}
    if row.get("DKAT1"):   # VERIFY Katalog-/Jahresversion
        coding["version"] = str(row.get("DKAT1"))
    res = {
        "resourceType": "Condition",
        "id": _ids.rid(ns, "Condition", mandt, einri, falnr, lfdnr),
        "code": {"coding": [coding], "text": row.get("DIATX")},   # VERIFY Freitext-Spalte
        "encounter": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "recordedDate": _shift(priv, patnr, row.get("DIADT")),   # VERIFY
        "meta": {"source": "sapfhir/NDIA"},
    }
    if patnr:
        res["subject"] = _patient_ref(ns, mandt, patnr)
    if _storniert(row):
        res["verificationStatus"] = {"coding": [{
            "system": T.COND_VERSTATUS, "code": "entered-in-error"}]}
    return res


def map_procedure(row: dict, ns, priv=None, patnr=None) -> dict:
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    patnr = patnr or row.get("PATNR")
    ops = row.get("ICPML") or row.get("ICPK1")   # VERIFY OPS-Spalte NICP
    coding = {"system": T.OPS, "code": ops}
    if row.get("ICKAT"):   # VERIFY Katalogversion
        coding["version"] = str(row.get("ICKAT"))
    res = {
        "resourceType": "Procedure",
        "id": _ids.rid(ns, "Procedure", mandt, einri, falnr, lfdnr),
        "status": "entered-in-error" if _storniert(row) else "completed",
        "code": {"coding": [coding]},
        "encounter": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "performedDateTime": _shift(priv, patnr, row.get("ICDAT")),   # VERIFY
        "meta": {"source": "sapfhir/NICP"},
    }
    if patnr:
        res["subject"] = _patient_ref(ns, mandt, patnr)
    return res


def map_observation_labor(row: dict, ns, priv=None, patnr=None,
                          loinc=None) -> dict:
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    patnr = patnr or row.get("PATNR")
    code_local = row.get("PARCD") or row.get("LABCD")   # VERIFY i.s.h.med Laborcode
    coding = []
    lo = loinc.lookup(code_local) if loinc else None
    if lo:
        coding.append({"system": T.LOINC, "code": lo})
    res = {
        "resourceType": "Observation",
        "id": _ids.rid(ns, "ObsLab", mandt, einri, falnr, lfdnr),
        "status": "entered-in-error" if _storniert(row) else "final",
        "category": [{"coding": [{"system": T.OBS_CATEGORY, "code": "laboratory"}]}],
        "code": {"coding": coding, "text": row.get("PARTX") or code_local},   # VERIFY
        "encounter": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "effectiveDateTime": _shift(priv, patnr, row.get("BEFDT")),   # VERIFY
        "meta": {"source": "sapfhir/N2LABOR"},
    }
    if patnr:
        res["subject"] = _patient_ref(ns, mandt, patnr)
    val = row.get("WERT")   # VERIFY
    try:
        vq = {"value": float(val)}
    except (TypeError, ValueError):
        vq = None
    if vq is not None:
        unit = row.get("EINH")   # VERIFY
        if unit:
            vq["unit"] = str(unit)
            uc = T.ucum(unit)
            if uc:
                vq["system"] = T.UCUM
                vq["code"] = uc
        res["valueQuantity"] = vq
    elif val not in (None, ""):
        res["valueString"] = str(val)
    if row.get("REFBER"):
        res["referenceRange"] = [{"text": row.get("REFBER")}]
    return res


def map_document_reference(row: dict, ns, priv=None, patnr=None) -> dict:
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    docid = row.get("DOCID")   # VERIFY
    patnr = patnr or row.get("PATNR")
    falnr = row.get("FALNR")
    res = {
        "resourceType": "DocumentReference",
        "id": _ids.rid(ns, "DocRef", mandt, einri, docid),
        "status": "entered-in-error" if _storniert(row) else "current",
        "type": {"text": row.get("DOCKA") or row.get("DOCTY")},   # VERIFY Dokumentkategorie
        "date": _shift(priv, patnr, row.get("DOCDT")),   # VERIFY
        "description": priv.text(patnr, row.get("DOCTX")) if priv else row.get("DOCTX"),
        "meta": {"source": "sapfhir/NDOC"},
        # Volltext bewusst NICHT hier -> DuckDB-FTS (doc_search)
    }
    if patnr:
        res["subject"] = _patient_ref(ns, mandt, patnr)
    if falnr:
        res["context"] = {"encounter": [{"reference": "Encounter/" +
                          _ids.rid(ns, "Encounter", mandt, einri, falnr)}]}
    return res


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
