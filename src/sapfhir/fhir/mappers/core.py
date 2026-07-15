# -*- coding: utf-8 -*-
"""IS-H / i.s.h.med -> FHIR R4 Kernmapper (v3).

Verifikationsstand:
- Live-DB-Runden 1-3 (docs/VERIFY_RESULTS*.md): NPAT/NFAL/NBEW/NDIA/NICP-Felder,
  Diagnose-Flags, DKEY2-Katalogredundanz, NICP-PK=LNRIC, Kataloge DKAT1/ICPMK.
- Altbestand-Abgleich (docs/ALTBESTAND_ANALYSE.md): BEWTY-Korrektur (2=Entlassung!),
  BWEDT=9999=offen, DIAGW=Diagnosesicherheit, TUDIA=Todesursache, NAPX-Klartexte.

Invarianten (ANALYSE A4/A5):
- Jede Ressource mit Patientenbezug traegt subject; PATNR kommt fuer NBEW/NDIA/
  NICP/N2LABOR/NDOC aus dem FALNR->PATNR-Lookup (ndjson.py).
- JEDES Datum laeuft durch priv.shift(patnr, ...).
"""
from __future__ import annotations
from .. import ids as _ids
from .. import terminology as T

# --- Enum-Tabellen -----------------------------------------------------------
GESCHLECHT = {  # NPAT.GSCHL — verifiziert (Live: 1/2/3/' ')
    "1": "male", "2": "female", "3": "other", " ": "unknown", "": "unknown",
}
FALLART = {     # NFAL.FALAR — Altbestand bestaetigt 1/2/3; Enum-Text aus TN24T-Umfeld
    "1": ("IMP", "stationaer"),
    "2": ("AMB", "ambulant"),
    "3": ("SS",  "teilstationaer"),
}
# NBEW.BEWTY — KORRIGIERT nach Altbestand (produktive Bewegungs-Prozedur) +
# Live-Zahlen (Aufnahmen 1,617 Mio ≈ '2' 1,614 Mio => 2=Entlassung, 3=Verlegung).
# Autoritative Quelle ist der Katalog sap.TN14T (Referenzschicht) — Lookup folgt.
BEWEGUNGSART = {
    "1": "Aufnahme",
    "2": "Entlassung",              # Altbestand: Bewegung_Entlassung (NICHT Verlegung)
    "3": "Verlegung",
    "4": "ambulanter Besuch",       # Massenfall (22,6 Mio)
    "6": "Beurlaubung",
    "7": "Rueckkehr aus Beurlaubung",
}
# Katalog-Kennung -> FHIR-System (verifiziert: DKAT1='56' ICD-10-GM, ICPMK='36' OPS;
# DKAT '49'-'55' = aeltere ICD-10-GM-Jahresversionen)
DIA_KATALOG_SYSTEM = {str(k): T.ICD10GM for k in (49, 50, 51, 52, 53, 54, 55, 56)}
OPS_KATALOG_SYSTEM = {"36": T.OPS}


def _shift(priv, pid, iso):
    return priv.shift(pid, iso) if priv else iso


def _x(v) -> bool:
    return str(v or "").strip() == "X"


def _storniert(row: dict) -> bool:
    return str(row.get("STORN") or "").strip() not in ("", "0")


def _offenes_ende(iso) -> str | None:
    """BWEDT/ENDAT mit Jahr 9999 = unbekanntes/offenes Ende (Altbestand-Regel)."""
    if iso and str(iso)[:4] == "9999":
        return None
    return iso


def _patient_ref(ns, mandt, patnr) -> dict:
    return {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, patnr)}


def map_patient(row: dict, ns, priv=None, adr: dict | None = None) -> dict:
    pid = row.get("PATNR")
    res = {
        "resourceType": "Patient",
        "id": _ids.rid(ns, "Patient", row.get("MANDT"), pid),
        "identifier": [{"system": "urn:ish:patnr", "value": pid}],
        "gender": GESCHLECHT.get(str(row.get("GSCHL", "")).strip() or "", "unknown"),
        "meta": {"source": "sapfhir/NPAT"},
    }
    gb = row.get("GBDAT")   # verifiziert: NPAT.GBDAT (DATS)
    if gb:
        res["birthDate"] = _shift(priv, pid, gb)
    # Sterbestatus (verifiziert: TODKZ='X'/TODDT, 32.379 Faelle)
    if _x(row.get("TODKZ")):
        tod = row.get("TODDT")
        if tod:
            res["deceasedDateTime"] = _shift(priv, pid, tod)
        else:
            res["deceasedBoolean"] = True
    # Patienten-Zusammenfuehrung (verifiziert: RFPAT, 26.388) -> link replaces
    rf = str(row.get("RFPAT") or "").strip()
    if rf and rf != "0000000000":
        res["link"] = [{"other": {"reference": "Patient/" + _ids.rid(
            ns, "Patient", row.get("MANDT"), rf)}, "type": "replaces"}]
    # Name/Adresse nur bei Klarbetrieb (verifiziert: NNAME/VNAME Klartext)
    if priv is None or priv.mode == "off":
        nn = row.get("NNAME"); vn = row.get("VNAME")
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
    cls, disp = FALLART.get(str(row.get("FALAR", "")).strip(), ("IMP", "stationaer"))
    res = {
        "resourceType": "Encounter",
        "id": _ids.rid(ns, "Encounter", mandt, row.get("EINRI"), falnr),
        "identifier": [{"system": "urn:ish:falnr",
                        "value": f"{row.get('EINRI')}-{falnr}"}],
        "status": "entered-in-error" if _storniert(row) else "finished",
        "class": {"system": T.V3_ACTCODE, "code": cls, "display": disp},
        "subject": _patient_ref(ns, mandt, pid),
        "period": {"start": _shift(priv, pid, row.get("BEGDT")),
                   "end": _shift(priv, pid, _offenes_ende(row.get("ENDAT")))},
        "meta": {"source": "sapfhir/NFAL"},
    }
    # Statistiksperre (Altbestand: NFAL.STASP) als Meta-Tag — Konsumenten
    # (Marts, mcp.*-Views) filtern solche Faelle aus der Analytik.
    if _x(row.get("STASP")):
        res["meta"]["tag"] = [{"system": "urn:ish:flag", "code": "statistiksperre"}]
    return res


def map_encounter_bewegung(row: dict, ns, priv=None, patnr=None) -> dict:
    """NBEW -> Sub-Encounter je Bewegung (partOf Fall-Encounter)."""
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    bewty = str(row.get("BEWTY", "")).strip()
    res = {
        "resourceType": "Encounter",
        "id": _ids.rid(ns, "EncounterBew", mandt, einri, falnr, lfdnr),
        "status": "entered-in-error" if _storniert(row) else "finished",
        "class": {"system": T.V3_ACTCODE, "code": "IMP"},
        "type": [{"text": BEWEGUNGSART.get(bewty, "Bewegung")}],
        "partOf": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "period": {"start": _shift(priv, patnr, row.get("BWIDT")),
                   "end": _shift(priv, patnr, _offenes_ende(row.get("BWEDT")))},
        "location": [{"location": {"display": row.get("ORGPF") or row.get("ORGFA")}}],
        "meta": {"source": "sapfhir/NBEW"},
    }
    if patnr:
        res["subject"] = _patient_ref(ns, mandt, patnr)
    # BEWTY 6=Beurlaubung -> onleave (7 = Rueckkehr beendet die Abwesenheit)
    if bewty == "6" and not _storniert(row):
        res["status"] = "onleave"
    return res


def _dia_kategorien(row: dict) -> list[dict]:
    """Alle zutreffenden Diagnoseverwendungen als FHIR-category. Verifiziert Runde 3:
    die *DIA-Flags sind NICHT exklusiv (KH-Hauptdiagnose ist fast immer zugleich
    FHDIA+BHDIA). Klartexte nach Altbestand (produktive Diagnosen-Prozedur);
    PODIA/ARDIA tragen einen offenen Deutungskonflikt."""
    flags = [
        ("KHDIA", "Krankenhaushauptdiagnose"),
        ("FHDIA", "Fachabteilungshauptdiagnose"),
        ("AFDIA", "Aufnahmediagnose"),
        ("ENDIA", "Entlassdiagnose"),
        ("EWDIA", "Einweisungsdiagnose"),
        ("BHDIA", "Behandlungsdiagnose"),
        ("OPDIA", "OP-Diagnose"),
        ("DIAPR", "medizinische Nebendiagnose"),   # Altbestand
        ("PODIA", "praeoperative Diagnose"),  # VERIFY-KONFLIKT: Altbestand 'praeoperativ', Runde 3 'postoperativ'
        ("TUDIA", "Todesursache"),            # Altbestand (SAP: TU=Todesursache); Runde 3 'Tumordiagnose' war falsch
        ("ARDIA", "Arbeitsdiagnose"),         # VERIFY-KONFLIKT: evtl. 'Arbeitsunfalldiagnose'
    ]
    return [{"text": txt} for f, txt in flags if _x(row.get(f))]


def map_condition(row: dict, ns, priv=None, patnr=None) -> dict:
    # NDIA verifiziert (Runde 1+3 + Altbestand): DKEY1=ICD, DKAT1=Katalogversion,
    # DKEY2 i.d.R. DERSELBE Kode in aelterer Katalogversion -> nur bei DKEY1<>DKEY2
    # als 2. Coding (sonst ~14,4 Mio Dubletten). Klartext DITXT; Sicherheit DIAGW
    # (Altbestand; DIASI im Haus leer); Lokalisation DIALO; Bemerkung KZTXT.
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    patnr = patnr or row.get("PATNR")
    icd = row.get("DKEY1")
    system = DIA_KATALOG_SYSTEM.get(str(row.get("DKAT1") or "").strip(), T.ICD10GM)
    coding = []
    if icd:
        c = {"system": system, "code": icd}
        if row.get("DKAT1"):
            c["version"] = str(row.get("DKAT1"))
        coding.append(c)
    dkey2 = str(row.get("DKEY2") or "").strip()
    if dkey2 and dkey2 != str(icd or "").strip():
        sys2 = DIA_KATALOG_SYSTEM.get(str(row.get("DKAT2") or "").strip(), system)
        coding.append({"system": sys2, "code": row.get("DKEY2")})
    text = row.get("DITXT") or row.get("ALTERN_DIATXT") or row.get("KZTXT")
    res = {
        "resourceType": "Condition",
        "id": _ids.rid(ns, "Condition", mandt, einri, falnr, lfdnr),
        "code": {"coding": coding,
                 "text": priv.text(patnr, text) if priv else text},
        "encounter": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "recordedDate": _shift(priv, patnr, row.get("DIADT")),
        "meta": {"source": "sapfhir/NDIA"},
    }
    if patnr:
        res["subject"] = _patient_ref(ns, mandt, patnr)
    kats = _dia_kategorien(row)
    if kats:
        res["category"] = kats
    if row.get("DIALO"):   # Seitenlokalisation (Altbestand)
        res["bodySite"] = [{"text": str(row.get("DIALO")).strip()}]
    # Diagnosesicherheit: DIAGW (Altbestand) vor DIASI (im Haus leer)
    sich = str(row.get("DIAGW") or row.get("DIASI") or "").strip()
    if sich:
        res.setdefault("extension", []).append({
            "url": "https://fhir.de/StructureDefinition/icd-10-gm-diagnosesicherheit",
            "valueCode": sich})
    if _storniert(row):
        res["verificationStatus"] = {"coding": [{
            "system": T.COND_VERSTATUS, "code": "entered-in-error"}]}
    return res


def map_procedure(row: dict, ns, priv=None, patnr=None) -> dict:
    # NICP verifiziert: PK=LNRIC (+LFDBEW), OPS=ICPML, Katalog=ICPMK('36'=OPS),
    # Klartext=BTEXT, OP-Datum/-Zeit=BGDOP/ENDOP+BZTOP/EZTOP, OE=ORGFA/ORGPF.
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lnric = row.get("LNRIC")
    patnr = patnr or row.get("PATNR")
    ops = row.get("ICPML")
    system = OPS_KATALOG_SYSTEM.get(str(row.get("ICPMK") or "").strip(), T.OPS)
    coding = [{"system": system, "code": ops}] if ops else []
    if coding and row.get("ICPMK"):
        coding[0]["version"] = str(row.get("ICPMK"))
    res = {
        "resourceType": "Procedure",
        "id": _ids.rid(ns, "Procedure", mandt, lnric),
        "status": "entered-in-error" if _storniert(row) else "completed",
        "code": {"coding": coding, "text": row.get("BTEXT")},
        "encounter": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "meta": {"source": "sapfhir/NICP"},
    }
    if patnr:
        res["subject"] = _patient_ref(ns, mandt, patnr)
    if row.get("BGDOP"):
        res["performedPeriod"] = {
            "start": _shift(priv, patnr, row.get("BGDOP")),
            "end": _shift(priv, patnr, _offenes_ende(row.get("ENDOP"))
                          or row.get("BGDOP"))}
    if row.get("ORGFA"):
        res["performer"] = [{"actor": {"display": row.get("ORGFA")}}]
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


def map_coverage(row: dict, ns, priv=None) -> dict:
    """NKSK -> Coverage (verifiziert Runde 2): Kostenuebernahme je Fall,
    primaere Coverage-Quelle (9,5 Mio; ersetzt NFPZ)."""
    mandt = row.get("MANDT"); belnr = row.get("BELNR")
    einri = row.get("EINRI"); falnr = row.get("FALNR"); kostr = row.get("KOSTR")
    res = {
        "resourceType": "Coverage",
        "id": _ids.rid(ns, "Coverage", mandt, belnr),
        "status": "cancelled" if _storniert(row) else "active",
        "beneficiary": {"reference": "Encounter/" + _ids.rid(
            ns, "Encounter", mandt, einri, falnr)},
        "payor": [{"reference": "Organization/" + _ids.rid(ns, "OrgKostr", mandt, kostr)}],
        "period": {"start": row.get("BEGDT"), "end": _offenes_ende(row.get("ENDDT"))},
        "type": {"text": (row.get("KSTYP") or "").strip() or None},
        "meta": {"source": "sapfhir/NKSK"},
    }
    if str(kostr or "").strip() == "0009999999":   # verifizierter Sammelplatzhalter
        res["type"] = {"text": "Selbstzahler"}
    return res


def map_geburt(row: dict, ns, priv=None, patnr=None) -> list:
    """NGEB -> Observations (verifiziert Runde 2): Perinataldaten Neugeborenes
    (Gewicht/Laenge/Kopfumfang), verknuepft ueber den Kind-Fall FALN1."""
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    faln1 = row.get("FALN1"); lfdnr = row.get("LFDNR")
    enc = "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, faln1)
    born = _shift(priv, patnr, row.get("GBDAT"))
    out = []

    def obs(kind, loinc_code, value, unit):
        if value in (None, "", 0):
            return
        try:
            v = float(str(value).replace(",", "."))
        except ValueError:
            return
        out.append({
            "resourceType": "Observation",
            "id": _ids.rid(ns, "ObsGeb", mandt, einri, faln1, lfdnr, kind),
            "status": "final",
            "category": [{"coding": [{"system": T.OBS_CATEGORY,
                                      "code": "vital-signs"}]}],
            "code": {"coding": [{"system": T.LOINC, "code": loinc_code}],
                     "text": kind},
            "encounter": {"reference": enc},
            "effectiveDateTime": born,
            "valueQuantity": {"value": v, "unit": unit},
            "meta": {"source": "sapfhir/NGEB"},
        })
    obs("Geburtsgewicht", "8339-4", row.get("GBGEW"), "g")
    obs("Geburtslaenge", "8305-5", row.get("GBGRO"), "cm")
    obs("Kopfumfang", "8287-5", row.get("HEAD_SIZE"), "cm")
    return out


def map_location_bau(row: dict, ns, priv=None) -> dict:
    """NBAU -> Location (verifiziert Runde 2): Gebaeude mit Geokoordinaten."""
    mandt = row.get("MANDT"); bauid = row.get("BAUID")
    res = {
        "resourceType": "Location",
        "id": _ids.rid(ns, "LocationBau", mandt, bauid),
        "status": "inactive" if _x(row.get("LOEKZ")) else "active",
        "name": row.get("BAUNA"),
        "physicalType": {"text": (row.get("BAUTY") or "").strip() or "Gebaeude"},
        "meta": {"source": "sapfhir/NBAU"},
    }
    x = row.get("XKOOR"); y = row.get("YKOOR")
    if x and y:
        try:
            res["position"] = {"longitude": float(str(x).replace(",", ".")),
                               "latitude": float(str(y).replace(",", "."))}
        except ValueError:
            pass
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
    "Coverage": map_coverage,
    "ObservationGeburt": map_geburt,
    "LocationBau": map_location_bau,
}
