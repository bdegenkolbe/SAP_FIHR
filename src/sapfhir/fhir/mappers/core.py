# -*- coding: utf-8 -*-
"""IS-H / i.s.h.med -> FHIR R4 Kernmapper.

Jede Funktion nimmt eine Bronze-Zeile (dict) plus Kontext (ids-Namespace, privacy) und
liefert eine FHIR-Ressource (dict). Feldkennungen, die noch nicht gegen Live-DB bzw.
offizielle SAP-IS-H-Doku (sapdatasheet.org) verifiziert sind, sind mit # VERIFY markiert.

Verifiziert gegen Live-replicate: NPAT-, NFAL-, NBEW-Spalten existieren wie referenziert.
Enum-Belegungen (FALAR, BEWTY, GSCHL) sind fachlich zu bestaetigen -> # VERIFY.
"""
from __future__ import annotations
import re
from .. import ids as _ids

# --- Enum-Tabellen (verifiziert gegen Live-replicate 15.07.2026) ------------
GESCHLECHT = {  # NPAT.GSCHL — verifiziert: 1/2/3/' ' kommen vor
    "1": "male", "2": "female", "3": "other", " ": "unknown", "": "unknown",
}
FALLART = {     # NFAL.FALAR — verifiziert R7 (Domaene FALLART, sapdatasheet)
    "1": ("IMP", "stationaer"),        # Inpatient Case
    "2": ("AMB", "ambulant"),          # Outpatient Case
    "3": ("SS",  "teilstationaer"),    # Day Patient Case (Tagesfall)
}
BEWEGUNGSART = {  # NBEW.BEWTY — verifiziert R6 gegen Katalog TN14T (hauseigene Texte)
    "1": "Aufnahme",
    "2": "Entlassung",         # KORRIGIERT R6 (war faelschlich 'Verlegung')
    "3": "Verlegung",          # KORRIGIERT R6 (war faelschlich 'Entlassung')
    "4": "ambulanter Besuch",  # dominierender Massenfall (22,6 Mio)
    "6": "Abwesenheit Beginn", # Beurlaubung
    "7": "Abwesenheit Ende",   # Rueckkehr aus Beurlaubung
}
# Diagnosekatalog-Kennung (NDIA.DKAT1 / NICP.ICPMK) -> FHIR-System
DIA_KATALOG_SYSTEM = {
    "56": "http://fhir.de/CodeSystem/bfarm/icd-10-gm",   # verifiziert: DKAT1='56'
}
OPS_KATALOG_SYSTEM = {
    "36": "http://fhir.de/CodeSystem/bfarm/ops",         # verifiziert: ICPMK='36'
}
ISH_SYS = {   # IS-H-Customizing-Kataloge (verifiziert R7 via sapdatasheet FK)
    "tn14g": "urn:ish:tn14g",   # NBEW.BWGR1/2 Bewegungsgrund (EDI, §301 Aufnahme-/Entl.grund)
    "tn14d": "urn:ish:tn14d",   # NBEW.EZUST Entlasszustand / discharge disposition
    "tn14h": "urn:ish:tn14h",   # NBEW.RFSRC Einweisungs-/Nachbehandlungsart (referral)
    "tn14k": "urn:ish:tn14k",   # NBEW.UNFAV Aufnahme-/Anreiseart (mode of arrival)
}


def _shift(priv, pid, iso):
    return priv.shift(pid, iso) if priv else iso


def _echtes_datum(d):
    """Sentinel-Filter (R16, Datenaudit): SAP-Leerdatum '00000000' kommt via Qlik als
    0101-01-01 an (NFAL: 2,21 Mio = 23%% aller Faelle!), SAP-Unendlich als 9999-12-31.
    Beides ist KEIN fachliches Datum -> None. Jahr<1901 oder >=9999 = Sentinel."""
    if not d:
        return None
    s = str(d)
    y = s[:4]
    if not y.isdigit():
        return None
    yi = int(y)
    if yi < 1901 or yi >= 9999:
        return None
    return d


def map_patient(row: dict, ns, priv=None, adr: dict | None = None) -> dict:
    pid = row.get("PATNR")
    res = {
        "resourceType": "Patient",
        "id": _ids.rid(ns, "Patient", row.get("MANDT"), pid),
        "identifier": [{"system": "urn:ish:patnr", "value": pid}],
        "gender": GESCHLECHT.get(str(row.get("GSCHL", "")), "unknown"),
        "meta": {"source": "sapfhir/NPAT"},
    }
    gb = row.get("GBDAT")   # verifiziert: NPAT.GBDAT (DATS)
    if gb:
        res["birthDate"] = _shift(priv, pid, gb)
    # Sterbestatus (verifiziert: TODKZ/TODDT, 32.379 Faelle)
    if str(row.get("TODKZ") or "").strip() == "X":
        res["deceasedBoolean"] = True
        if row.get("TODDT"):
            res["deceasedDateTime"] = _shift(priv, pid, row.get("TODDT"))
    # Merge-Referenz (verifiziert: RFPAT, 26.388 Faelle) -> Patient.link replaces
    rf = str(row.get("RFPAT") or "").strip()
    if rf and rf != "0000000000":
        res["link"] = [{"other": {"reference": "Patient/" + _ids.rid(
            ns, "Patient", row.get("MANDT"), rf)}, "type": "replaces"}]
    # Hausarzt (verifiziert R7: NPAT.HARNR -> NGPA/Practitioner)
    har = str(row.get("HARNR") or "").strip()
    if har and har != "0000000000":
        res["generalPractitioner"] = [{"reference": "Practitioner/" + _ids.rid(
            ns, "Practitioner", row.get("MANDT"), har)}]
    # Name/Adresse nur bei Klarbetrieb (verifiziert: NNAME/VNAME Klartext)
    if priv is None or priv.mode == "off":
        nn = row.get("NNAME"); vn = row.get("VNAME")
        if nn or vn:
            res["name"] = [{"family": nn, "given": [vn] if vn else []}]
        # Adresse liegt direkt auf NPAT (ORT/STRAS/PSTLZ/LAND, verifiziert R7);
        # adr-Fallback = NADR-Join (ADRNR+ADROB='NPAT') mit denselben Feldnamen.
        src = row if (row.get("ORT") or row.get("STRAS")) else (adr or {})
        if src.get("STRAS") or src.get("ORT"):
            res["address"] = [{
                "line": [src.get("STRAS")] if src.get("STRAS") else [],
                "city": src.get("ORT"), "postalCode": src.get("PSTLZ"),
                "country": src.get("LAND"),
            }]
    if priv:
        res = priv.redact_patient(res, pid)
    return res


def _norg_ref(ns, mandt, orgid):
    """OE-Referenz (NBEW/NICP.ORGFA/ORGPF/ORGAU -> NORG.ORGID, verifiziert R7)."""
    oid = str(orgid or "").strip()
    if not oid or oid in ("00000000", "0"):
        return None
    return "Organization/" + _ids.rid(ns, "OrgNorg", mandt, oid)


def _cc(system, code, text=None):
    code = str(code or "").strip()
    if not code or code == "0":
        return None
    cc = {"coding": [{"system": system, "code": code}]}
    if text:
        cc["text"] = text
    return cc


def _hospitalization(bewegungen):
    """Encounter.hospitalization aus den Bewegungen eines Falls (verifiziert R7, NBEW):
    Aufnahmebewegung (BEWTY=1) -> admitSource (RFSRC->TN14H / UNFAV->TN14K / BWGR1->TN14G);
    Entlassbewegung (BEWTY=2)  -> dischargeDisposition (EZUST->TN14D / BWGR1->TN14G)."""
    if not bewegungen:
        return None

    def _pick(bewty):
        cand = [b for b in bewegungen if str(b.get("BEWTY") or "").strip() == bewty
                and str(b.get("STORN") or "").strip() in ("", "0")]
        return cand[0] if cand else None

    hosp = {}
    adm = _pick("1")
    if adm:
        src = (_cc(ISH_SYS["tn14h"], adm.get("RFSRC"))
               or _cc(ISH_SYS["tn14k"], adm.get("UNFAV"))
               or _cc(ISH_SYS["tn14g"], adm.get("BWGR1")))
        if src:
            hosp["admitSource"] = src
    dis = _pick("2")
    if dis:
        dd = _cc(ISH_SYS["tn14d"], dis.get("EZUST")) or _cc(ISH_SYS["tn14g"], dis.get("BWGR1"))
        if dd:
            hosp["dischargeDisposition"] = dd
    return hosp or None


def _participants_nfpz(personal, ns, mandt):
    """NFPZ-Zeilen -> Encounter.participant[]. Verifiziert R12 gegen replicate:
    NFPZ PK [MANDT,EINRI,FALNR,PERNR,LFDNR] = Fall<->behandelnde Person. PERNR->NPER
    (Practitioner, ID-Schema 'PractitionerNper'). FARZT=Funktion der Person im Fall
    (Live: 1/2/5/6/7/9/E belegt; Katalog hier nicht repliziert -> Rohcode urn:ish:farzt).
    BEGDT/ENDDT=Zeitraum der Zuordnung, STORN=Storno (wird uebersprungen)."""
    out = []
    for p in (personal or []):
        if str(p.get("STORN") or "").strip() not in ("", "0"):
            continue
        pernr = str(p.get("PERNR") or "").strip()
        if not pernr or pernr == "0000000000":
            continue
        # R13: GEMEINSAMES ID-Schema 'Practitioner' — replicate-verifiziert:
        # NGPA.GPART == NPER.PERNR fuer ALLE 236.114 Personen (PERS='X') -> dieselbe
        # Person, derselbe Schluessel, EINE Practitioner-Ressource (keine Dubletten).
        part = {"individual": {"reference": "Practitioner/" + _ids.rid(
            ns, "Practitioner", mandt, pernr)}}
        typ = _cc("urn:ish:farzt", p.get("FARZT"))
        if typ:
            part["type"] = [typ]
        start = p.get("BEGDT"); end = p.get("ENDDT")
        if start or end:
            part["period"] = {k: v for k, v in (("start", start), ("end", end)) if v}
        out.append(part)
    return out


# NFFZ.REFA — Fall-Bezugsarten (R15, Liveverteilung; nur M/N durch NGEB-Abgleich GESICHERT)
FALLBEZUG = {
    "M": "Mutter", "N": "Neugeborenes",          # gesichert (NGEB-Groessenordnung)
    "P": "Patient (zu Begleitperson)",           # Deutung aus P<->B-Paarung
    "B": "Begleitperson",
}


def _fallbezuege_nffz(verknuepfungen, ns, mandt, einri):
    """NFFZ-Zeilen (dieses Falls als FALN1) -> Encounter-Extensions. Verifiziert R14/R15:
    FALN1<->FALN2 mit REFA1/REFA2 (Bezugsart je Seite). Verlustfrei: JEDER nicht stornierte
    Bezug wird als Extension urn:ish:fallbezug ausgeleitet (Rohcodes + Referenz auf den
    Partner-Encounter); Display nur fuer gesicherte Codes (FALLBEZUG-Map)."""
    out = []
    for v in (verknuepfungen or []):
        if str(v.get("STORN") or "").strip() not in ("", "0"):
            continue
        faln2 = str(v.get("FALN2") or "").strip()
        if not faln2:
            continue
        refa1 = str(v.get("REFA1") or "").strip()
        refa2 = str(v.get("REFA2") or "").strip()
        ext = {"url": "urn:ish:fallbezug", "extension": [
            {"url": "partner", "valueReference": {"reference": "Encounter/" + _ids.rid(
                ns, "Encounter", mandt, v.get("EINRI") or einri, faln2)}},
        ]}
        if refa1:
            cc = _cc("urn:ish:refa", refa1, FALLBEZUG.get(refa1))
            ext["extension"].append({"url": "rolle-dieser-fall", "valueCodeableConcept": cc})
        if refa2:
            cc2 = _cc("urn:ish:refa", refa2, FALLBEZUG.get(refa2))
            ext["extension"].append({"url": "rolle-partner", "valueCodeableConcept": cc2})
        out.append(ext)
    return out


def map_encounter(row: dict, ns, priv=None, bewegungen: list | None = None,
                  apxnr: str | None = None, personal: list | None = None,
                  verknuepfungen: list | None = None) -> dict:
    """NFAL -> Encounter. `apxnr` (optional, aus NAPX_FAL-Lookup je FALNR): der Fall ist
    Teil einer ABRECHNUNGS-Fallzusammenfuehrung -> Encounter.account verweist auf den
    Account(APXNR). Der Encounter selbst bleibt medizinisch unveraendert (R11):
    status=finished, eigener Zeitraum — die Zusammenfuehrung ist nur die Abrechnungsklammer.
    `personal` (optional, NFPZ-Zeilen des Falls) -> Encounter.participant (R12)."""
    pid = row.get("PATNR"); falnr = row.get("FALNR"); mandt = row.get("MANDT")
    cls, disp = FALLART.get(str(row.get("FALAR", "")), ("IMP", "stationaer"))
    # R16 (Datenaudit): ENDDT=0101-01-01 ist das Qlik-geladene SAP-Leerdatum -> OFFENER
    # Fall (23% des Bestands!). Dann KEIN period.end und status=in-progress statt finished.
    ende = _echtes_datum(row.get("ENDDT"))   # ENDDT=Fallende (ENDAT=Entbindung!)
    period = {"start": _shift(priv, pid, row.get("BEGDT"))}
    if ende:
        period["end"] = _shift(priv, pid, ende)
    res = {
        "resourceType": "Encounter",
        "id": _ids.rid(ns, "Encounter", mandt, row.get("EINRI"), falnr),
        "identifier": [{"system": "urn:ish:falnr",
                        "value": f"{row.get('EINRI')}-{falnr}"}],
        "status": "finished" if ende else "in-progress",
        "class": {"code": cls, "display": disp},
        "subject": {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, pid)},
        "serviceProvider": {"reference": "Organization/" + _ids.rid(
            ns, "OrgEinri", mandt, row.get("EINRI"))},
        "period": period,
        "meta": {"source": "sapfhir/NFAL"},
    }
    hosp = _hospitalization(bewegungen)
    if hosp:
        res["hospitalization"] = hosp
    # Abrechnungs-Fallzusammenfuehrung (NAPX): nur Account-Referenz, KEIN replaces/partOf
    if apxnr:
        res["account"] = [{"reference": "Account/" + _ids.rid(ns, "AccountApx", mandt, apxnr)}]
    # Behandelnde Personen (NFPZ) -> participant (R12)
    parts = _participants_nfpz(personal, ns, mandt)
    if parts:
        res["participant"] = parts
    # Klinische Fall-Verknuepfungen (NFFZ) -> Extensions (R15; KEIN partOf/replaces)
    bezuege = _fallbezuege_nffz(verknuepfungen, ns, mandt, row.get("EINRI"))
    if bezuege:
        res.setdefault("extension", []).extend(bezuege)
    if str(row.get("STORN") or "") not in ("", "0"):
        res["status"] = "entered-in-error"
    return res


def map_encounter_bewegung(row: dict, ns, priv=None) -> dict:
    """NBEW -> Sub-Encounter je Bewegung (partOf Fall-Encounter). Verifiziert R7 (sapdatasheet):
    PK [MANDT,EINRI,FALNR,LFDNR]; Kette VGNREF(prev)/NFGREF(next)->NBEW.LFDNR; Zeitraum
    BWIDT/BWIZT..BWEDT/BWEZT; fachl./pfleg. OE ORGFA/ORGPF->NORG.ORGID; Ort ZIMMR(Raum)/
    BETT(Bett)->NBAU; Bewegungsgrund BWGR1(+BWGR2)->TN14G; Fachrichtung FACHR->TNKFA."""
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    bewty = str(row.get("BEWTY", "")).strip()
    res = {
        "resourceType": "Encounter",
        "id": _ids.rid(ns, "EncounterBew", mandt, einri, falnr, lfdnr),
        "status": "finished",
        "class": {"code": "IMP"},
        "type": [{"text": BEWEGUNGSART.get(bewty, "Bewegung")}],
        "partOf": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "period": {"start": _dt(row.get("BWIDT"), row.get("BWIZT")),
                   "end": _dt(row.get("BWEDT"), row.get("BWEZT"))},
        "meta": {"source": "sapfhir/NBEW"},
    }
    # Verantwortliche Fachabteilung ORGFA -> Organization(NORG)
    dept = _norg_ref(ns, mandt, row.get("ORGFA"))
    if dept:
        res["serviceProvider"] = {"reference": dept}
    # Pflegerische OE ORGPF (falls abweichend) als Extension
    pfleg = _norg_ref(ns, mandt, row.get("ORGPF"))
    if pfleg and pfleg != dept:
        res["extension"] = [{"url": "urn:ish:nursing-org",
                             "valueReference": {"reference": pfleg}}]
    # Physischer Ort: Raum ZIMMR / Bett BETT -> Location(NBAU)
    loc = []
    for fld, ptype in (("ZIMMR", "ro"), ("BETT", "bd")):
        bau = str(row.get(fld) or "").strip()
        if bau and bau not in ("00000000", "0"):
            loc.append({"location": {"reference": "Location/" + _ids.rid(
                ns, "LocationBau", mandt, bau)},
                "physicalType": {"coding": [{
                    "system": "http://terminology.hl7.org/CodeSystem/location-physical-type",
                    "code": ptype}]}})
    if loc:
        res["location"] = loc
    # Bewegungsgrund BWGR1(Pos.1-2)+BWGR2(Pos.3-4) -> TN14G
    grund = (str(row.get("BWGR1") or "").strip() + str(row.get("BWGR2") or "").strip()).strip()
    rc = _cc(ISH_SYS["tn14g"], grund)
    if rc:
        res["reasonCode"] = [rc]
    # Fachrichtung FACHR -> TNKFA
    fr = _cc("urn:ish:tnkfa", row.get("FACHR"))
    if fr:
        res["serviceType"] = fr
    # BEWTY 6=Beurlaubung -> onleave (verifiziert R6)
    if bewty == "6":
        res["status"] = "onleave"
    if str(row.get("STORN") or "").strip() not in ("", "0"):
        res["status"] = "entered-in-error"
    return res


def _dia_kategorien(row: dict) -> list[dict]:
    """Alle zutreffenden Diagnoseverwendungen als FHIR-category (verifiziert Runde 3:
    die *DIA-Flags sind NICHT exklusiv, eine Diagnose traegt oft mehrere Rollen —
    z.B. KH-Hauptdiagnose ist zugleich FHDIA + BHDIA). Reihenfolge = Spezifitaet."""
    flags = [
        ("KHDIA", "Krankenhaushauptdiagnose"),
        ("FHDIA", "Fachabteilungshauptdiagnose"),
        ("AFDIA", "Aufnahmediagnose"),
        ("ENDIA", "Entlassdiagnose"),
        ("EWDIA", "Einweisungsdiagnose"),
        ("BHDIA", "Behandlungsdiagnose"),
        ("OPDIA", "OP-Diagnose"),
        # VERIFY-KONFLIKT geloest (SAP-Datenelemente, leanx/se80 ABAP-Dict):
        # PODIA=N2_KZPODIA "Preoperative Diagnosis"   (NICHT postoperativ)
        # TUDIA=N2_KZTUDIA "Cause of Death Indicator"  (NICHT Tumordiagnose)
        # ARDIA=N2_KZARDIA "Working Diagnosis"         (NICHT Arbeitsunfall)
        ("PODIA", "praeoperative Diagnose"),
        ("TUDIA", "Todesursachen-Diagnose"),
        ("ARDIA", "Arbeitsdiagnose"),
    ]
    return [{"text": txt} for f, txt in flags
            if str(row.get(f) or "").strip() == "X"]


def map_condition(row: dict, ns, priv=None, kodetext: dict | None = None) -> dict:
    # NDIA verifiziert (Runde 1+3): DKEY1=ICD, DKAT1=Katalogversion ('56'=aktuelle
    # ICD-10-GM), DKEY2/DKAT2 = i.d.R. DERSELBE Kode in aelterer Katalogversion
    # (KEINE Kreuz-Stern-Notation!) -> nur als 2. Coding wenn DKEY1<>DKEY2.
    # DITXT=Klartext, DIASI=Sicherheit (im Haus leer), *DIA-Flags=Verwendung, STORN.
    # `kodetext` (optional, R13): NKDI-Lookup '<DKAT>|<DKEY>' -> DTEXT1 (verifiziert R9/R13:
    # NKDI PK [MANDT,SPRAS,DKAT,DKEY], SPRAS='D', Text in DTEXT1, z.B. '56|J36' ->
    # 'Peritonsillarabszess'). Liefert coding.display + code.text-Fallback, wenn DITXT leer.
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lfdnr = row.get("LFDNR")
    icd = row.get("DKEY1")
    dkat1 = str(row.get("DKAT1") or "").strip()
    system = DIA_KATALOG_SYSTEM.get(dkat1, "http://fhir.de/CodeSystem/bfarm/icd-10-gm")
    kt = kodetext or {}
    coding = []
    if icd:
        c1 = {"system": system, "code": icd}
        disp = (kt.get(f"{dkat1}|{str(icd).strip()}") or "").strip()
        if disp:
            c1["display"] = disp
        coding.append(c1)
    # Sekundaerkode nur bei echt abweichendem ICD (~1 Mio Faelle), nicht bei
    # blosser Katalogversions-Redundanz (~14 Mio Faelle).
    dkey2 = str(row.get("DKEY2") or "").strip()
    if dkey2 and dkey2 != str(icd or "").strip():
        dkat2 = str(row.get("DKAT2") or "").strip()
        sys2 = DIA_KATALOG_SYSTEM.get(dkat2, system)
        c2 = {"system": sys2, "code": row.get("DKEY2")}
        disp2 = (kt.get(f"{dkat2}|{dkey2}") or "").strip()
        if disp2:
            c2["display"] = disp2
        coding.append(c2)
    text = (row.get("DITXT") or row.get("ALTERN_DIATXT")
            or (coding[0].get("display") if coding else None))
    res = {
        "resourceType": "Condition",
        "id": _ids.rid(ns, "Condition", mandt, einri, falnr, lfdnr),
        "code": {"coding": coding, "text": priv.text(None, text) if priv else text},
        "encounter": {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)},
        "recordedDate": row.get("DIADT"),
        "meta": {"source": "sapfhir/NDIA"},
    }
    kats = _dia_kategorien(row)
    if kats:
        res["category"] = kats
    # Diagnosesicherheit — verifiziert Runde 4: NICHT in DIASI (im Haus leer), sondern
    # in DIAGW (Datenelement N2_DIASI, Katalog TN26C). Live-Werte: G=gesichert,
    # V=Verdacht, A=ausgeschlossen, Z=Zustand nach. Fallback DIASI fuer Fremdsysteme.
    sicherheit = str(row.get("DIAGW") or row.get("DIASI") or "").strip()
    if sicherheit:
        # Deutsche ICD-10-GM-Diagnosesicherheit (Rohcode A/V/G/Z)
        res.setdefault("extension", []).append({
            "url": "https://fhir.de/StructureDefinition/icd-10-gm-diagnosesicherheit",
            "valueCode": sicherheit})
        # FHIR-Semantik: G/V/A -> verificationStatus; Z (Zustand nach) -> clinicalStatus
        _VS = {"G": "confirmed", "V": "provisional", "A": "refuted"}
        if sicherheit in _VS:
            res["verificationStatus"] = {"coding": [{
                "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status",
                "code": _VS[sicherheit]}]}
        elif sicherheit == "Z":
            res["clinicalStatus"] = {"coding": [{
                "system": "http://terminology.hl7.org/CodeSystem/condition-clinical",
                "code": "resolved"}]}
    if str(row.get("STORN") or "").strip() not in ("", "0"):
        res["verificationStatus"] = {"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/condition-ver-status",
            "code": "entered-in-error"}]}
    return res


# N1LSTEAM.VORGANG — OP-Team-Funktionscodes (R15, Deutung aus Livewerten; Katalog nicht
# repliziert -> Rohcode bleibt fuehrend, Display nur fuer eindeutige Standardcodes).
OP_VORGANG = {
    "OPT1": "Operateur", "OPT2": "2. Operateur",
    "ASS1": "1. Assistenz", "ASS2": "2. Assistenz", "ASS3": "3. Assistenz", "ASS4": "4. Assistenz",
    "INS1": "Instrumentanz", "SPR1": "Springer",
    "ANA1": "Anaesthesist", "ANA2": "Anaesthesist", "ANA3": "Anaesthesist", "ANA4": "Anaesthesist",
    "ANS1": "Anaesthesiepflege", "ANS2": "Anaesthesiepflege",
    "ANS3": "Anaesthesiepflege", "ANS4": "Anaesthesiepflege",
    "HEB": "Hebamme", "GAST": "Gast",
}


def _performers_team(team, ns, mandt):
    """N1LSTEAM-Zeilen -> Procedure.performer[] (INDIVIDUELLE Personen). Verifiziert R14/R15:
    PK-Grain [MANDT,LNRLS,VRGNR,GPART]; VORGANG=Funktion im Eingriff (Live: OPT1/ASS*/ANA*/
    ANS*/INS1/SPR1/HEB/GAST, STATUS 'F'=fixiert/' '), GPART=Person im GEMEINSAMEN
    Practitioner-Schema (R13: GPART==PERNR), BEGDT/BEGZT..ENDDT/ENDZT=Einsatzzeit."""
    out = []
    for t in (team or []):
        gpart = str(t.get("GPART") or "").strip()
        if not gpart or gpart == "0000000000":
            continue
        perf = {"actor": {"reference": "Practitioner/" + _ids.rid(
            ns, "Practitioner", mandt, gpart)}}
        vorgang = str(t.get("VORGANG") or "").strip()
        fn = _cc("urn:ish:op-vorgang", vorgang, OP_VORGANG.get(vorgang))
        if fn:
            perf["function"] = fn
        out.append(perf)
    return out


def map_procedure(row: dict, ns, priv=None, patnr: str | None = None,
                  team: list | None = None) -> dict:
    """NICP -> Procedure. Verifiziert R8 (sapdatasheet), alle Schluesselpfade nachvollzogen:
    PK [MANDT, LNRIC] (LNRIC = ISH_LNRIC, global eindeutige OPS-Lfd.Nr.). LFDBEW ist NICHT
    Teil des PK, sondern FK -> NBEW (Bewegungsbezug: welche Prozedur in welcher Bewegung).
    OPS-Kode ICPML (ICPM_LS), Katalog-ID ICPMK (ICPM_ID, '36'=OPS) FK->TNK01, Klartext BTEXT.
    OP-Zeitraum BGDOP/BZTOP..ENDOP/EZTOP. OE ORGFA=ISH_FACHOE_PROC (fachlich, ->NORG, traegt
    den Performer), ORGPF=ISH_ERBOE_PROC (erbringend/pflegerisch, ->NORG). Lokalisation
    LSLOK=ISH_PROC_LOC FK->TN26E (-> bodySite). OP-Art OPART FK->TN14O (-> category).
    FALNR/EINRI denormalisiert vorhanden (FK->NFAL/TN01), PATNR NICHT -> `patnr` als Kontext
    (Pipeline loest FALNR->NFAL->PATNR), sonst faellt subject auf den Encounter zurueck."""
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    falnr = row.get("FALNR"); lnric = row.get("LNRIC")
    ops = row.get("ICPML")
    system = OPS_KATALOG_SYSTEM.get(str(row.get("ICPMK") or "").strip(),
                                    "http://fhir.de/CodeSystem/bfarm/ops")
    enc_ref = "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)
    # FHIR Procedure.subject MUSS Patient sein; NICP traegt kein PATNR -> Pipeline-Kontext.
    subject = ({"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, patnr)}
               if patnr else {"reference": enc_ref})   # Fallback bis PATNR gejoint ist
    res = {
        "resourceType": "Procedure",
        "id": _ids.rid(ns, "Procedure", mandt, lnric),
        "status": "completed",
        "code": {"coding": [{"system": system, "code": ops}] if ops else [],
                 "text": row.get("BTEXT")},
        "subject": subject,
        "encounter": {"reference": enc_ref},
        "meta": {"source": "sapfhir/NICP"},
    }
    # OP-Zeitraum mit Uhrzeit (BGDOP+BZTOP .. ENDOP+EZTOP)
    start = _dt(row.get("BGDOP"), row.get("BZTOP"))
    if start:
        end = _dt(row.get("ENDOP"), row.get("EZTOP")) or start
        res["performedPeriod"] = {"start": start, "end": end}
    # Performer = fachliche OE ORGFA -> Organization(NORG); ORGPF (erbringend) falls abweichend
    dept = _norg_ref(ns, mandt, row.get("ORGFA"))
    if dept:
        res["performer"] = [{"actor": {"reference": dept}}]
    erb = _norg_ref(ns, mandt, row.get("ORGPF"))
    if erb and erb != dept:
        res.setdefault("performer", []).append(
            {"function": {"text": "erbringende OE"}, "actor": {"reference": erb}})
    # R15: INDIVIDUELLES OP-Team (N1LSTEAM via LNRLS) zusaetzlich zur OE
    for perf in _performers_team(team, ns, mandt):
        res.setdefault("performer", []).append(perf)
    # Lokalisation LSLOK -> TN26E (bodySite)
    loc = _cc("urn:ish:tn26e", row.get("LSLOK"))
    if loc:
        res["bodySite"] = [loc]
    # OP-Art OPART -> TN14O (category)
    cat = _cc("urn:ish:tn14o", row.get("OPART"))
    if cat:
        res["category"] = cat
    if str(row.get("STORN") or "").strip() not in ("", "0"):
        res["status"] = "entered-in-error"
    return res


# --- Labor: flexible Parser (verifiziert R6 gegen N2LABOR/N2LABOR001) -------
# N2VALUE ist Freitext (kein garantierter Werttyp: N2VALUETYP war leer). Werte kommen
# als '2.0', '2,5', '<0,05', '> 10', 'positiv', 'n.n.' -> robust erkennen.
LAB_STATUS = {   # N2VSTATUS/N2STATUS bzw. N2LASTATUS -> observation/report-status  # VERIFY Enum
    "F": "final", "E": "final", "G": "final",
    "P": "preliminary", "V": "preliminary",
    "C": "corrected", "K": "corrected",
    "S": "cancelled", "X": "cancelled",
}
_COMP = {"<": "<", "<=": "<=", "≤": "<=", ">": ">", ">=": ">=", "≥": ">="}
_INTERP = {"H": "H", "HH": "HH", "L": "L", "LL": "LL", "N": "N", "A": "A",
           "+": "H", "++": "HH", "-": "L", "--": "LL", "*": "A"}
_V3INTERP = "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation"


def _to_float(s):
    """Robuste Zahlerkennung: de/en-Dezimaltrenner, Tausendertrennung, Vorzeichen."""
    if s is None:
        return None
    t = str(s).strip().replace(" ", "").replace(" ", "")
    if not t:
        return None
    if "," in t and "." in t:            # gemischt -> letzter Trenner = Dezimal
        t = (t.replace(".", "").replace(",", ".") if t.rfind(",") > t.rfind(".")
             else t.replace(",", ""))
    elif "," in t:                       # nur Komma -> Dezimalkomma
        t = t.replace(",", ".")
    if not re.fullmatch(r"[+-]?\d*\.?\d+", t):
        return None
    try:
        return float(t)
    except ValueError:
        return None


def _dt(d, t=None):
    """Datum (+optional Zeit) -> ISO. Akzeptiert date/datetime/str beliebiger Herkunft."""
    if not d:
        return None
    ds = str(d)[:10]
    if t:
        ts = str(t)
        if len(ts) >= 5 and ts[:5] not in ("00:00",):
            return f"{ds}T{ts[:8]}"
    return ds


def _parse_value(raw, unit):
    """N2VALUE -> FHIR value[x]. Zahl (opt. Komparator) -> valueQuantity, sonst valueString."""
    if raw is None or str(raw).strip() == "":
        return {}
    s = str(raw).strip()
    comp, body = None, s
    m = re.match(r"^(<=|>=|≤|≥|<|>)\s*(.+)$", s)
    if m:
        comp, body = _COMP.get(m.group(1)), m.group(2).strip()
    num = _to_float(body)
    if num is not None:
        q = {"value": num}
        u = (unit or "").strip()
        if u:
            q["unit"] = u
        if comp:
            q["comparator"] = comp
        return {"valueQuantity": q}
    return {"valueString": s}


def _parse_range(raw):
    """N2NORMAL -> FHIR referenceRange. Intervall 'a-b'/'a bis b', Grenzen '<b'/'>a'/'bis b'/
    'ab a', Komma-Dezimal, Einheit-Anhang; nicht parsebar -> {'text': raw}."""
    if raw is None or str(raw).strip() == "":
        return None
    s = str(raw).strip()
    m = re.match(r"^([+-]?[\d.,]+)\s*(?:-|–|—|\.\.|bis)\s*([+-]?[\d.,]+)", s, re.I)
    if m:
        lo, hi = _to_float(m.group(1)), _to_float(m.group(2))
        rr = {}
        if lo is not None:
            rr["low"] = {"value": lo}
        if hi is not None:
            rr["high"] = {"value": hi}
        if rr:
            return rr
    m = re.match(r"^(?:<=?|≤|bis)\s*([+-]?[\d.,]+)", s, re.I)
    if m and _to_float(m.group(1)) is not None:
        return {"high": {"value": _to_float(m.group(1))}}
    m = re.match(r"^(?:>=?|≥|ab)\s*([+-]?[\d.,]+)", s, re.I)
    if m and _to_float(m.group(1)) is not None:
        return {"low": {"value": _to_float(m.group(1))}}
    return {"text": s}


def _interpretation(abn, vq, rr):
    """N2ABNORMAL bevorzugt; sonst aus Wert+Referenzbereich abgeleitet (Haus flaggt
    nicht zuverlaessig, s. R6-Stichprobe)."""
    code = None
    a = (abn or "").strip()
    if a:
        code = _INTERP.get(a.upper())
        if code is None:
            return {"text": a}          # unbekanntes Flag als Rohtext behalten
    elif vq and rr and "value" in vq and "text" not in rr:
        v = vq["value"]
        lo = (rr.get("low") or {}).get("value")
        hi = (rr.get("high") or {}).get("value")
        if hi is not None and v > hi:
            code = "H"
        elif lo is not None and v < lo:
            code = "L"
        elif lo is not None or hi is not None:
            code = "N"
    return {"coding": [{"system": _V3INTERP, "code": code}]} if code else None


def map_observation_labor(row: dict, ns, priv=None, header: dict | None = None,
                          loinc: dict | None = None) -> dict:
    """N2LABOR001 (Wertzeile) -> Observation(laboratory). `header` = zugehoerige
    N2LABOR-Kopfzeile fuer subject/encounter/Befunddatum (client-seitig ueber
    DOKAR/DOKNR/DOKVR/DOKTL gemergt — NICHT serverseitig auf 322 Mio. joinen)."""
    h = header or {}
    mandt = row.get("MANDT")
    dokar = row.get("DOKAR"); doknr = row.get("DOKNR")
    dokvr = row.get("DOKVR"); doktl = row.get("DOKTL"); museq = row.get("MUSEQ")
    code_local = (row.get("N2LEISTID") or "").strip()
    coding = []
    if loinc and code_local in loinc:
        coding.append({"system": "http://loinc.org", "code": loinc[code_local]})
    if code_local:
        coding.append({"system": "urn:ish:leistid", "code": code_local})
    res = {
        "resourceType": "Observation",
        "id": _ids.rid(ns, "ObsLab", mandt, dokar, doknr, dokvr, doktl, museq),
        "status": LAB_STATUS.get(
            str(row.get("N2VSTATUS") or row.get("N2STATUS") or "").strip().upper(), "final"),
        "category": [{"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/observation-category",
            "code": "laboratory"}]}],
        "code": {"coding": coding, "text": (row.get("N2KATTEXT") or "").strip() or code_local or None},
        "partOf": [{"reference": "DiagnosticReport/" + _ids.rid(
            ns, "DiagReportLab", mandt, dokar, doknr, dokvr, doktl)}],
        "meta": {"source": "sapfhir/N2LABOR001"},
    }
    pat = h.get("N2LAPATNR"); fal = h.get("N2LAFALNR"); einri = h.get("N2LAEINRI")
    if pat:
        res["subject"] = {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, pat)}
    if fal:
        res["encounter"] = {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, fal)}
    dt = _dt(row.get("N2DATE"), row.get("N2TIME")) or _dt(h.get("N2LADATUM"), h.get("N2LATIME"))
    if dt:
        res["effectiveDateTime"] = dt
    res.update(_parse_value(row.get("N2VALUE"), row.get("N2UNIT")))
    rr = _parse_range(row.get("N2NORMAL"))
    if rr:
        res["referenceRange"] = [rr]
    interp = _interpretation(row.get("N2ABNORMAL"), res.get("valueQuantity"), rr)
    if interp:
        res["interpretation"] = [interp]
    return res


def map_diagnosticreport_labor(row: dict, ns, priv=None, value_rows: list | None = None) -> dict:
    """N2LABOR (Kopf) -> DiagnosticReport(laboratory). `value_rows` (N2LABOR001) optional
    -> result[]-Referenzen auf die Observations."""
    mandt = row.get("MANDT"); einri = row.get("N2LAEINRI")
    pat = row.get("N2LAPATNR"); fal = row.get("N2LAFALNR")
    dokar = row.get("DOKAR"); doknr = row.get("DOKNR")
    dokvr = row.get("DOKVR"); doktl = row.get("DOKTL")
    res = {
        "resourceType": "DiagnosticReport",
        "id": _ids.rid(ns, "DiagReportLab", mandt, dokar, doknr, dokvr, doktl),
        "status": LAB_STATUS.get(str(row.get("N2LASTATUS") or "").strip().upper(), "final"),
        "category": [{"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/v2-0074", "code": "LAB"}]}],
        "code": {"text": (row.get("N2KATTEXT") or "").strip() or "Laborbefund"},
        "meta": {"source": "sapfhir/N2LABOR"},
    }
    if pat:
        res["subject"] = {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, pat)}
    if fal:
        res["encounter"] = {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, fal)}
    dt = _dt(row.get("N2LADATUM"), row.get("N2LATIME"))
    if dt:
        res["effectiveDateTime"] = dt
        res["issued"] = dt
    if value_rows:
        res["result"] = [{"reference": "Observation/" + _ids.rid(
            ns, "ObsLab", mandt, v.get("DOKAR"), v.get("DOKNR"), v.get("DOKVR"),
            v.get("DOKTL"), v.get("MUSEQ"))} for v in value_rows]
    return res


def map_document_reference(row: dict, ns, priv=None) -> dict:
    """NDOC -> DocumentReference. Verifiziert R8 (sapdatasheet + replicate): NDOC ist die
    ZUORDNUNG IS-H-Objekt <-> DVS-Dokument, NICHT der Textinhalt. KORREKTUR R8: die frueheren
    Feldnamen (DOCID/DOCKA/DOCDT/DOCTX) existieren NICHT.
    PK [MANDT, DOKAR, DOKNR, DOKVR, DOKTL, LFDDOK] (DVS-Dokumentschluessel + Lfd.Nr.).
    Bezug: PATNR->NPAT, FALNR->NFAL, LFDBEW->NBEW (Bewegung), EINRI->TN01. Kategorie
    DTID->N2DT, MEDOK=medizinisches Dokument. Autor: MITARB (N1MITARB)->NGPA (Practitioner),
    dokumentierende OE ORGDO->NORG. Dokumentdatum DODAT/DOTIM. STORN=Storno, LOEKZ=Loesch.
    Volltext bewusst NICHT hier -> N2TEXT.TXT (DuckDB-FTS, doc_search)."""
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    dokar = row.get("DOKAR"); doknr = row.get("DOKNR")
    dokvr = row.get("DOKVR"); doktl = row.get("DOKTL"); lfddok = row.get("LFDDOK")
    res = {
        "resourceType": "DocumentReference",
        "id": _ids.rid(ns, "DocRef", mandt, dokar, doknr, dokvr, doktl, lfddok),
        "status": "current",
        "masterIdentifier": {"system": "urn:ish:dms-dokid",
                             "value": f"{dokar}-{doknr}-{dokvr}-{doktl}"},
        "meta": {"source": "sapfhir/NDOC"},
    }
    typ = _cc("urn:ish:n2dt", row.get("DTID"))
    if typ:
        res["type"] = typ
    if str(row.get("MEDOK") or "").strip().upper() == "X":
        res["category"] = [{"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/document-category",
            "code": "clinical-note"}], "text": "medizinisches Dokument"}]
    pat = str(row.get("PATNR") or "").strip()
    if pat and pat != "0000000000":
        res["subject"] = {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, pat)}
    fal = str(row.get("FALNR") or "").strip()
    if fal:
        res["context"] = {"encounter": [{"reference": "Encounter/" + _ids.rid(
            ns, "Encounter", mandt, einri, fal)}]}
    dt = _dt(row.get("DODAT"), row.get("DOTIM"))
    if dt:
        res["date"] = dt
    author = []
    mitarb = str(row.get("MITARB") or "").strip()
    if mitarb and mitarb != "0000000000":
        author.append({"reference": "Practitioner/" + _ids.rid(
            ns, "Practitioner", mandt, mitarb)})
    orgdo = _norg_ref(ns, mandt, row.get("ORGDO"))
    if orgdo:
        author.append({"reference": orgdo})
    if author:
        res["author"] = author
    if str(row.get("STORN") or "").strip() not in ("", "0") or \
       str(row.get("LOEKZ") or "").strip().upper() == "X":
        res["status"] = "entered-in-error"
    return res


def map_coverage(row: dict, ns, priv=None, vvp: dict | None = None) -> dict:
    """NKSK -> Coverage (verifiziert Runde 2). Kostenuebernahme je Fall.
    `vvp` (optional, R15): passende NVVP-Zeile des Patienten (gleicher KOSTR) —
    verifiziert R14 gegen replicate (NVVP: 475k, davon 295k mit VERNR=Versichertennummer).
    VERNR ist KVNR-Kandidat -> IMMER ueber priv.hash_id de-identifizieren, wenn priv aktiv;
    nur im Klarbetrieb roh. MGART/UNTGR (Mitglieds-/Untergruppe) als Rohcode-Extension."""
    mandt = row.get("MANDT"); belnr = row.get("BELNR")
    einri = row.get("EINRI"); falnr = row.get("FALNR"); kostr = row.get("KOSTR")
    res = {
        "resourceType": "Coverage",
        "id": _ids.rid(ns, "Coverage", mandt, belnr),
        "status": "cancelled" if str(row.get("STORN") or "").strip() not in ("", "0")
                  else "active",
        "beneficiary": {"reference": "Encounter/" + _ids.rid(
            ns, "Encounter", mandt, einri, falnr)},
        "payor": [{"reference": "Organization/" + _ids.rid(ns, "OrgKostr", mandt, kostr)}],
        "period": {k: v for k, v in (("start", _echtes_datum(row.get("BEGDT"))),
                                     ("end", _echtes_datum(row.get("ENDDT")))) if v},
        "type": {"text": (row.get("KSTYP") or "").strip() or None},
        "meta": {"source": "sapfhir/NKSK"},
    }
    if str(kostr or "").strip() == "0009999999":
        res["type"] = {"text": "Selbstzahler"}
    # NVVP-Anreicherung (R15): Versichertennummer + Mitgliedsart
    if vvp:
        vernr = (vvp.get("VERNR") or "").strip()
        if vernr:
            if priv is not None and getattr(priv, "mode", "off") != "off":
                res["subscriberId"] = priv.hash_id(vernr, "kvnr")
            else:
                res["subscriberId"] = vernr
        mg = _cc("urn:ish:mgart", vvp.get("MGART"))
        if mg:
            res.setdefault("extension", []).append(
                {"url": "urn:ish:mgart", "valueCodeableConcept": mg})
    return res


def map_geburt(row: dict, ns, priv=None) -> list:
    """NGEB -> Observation(s) (verifiziert Runde 2). Perinataldaten Neugeborenes.
    Liefert eine Liste (Gewicht, Laenge, Kopfumfang), verknuepft ueber Kind-Fall."""
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    faln1 = row.get("FALN1"); lfdnr = row.get("LFDNR")
    enc = "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, faln1)
    born = row.get("GBDAT")
    out = []
    def obs(kind, loinc, value, unit):
        if value in (None, "", 0):
            return
        out.append({
            "resourceType": "Observation",
            "id": _ids.rid(ns, "ObsGeb", mandt, einri, faln1, lfdnr, kind),
            "status": "final",
            "category": [{"coding": [{
                "system": "http://terminology.hl7.org/CodeSystem/observation-category",
                "code": "vital-signs"}]}],
            "code": {"coding": [{"system": "http://loinc.org", "code": loinc}],
                     "text": kind},
            "encounter": {"reference": enc},
            "effectiveDateTime": born,
            "valueQuantity": {"value": value, "unit": unit},
            "meta": {"source": "sapfhir/NGEB"},
        })
    obs("Geburtsgewicht", "8339-4", row.get("GBGEW"), "g")
    obs("Geburtslaenge", "8305-5", row.get("GBGRO"), "cm")
    obs("Kopfumfang", "8287-5", row.get("HEAD_SIZE"), "cm")
    return out


def map_location_bau(row: dict, ns, priv=None, adr: dict | None = None,
                     struktur: dict | None = None, hierarchie: dict | None = None) -> dict:
    """NBAU -> Location. Verifiziert R8 (sapdatasheet + replicate): PK [MANDT, BAUID] (8-st.).
    KORREKTUR R8: XKOOR/YKOOR sind NICHT geografisch! Datenelemente RI_XKOOR/RI_YKOOR
    (Domaene KOOR3, replicate: nvarchar(3)) = X/Y-Position in der Uebersichtsgrafik (Lageplan
    000-999, mit BREIT/LAENG). KEINE WGS84-Koordinate -> NICHT nach position. Echte Geo/Adresse
    via ADRNR+ADROB='NBAU' -> NADR (adr-Join). BAUTY FK->TN11B (Gebaeudekategorie), BAUNA=Name,
    BKURZ=Kennung, BAUKB=Kurztext. Ziel von NBEW.ZIMMR (Raum, ISH_ZIMMID)/BETT (Bett, BETTID)
    -> BAUID (FK NBEW.BETT->NBAU verifiziert).
    STRUKTUR (verifiziert R8 gegen replicate):
    - `hierarchie` = TN11H-Zeile dieses Bauobjekts (UNTBE=diese BAUID -> UEBBE=uebergeordnet;
      je Kind genau EIN Elternteil, 1832/1832) -> Location.partOf = Location(NBAU, UEBBE)
      (physische Baumkette Bett->Zimmer->...). UNTBT/UEBBT = Kategorie (->TN11B).
    - `struktur` = NPOB-/TN11O-Zeile (Ort<->OE) -> managingOrganization = Organization(NORG, ORGID)."""
    mandt = row.get("MANDT"); bauid = row.get("BAUID")
    res = {
        "resourceType": "Location",
        "id": _ids.rid(ns, "LocationBau", mandt, bauid),
        "status": "active" if str(row.get("LOEKZ") or "").strip().upper() != "X" else "inactive",
        "name": (row.get("BAUNA") or "").strip() or None,
        "physicalType": _cc("urn:ish:tn11b", row.get("BAUTY")) or {"text": "Gebaeude"},
        "meta": {"source": "sapfhir/NBAU"},
    }
    bkurz = (row.get("BKURZ") or "").strip()
    if bkurz:
        res["alias"] = [bkurz]
    if (row.get("TELNR") or "").strip():
        res["telecom"] = [{"system": "phone", "value": row.get("TELNR").strip()}]
    # Adresse/Geo NUR aus NADR (ADRNR+ADROB='NBAU'); XKOOR/YKOOR sind Lageplan-Koords.
    src = adr or {}
    if src.get("STRAS") or src.get("ORT"):
        res["address"] = {
            "line": [src.get("STRAS")] if src.get("STRAS") else [],
            "city": src.get("ORT"), "postalCode": src.get("PSTLZ"),
            "country": src.get("LAND"),
        }
    # Verwaltende OE aus NPOB-/TN11O-Struktur (ORGID -> NORG), verifiziert R8 gegen replicate
    mng = _norg_ref(ns, mandt, (struktur or {}).get("ORGID"))
    if mng:
        res["managingOrganization"] = {"reference": mng}
    # Physische Baumkette: uebergeordnete Baueinheit TN11H.UEBBE -> Location.partOf
    ueb = str((hierarchie or {}).get("UEBBE") or "").strip()
    if ueb and ueb not in ("00000000", "0"):
        res["partOf"] = {"reference": "Location/" + _ids.rid(ns, "LocationBau", mandt, ueb)}
    return res


# --- Medikation: N1MEORDER -> MedicationRequest (verifiziert R5) ------------
def map_medicationrequest(row: dict, ns, priv=None) -> dict:
    mandt = row.get("MANDT"); meordid = row.get("MEORDID")
    pid = row.get("PATNR"); fal = row.get("FALNR"); einri = row.get("EINRI")
    storn = str(row.get("STORN") or "").strip() not in ("", "0")
    med = {"text": (row.get("MOTX") or row.get("MOSTX") or "").strip() or None}
    drug = (row.get("EXT_DRUGID") or "").strip()
    if drug:
        # PZN wenn rein numerisch, sonst hauseigene Arzneimittel-ID  # VERIFY Codesystem
        sysd = "http://fhir.de/CodeSystem/ifa/pzn" if drug.isdigit() else "urn:ish:drugid"
        med["coding"] = [{"system": sysd, "code": drug}]
    res = {
        "resourceType": "MedicationRequest",
        "id": _ids.rid(ns, "MedReq", mandt, meordid),
        "status": "entered-in-error" if storn else "active",
        "intent": "order",
        "medicationCodeableConcept": med,
        "subject": {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, pid)},
        "meta": {"source": "sapfhir/N1MEORDER"},
    }
    if fal:
        res["encounter"] = {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, fal)}
    authored = _dt(row.get("ERDAT"), row.get("ERTIM"))
    if authored:
        res["authoredOn"] = authored
    dose = {}
    if (row.get("DOSDEF") or "").strip():
        dose["text"] = row.get("DOSDEF").strip()
    if (row.get("APROU") or "").strip():
        dose["route"] = {"text": row.get("APROU").strip()}   # VERIFY: Route-Code -> Katalog
    if dose:
        res["dosageInstruction"] = [dose]
    disp = {}
    qty = _to_float(row.get("DISPQUAN"))
    if qty is not None:
        disp["quantity"] = {"value": qty, "unit": (row.get("DISPQUANU") or "").strip() or None}
    start = _dt(row.get("MOVDF"), row.get("MOVTF")); end = _dt(row.get("MOVDT"), row.get("MOVTT"))
    if start or end:
        disp["validityPeriod"] = {k: v for k, v in (("start", start), ("end", end)) if v}
    if disp:
        res["dispenseRequest"] = disp
    aut = str(row.get("AUTIDEM") or "").strip().upper()
    if aut:
        res["substitution"] = {"allowedBoolean": aut != "X"}  # VERIFY: X = aut idem (keine Substitution)
    return res


# --- Risikofaktoren/Allergien: NRSF -> AllergyIntolerance | Flag ------------
# Kuratierte, VOLLSTAENDIGE RSFNR-Klassifikation (R6, aus TN39T 56 Eintraege).
# SOLLTE nach config/rsf_fhir_map.csv ausgelagert werden (cdc:full, 56 Codes, stabil).
RSF_ALLERGY = {   # RSFNR -> AllergyIntolerance.category (None = ohne Kategorie)
    "000001": "medication", "000002": "medication", "000003": "medication",
    "000004": "medication", "000005": "medication", "000006": "medication",
    "000007": "biologic",   "000008": "medication", "000009": "medication",
    "000010": "medication", "000011": "medication", "000012": "medication",
    "000013": "medication", "000014": "medication", "000015": "environment",
    "000016": None,         "000022": None,         "000023": "environment",
}
RSF_INFECTION = {  # RSFNR -> Flag(safety): MRE / Infektion / Isolation
    "000000", "000017", "000019", "000020", "000021", "000024", "000025",
    "000026", "000029", "000030", "000031", "000034", "000035", "000036",
    "000039", "000041", "000043", "000045", "000053",
}
_INF_KW = re.compile(r"mrsa|mrgn|vre|carbapenem|imipenem|metallobetalakt|pseudomonas|"
                     r"klebsiella|enterokokken|sars|infekt|leukozidin|isolation", re.I)
_ALG_KW = re.compile(r"allerg|penicill|antibiot|kontrastmittel|latex|\bjod\b|arzneimittel|"
                     r"barbiturat|procain|tetracyclin|neomycin|streptomycin", re.I)


def _rsf_class(rsfnr, text):
    """allergy | infection | admin — kuratiert, Fallback per Keyword (fuer neue Codes)."""
    if rsfnr in RSF_ALLERGY:
        return "allergy"
    if rsfnr in RSF_INFECTION:
        return "infection"
    t = text or ""
    if _INF_KW.search(t):
        return "infection"
    if _ALG_KW.search(t):
        return "allergy"
    return "admin"


def map_risikofaktor(row: dict, ns, priv=None, catalog: dict | None = None):
    """NRSF -> AllergyIntolerance (echte Allergie) ODER Flag (MRE/Isolation=safety,
    Administratives=admin). NRSF ist gemischt -> Routing verhindert, dass z.B. MRSA
    faelschlich als Allergie kodiert wird. `catalog` = optionales RSFNR->Text (TN39T)."""
    mandt = row.get("MANDT"); pid = row.get("PATNR")
    rsfnr = (row.get("RSFNR") or "").strip(); lfdnr = row.get("LFDNR")
    cat_text = (catalog or {}).get(rsfnr)
    text = (row.get("KZTXT") or "").strip() or cat_text or rsfnr
    klass = _rsf_class(rsfnr, cat_text or row.get("KZTXT"))
    geloescht = str(row.get("LOEKZ") or "").strip().upper() == "X"
    aktiv = (not geloescht) and str(row.get("EXIST") or "").strip().upper() != "N"
    subj = {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, pid)}
    code = {"coding": [{"system": "urn:ish:rsfnr", "code": rsfnr}], "text": text}
    recorded = _dt(row.get("ERDAT"), row.get("ERTIM"))

    if klass == "allergy":
        res = {
            "resourceType": "AllergyIntolerance",
            "id": _ids.rid(ns, "Allergy", mandt, pid, rsfnr, lfdnr),
            "clinicalStatus": {"coding": [{
                "system": "http://terminology.hl7.org/CodeSystem/allergyintolerance-clinical",
                "code": "active" if aktiv else "inactive"}]},
            "patient": subj,
            "code": code,
            "meta": {"source": "sapfhir/NRSF"},
        }
        acat = RSF_ALLERGY.get(rsfnr)
        if acat:
            res["category"] = [acat]
        if recorded:
            res["recordedDate"] = recorded
        return res

    # infection / admin -> Flag (kein Datenverlust, aber FHIR-korrekt getrennt)
    return {
        "resourceType": "Flag",
        "id": _ids.rid(ns, "Flag", mandt, pid, rsfnr, lfdnr),
        "status": "active" if aktiv else "inactive",
        "category": [{"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/flag-category",
            "code": "safety" if klass == "infection" else "admin"}]}],
        "code": code,
        "subject": subj,
        "meta": {"source": "sapfhir/NRSF"},
        **({"period": {"start": recorded}} if recorded else {}),
    }


# --- Organization: Kostentraeger (NKTR) + Einrichtung (TN01) ---------------
def map_organization_kostentraeger(row: dict, ns, priv=None) -> dict:
    """NKTR -> Organization(payer). ID-Schema 'OrgKostr' == map_coverage.payor-Referenz."""
    mandt = row.get("MANDT"); kostr = row.get("KOSTR")
    res = {
        "resourceType": "Organization",
        "id": _ids.rid(ns, "OrgKostr", mandt, kostr),
        "active": str(row.get("LOEKZ") or "").strip().upper() != "X",
        "type": [{"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/organization-type", "code": "pay"}]}],
        "name": (row.get("KSSNM") or "").strip() or (row.get("KZTXT") or "").strip() or None,
        "meta": {"source": "sapfhir/NKTR"},
    }
    ident = []
    ik = (row.get("PM301") or "").strip()      # IK der Kasse (fuer §301)
    if ik:
        ident.append({"system": "http://fhir.de/sid/arge-ik/iknr", "value": ik})
    if kostr:
        ident.append({"system": "urn:ish:kostr", "value": kostr})
    if ident:
        res["identifier"] = ident
    return res


def map_organization_einrichtung(row: dict, ns, priv=None) -> dict:
    """TN01 -> Organization (Einrichtung/Krankenhaus). EINBZ=Name, INSTNR=IK."""
    mandt = row.get("MANDT"); einri = row.get("EINRI")
    res = {
        "resourceType": "Organization",
        "id": _ids.rid(ns, "OrgEinri", mandt, einri),
        "active": True,
        "name": (row.get("EINBZ") or "").strip() or (row.get("EINKB") or "").strip() or None,
        "meta": {"source": "sapfhir/TN01"},
    }
    ident = []
    ik = (row.get("INSTNR") or "").strip()
    if ik:
        ident.append({"system": "http://fhir.de/sid/arge-ik/iknr", "value": ik})
    if einri:
        ident.append({"system": "urn:ish:einri", "value": einri})
    if ident:
        res["identifier"] = ident
    addr = {}
    if (row.get("STRAS") or "").strip():
        addr["line"] = [row.get("STRAS").strip()]
    if (row.get("ORT") or "").strip():
        addr["city"] = row.get("ORT").strip()
    if (row.get("PSTLZ") or "").strip():
        addr["postalCode"] = row.get("PSTLZ").strip()
    if (row.get("LAND") or "").strip():
        addr["country"] = row.get("LAND").strip()
    if addr:
        res["address"] = [addr]
    if (row.get("TELF1") or "").strip():
        res["telecom"] = [{"system": "phone", "value": row.get("TELF1").strip()}]
    return res


# --- Practitioner: NGPA (Rolle PERS='X') -----------------------------------
def map_practitioner(row: dict, ns, priv=None) -> dict:
    """NGPA -> Practitioner. PK GPART (verifiziert R7). Ziel von NPAT.HARNR/EARNR/UARNR
    und NDIA.DIAPE. NGPA-als-Organization (KRKHS/KOSTR) separat (NKTR deckt Kassen)."""
    mandt = row.get("MANDT"); gpart = row.get("GPART")
    res = {
        "resourceType": "Practitioner",
        "id": _ids.rid(ns, "Practitioner", mandt, gpart),
        "active": str(row.get("LOEKZ") or "").strip().upper() != "X",
        "identifier": [{"system": "urn:ish:gpart", "value": gpart}],
        "gender": {"1": "male", "2": "female", "3": "unknown"}.get(
            str(row.get("GSCHL") or "").strip(), "unknown"),
        "meta": {"source": "sapfhir/NGPA"},
    }
    ik = (row.get("INSTN") or "").strip()
    if ik:
        res["identifier"].append({"system": "http://fhir.de/sid/arge-ik/iknr", "value": ik})
    if priv is None or priv.mode == "off":
        nn = (row.get("NAME1") or "").strip(); vn = (row.get("NAME2") or "").strip()
        if nn or vn:
            name = {"family": nn, "given": [vn] if vn else []}
            if (row.get("TITEL") or "").strip():
                name["prefix"] = [row.get("TITEL").strip()]
            res["name"] = [name]
    return res


# --- Practitioner: NPER (IS-H-Personal, Ziel von NFPZ.PERNR) ---------------
def map_practitioner_nper(row: dict, ns, priv=None) -> dict:
    """NPER -> Practitioner (ANREICHERUNG). Verifiziert R12/R13 gegen replicate:
    PK [MANDT,PERNR] (KEIN EINRI), 236k Zeilen. BEFUND R13: NGPA.GPART == NPER.PERNR fuer
    ALLE 236.114 Personen (PERS='X') — NPER und NGPA beschreiben DIESELBE Person unter
    demselben Schluessel. Daher GEMEINSAMES ID-Schema 'Practitioner' (== map_practitioner/
    NGPA und == _participants_nfpz): eine Person = eine FHIR-Ressource. Die Pipeline mergt
    NGPA-Zeile (Name/Titel/IK) + NPER-Zeile (LANR/FACHR/Rollen) VOR der Ausleitung —
    dieser Mapper liefert den NPER-Anteil: PERNR (urn:ish:pernr), FIXLANR -> LANR
    (http://fhir.de/sid/kbv/lanr), FACHR->TNKFA als qualification, Rollen-Flags als
    Extension. KEINE Namensfelder in NPER (Name kommt aus NGPA bzw. HR/PA0002)."""
    mandt = row.get("MANDT"); pernr = str(row.get("PERNR") or "").strip()
    res = {
        "resourceType": "Practitioner",
        "id": _ids.rid(ns, "Practitioner", mandt, pernr),
        "active": str(row.get("LOEKZ") or "").strip().upper() != "X",
        "identifier": [{"system": "urn:ish:pernr", "value": pernr}],
        "meta": {"source": "sapfhir/NPER"},
    }
    lanr = (row.get("FIXLANR") or "").strip()
    if lanr:
        res["identifier"].append({"system": "http://fhir.de/sid/kbv/lanr", "value": lanr})
    fachr = _cc("urn:ish:tnkfa", row.get("FACHR"))
    if fachr:
        res["qualification"] = [{"code": fachr}]
    rollen = [f for f in ("ARZT", "PFLEG", "BARZT") if str(row.get(f) or "").strip() == "X"]
    if rollen:
        res["extension"] = [{"url": "urn:ish:nper-rolle", "valueCode": r.lower()}
                            for r in rollen]
    return res


# --- Organization: NC301P Datenannahmestellen (§301) ------------------------
def map_organization_das301(row: dict, ns, priv=None) -> dict:
    """NC301P -> Organization (Datenannahmestelle §301). Verifiziert R12 gegen replicate
    (123 Zeilen; DAS301=Schluessel, INSTNR=IK, NAME1/NAME2, Adresse, ANSPR/TELFN/TELFX).
    Ziel von NC301S.DAS301 (welche Meldung ging an welche Annahmestelle)."""
    mandt = row.get("MANDT"); das = str(row.get("DAS301") or "").strip()
    res = {
        "resourceType": "Organization",
        "id": _ids.rid(ns, "OrgDas301", mandt, das),
        "active": True,
        "type": [{"text": "Datenannahmestelle (§301)"}],
        "name": (row.get("NAME1") or "").strip() or None,
        "identifier": [{"system": "urn:ish:das301", "value": das}],
        "meta": {"source": "sapfhir/NC301P"},
    }
    n2 = (row.get("NAME2") or "").strip()
    if n2:
        res["alias"] = [n2]
    ik = (row.get("INSTNR") or "").strip()
    if ik:
        res["identifier"].append({"system": "http://fhir.de/sid/arge-ik/iknr", "value": ik})
    addr = {}
    if (row.get("STRAS") or "").strip():
        addr["line"] = [row.get("STRAS").strip()]
    if (row.get("ORT") or "").strip():
        addr["city"] = row.get("ORT").strip()
    if (row.get("PSTLZ") or "").strip():
        addr["postalCode"] = row.get("PSTLZ").strip()
    if (row.get("LAND") or "").strip():
        addr["country"] = row.get("LAND").strip()
    if addr:
        res["address"] = [addr]
    tel = []
    if (row.get("TELFN") or "").strip():
        tel.append({"system": "phone", "value": row.get("TELFN").strip()})
    if (row.get("TELFX") or "").strip():
        tel.append({"system": "fax", "value": row.get("TELFX").strip()})
    if tel:
        res["telecom"] = tel
    if (row.get("ANSPR") or "").strip():
        res["contact"] = [{"name": {"text": row.get("ANSPR").strip()}}]
    return res


# --- Organization: Organisationseinheit (NORG) -----------------------------
def map_organization_norg(row: dict, ns, priv=None) -> dict:
    """NORG -> Organization (Fachabteilung/Pflege-OE). PK [MANDT,ORGID] (verifiziert R7).
    Ziel von NBEW/NICP.ORGFA/ORGPF/ORGAU -> ORGID. ID-Schema 'OrgNorg' == _norg_ref."""
    mandt = row.get("MANDT"); orgid = str(row.get("ORGID") or "").strip()
    res = {
        "resourceType": "Organization",
        "id": _ids.rid(ns, "OrgNorg", mandt, orgid),
        "active": str(row.get("LOEKZ") or "").strip().upper() != "X",
        "type": [{"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/organization-type",
            "code": "dept"}]}],
        "name": (row.get("ORGNA") or "").strip() or (row.get("ORGKB") or "").strip() or None,
        "identifier": [{"system": "urn:ish:orgid", "value": orgid}],
        "meta": {"source": "sapfhir/NORG"},
    }
    okz = (row.get("OKURZ") or "").strip()
    if okz:
        res["alias"] = [okz]
    einri = str(row.get("EINRI") or "").strip()
    if einri:
        res["partOf"] = {"reference": "Organization/" + _ids.rid(ns, "OrgEinri", mandt, einri)}
    return res


# --- Account: NAPX/NAPX_FAL Fallzusammenfuehrung (Abrechnungsklammer) ------
def map_account_napx(kopf: dict, ns, priv=None, faelle: list | None = None,
                     patnr: str | None = None) -> dict:
    """NAPX (Kopf) + NAPX_FAL (Faelle) -> Account. Verifiziert R10/R11 gegen replicate.

    FACHLICHE ENTSCHEIDUNG (R11): Die NAPX-Fallzusammenfuehrung ist ein ABRECHNUNGS-
    Konstrukt (FPV-Wiederaufnahme-Regeln), KEINE medizinische Aussage. Die Einzelfaelle
    waren real abgeschlossene Aufenthalte -> die Encounter je FALNR bleiben UNANGETASTET
    (status=finished, echte Zeitraeume). KEIN Encounter.replaces (wuerde 'ersetzt/fehler-
    haft' behaupten), KEIN partOf (wuerde Enthaltensein behaupten). Stattdessen: EIN
    Account je APXNR als Abrechnungsklammer; jeder beteiligte Encounter referenziert ihn
    ueber Encounter.account (s. map_encounter(..., apxnr=)). Klinische Sicht = Encounter,
    Abrechnungssicht = Account. LEAD-Fall -> Extension lead-encounter, REASON -> Extension."""
    mandt = kopf.get("MANDT"); apxnr = kopf.get("APXNR")
    storn = str(kopf.get("STORN") or "").strip() not in ("", "0")
    res = {
        "resourceType": "Account",
        "id": _ids.rid(ns, "AccountApx", mandt, apxnr),
        "status": "entered-in-error" if storn else "active",
        "type": {"coding": [{
            "system": "http://terminology.hl7.org/CodeSystem/v3-ActCode",
            "code": "PBILLACCT"}],
            "text": "Fallzusammenfuehrung (FPV/Abrechnung)"},
        "identifier": [{"system": "urn:ish:apxnr", "value": apxnr}],
        "meta": {"source": "sapfhir/NAPX"},
    }
    if patnr:
        res["subject"] = [{"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, patnr)}]
    ext = []
    for f in (faelle or []):
        einri = f.get("EINRI"); falnr = f.get("FALNR")
        if not falnr:
            continue
        enc_ref = {"reference": "Encounter/" + _ids.rid(ns, "Encounter", mandt, einri, falnr)}
        if str(f.get("LEAD") or "").strip() in ("X", "1"):
            ext.append({"url": "urn:ish:apx-lead-encounter", "valueReference": enc_ref})
        reason = (f.get("REASON") or "").strip()
        if reason:
            ext.append({"url": "urn:ish:apx-reason", "valueString": reason})
    if ext:
        res["extension"] = ext
    return res


# --- ServiceRequest: N1CORDER (Clinical Order i.s.h.med) -------------------
def map_servicerequest(row: dict, ns, priv=None) -> dict:
    """N1CORDER -> ServiceRequest. Verifiziert R8 (sapdatasheet + replicate). KORREKTUR R8:
    PK ist [MANDT, CORDERID] (CORDERID = N1CORDID, 32-stellige UUID/SYSUUID_C), NICHT das
    frueher geratene ORDID. PATIENTENbezogen (PATNR->NPAT; PAPID=provisor. Patient, REFTYP
    steuert welcher gilt) — KEIN FALNR. Titel CORDTITLE, Fragestellung FRAGE, Kurzanamnese
    KANAM, Prioritaet ORDPRI (N1APRI, intern-numerisch). Auftraggeber: ETRGP (RI_KUNNR)->NGPA
    (Practitioner/Requester), initiierende OE ORDDEP/ETROE (ORGID)->NORG. ERDAT/ERTIM=
    Anlage. STORN=Storno -> revoked."""
    mandt = row.get("MANDT"); cid = row.get("CORDERID")
    pid = str(row.get("PATNR") or "").strip()
    storn = str(row.get("STORN") or "").strip() not in ("", "0")
    res = {
        "resourceType": "ServiceRequest",
        "id": _ids.rid(ns, "ServiceRequest", mandt, cid),
        "status": "revoked" if storn else "active",
        "intent": "order",
        "code": {"text": (row.get("CORDTITLE") or "").strip() or None},
        "meta": {"source": "sapfhir/N1CORDER"},
    }
    if pid and pid != "0000000000":
        res["subject"] = {"reference": "Patient/" + _ids.rid(ns, "Patient", mandt, pid)}
    # Requester: initiierender Geschaeftspartner (NGPA) bevorzugt, sonst initiierende OE (NORG)
    gp = str(row.get("ETRGP") or "").strip()
    if gp and gp != "0000000000":
        res["requester"] = {"reference": "Practitioner/" + _ids.rid(
            ns, "Practitioner", mandt, gp)}
    else:
        oe = _norg_ref(ns, mandt, row.get("ORDDEP") or row.get("ETROE"))
        if oe:
            res["requester"] = {"reference": oe}
    authored = _dt(row.get("ERDAT"), row.get("ERTIM"))
    if authored:
        res["authoredOn"] = authored
    # Fragestellung / Kurzanamnese -> note (Klartext, ggf. deidentifiziert)
    notes = []
    for fld in ("FRAGE", "KANAM", "RMCORD"):
        val = (row.get(fld) or "").strip()
        if val:
            notes.append({"text": priv.text(None, val) if priv else val})
    if notes:
        res["note"] = notes
    # Interne Prioritaet ORDPRI roh bewahren (kein 1:1-Mapping auf routine/urgent/asap/stat)
    pri = (str(row.get("ORDPRI") or "").strip()).lstrip("0")
    if pri:
        res.setdefault("extension", []).append(
            {"url": "urn:ish:cord-priority", "valueString": pri})
    return res


# Registry: FHIR-Ressourcentyp -> Mapperfunktion (fuer ndjson.py)
MAPPERS = {
    "Patient": map_patient,
    "Encounter": map_encounter,
    "EncounterBewegung": map_encounter_bewegung,
    "Condition": map_condition,
    "Procedure": map_procedure,
    "Observation": map_observation_labor,
    "ObservationLabor": map_observation_labor,
    "DiagnosticReportLabor": map_diagnosticreport_labor,
    "MedicationRequest": map_medicationrequest,
    "AllergyIntolerance": map_risikofaktor,
    "Risikofaktor": map_risikofaktor,
    "OrganizationKostentraeger": map_organization_kostentraeger,
    "OrganizationEinrichtung": map_organization_einrichtung,
    "OrganizationNorg": map_organization_norg,
    "OrganizationDas301": map_organization_das301,
    "Practitioner": map_practitioner,
    "PractitionerNper": map_practitioner_nper,
    "DocumentReference": map_document_reference,
    "ServiceRequest": map_servicerequest,
    "AccountFallzusammenfuehrung": map_account_napx,
    "Coverage": map_coverage,
    "ObservationGeburt": map_geburt,
    "LocationBau": map_location_bau,
}
