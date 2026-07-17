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


def test_map_encounter_offener_fall_sentinel():
    """R16 (Datenaudit): ENDDT=0101-01-01 = Qlik-geladenes SAP-Leerdatum (2,21 Mio Faelle!)
    -> offener Fall: KEIN period.end, status=in-progress. 9999* = SAP-Unendlich ebenso."""
    ns = I.make_ns()
    basis = {"MANDT": "100", "EINRI": "0001", "FALNR": "1", "PATNR": "1",
             "FALAR": "1", "BEGDT": "2026-07-01"}
    for sentinel in ("0101-01-01", "9999-12-31", "", None):
        enc = M.map_encounter(dict(basis, ENDDT=sentinel), ns, None)
        assert enc["status"] == "in-progress", f"Sentinel {sentinel!r}"
        assert "end" not in enc["period"], f"Sentinel {sentinel!r}"
    # echtes Fallende -> finished + end gesetzt
    enc2 = M.map_encounter(dict(basis, ENDDT="2026-07-10"), ns, None)
    assert enc2["status"] == "finished" and enc2["period"]["end"] == "2026-07-10"
    # Coverage: Sentinel-Zeitraum ebenso gefiltert
    cov = M.map_coverage({"MANDT": "100", "BELNR": "B9", "EINRI": "0001", "FALNR": "1",
                          "KOSTR": "1", "BEGDT": "0101-01-01", "ENDDT": "9999-12-31"}, ns)
    assert cov["period"] == {}


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


# --- gehaertete Mapper (verifiziert gegen Live-replicate) -------------------

def test_map_patient_deceased_and_merge():
    ns = I.make_ns()
    row = {"MANDT": "100", "PATNR": "0004000000", "GSCHL": "3",
           "GBDAT": "1957-03-14", "TODKZ": "X", "TODDT": "2025-12-01",
           "RFPAT": "0004000999"}
    res = M.map_patient(row, ns, None)
    assert res["gender"] == "other"          # GSCHL=3 verifiziert
    assert res["deceasedBoolean"] is True
    assert res["deceasedDateTime"] == "2025-12-01"
    assert res["link"][0]["type"] == "replaces"


def test_map_condition_hardened():
    ns = I.make_ns()
    # KH-Hauptdiagnose ist zugleich FHDIA + BHDIA (verifiziertes Live-Muster)
    row = {"MANDT": "100", "EINRI": "0001", "FALNR": "0020942263", "LFDNR": "001",
           "DKAT1": "56", "DKEY1": "J36", "DITXT": "Peritonsillarabszess",
           "KHDIA": "X", "FHDIA": "X", "BHDIA": "X", "STORN": " "}
    res = M.map_condition(row, ns, None)
    assert res["code"]["coding"][0]["code"] == "J36"
    assert "icd-10-gm" in res["code"]["coding"][0]["system"]
    assert res["code"]["text"] == "Peritonsillarabszess"
    kats = {c["text"] for c in res["category"]}
    assert kats == {"Krankenhaushauptdiagnose", "Fachabteilungshauptdiagnose",
                    "Behandlungsdiagnose"}


def test_map_condition_dkey2_katalog_redundanz():
    ns = I.make_ns()
    # DKEY1=DKEY2 (nur andere Katalogversion) -> KEIN zweites Coding (14 Mio Faelle)
    row = {"MANDT": "100", "EINRI": "0001", "FALNR": "1", "LFDNR": "001",
           "DKAT1": "56", "DKEY1": "C43.9", "DKAT2": "54", "DKEY2": "C43.9"}
    res = M.map_condition(row, ns, None)
    assert len(res["code"]["coding"]) == 1   # keine Dublette


def test_map_condition_nkdi_kodetext():
    ns = I.make_ns()
    kt = {"56|J36": "Peritonsillarabszess", "56|H36.0": "Retinopathia diabetica"}
    # DITXT leer -> NKDI-Text wird display UND code.text-Fallback
    row = {"MANDT": "100", "EINRI": "0001", "FALNR": "1", "LFDNR": "001",
           "DKAT1": "56", "DKEY1": "J36", "DITXT": ""}
    res = M.map_condition(row, ns, None, kodetext=kt)
    assert res["code"]["coding"][0]["display"] == "Peritonsillarabszess"
    assert res["code"]["text"] == "Peritonsillarabszess"
    # DITXT gesetzt -> DITXT hat Vorrang vor NKDI-Text, display trotzdem gesetzt
    row2 = dict(row, DITXT="V.a. Abszess", DKAT2="56", DKEY2="H36.0")
    res2 = M.map_condition(row2, ns, None, kodetext=kt)
    assert res2["code"]["text"] == "V.a. Abszess"
    assert res2["code"]["coding"][1]["display"] == "Retinopathia diabetica"
    # ohne Katalog: kein display, Verhalten unveraendert
    res3 = M.map_condition(row2, ns, None)
    assert "display" not in res3["code"]["coding"][0]


def test_map_condition_echter_zweitkode():
    ns = I.make_ns()
    # DKEY1<>DKEY2 -> zweites Coding (echte ~1 Mio Faelle)
    row = {"MANDT": "100", "EINRI": "0001", "FALNR": "1", "LFDNR": "001",
           "DKAT1": "56", "DKEY1": "E10.30", "DKAT2": "56", "DKEY2": "H36.0"}
    res = M.map_condition(row, ns, None)
    assert len(res["code"]["coding"]) == 2


def test_map_procedure_lnric():
    ns = I.make_ns()
    row = {"MANDT": "100", "EINRI": "0001", "FALNR": "0020942094",
           "LNRIC": "0010919343", "ICPMK": "36", "ICPML": "3-200",
           "BTEXT": "Native CT des Schaedels", "BGDOP": "2026-07-15",
           "ORGFA": "RADA", "STORN": " "}
    res = M.map_procedure(row, ns, None)
    # ID basiert auf LNRIC, nicht FALNR/LFDNR
    assert res["id"] == I.rid(ns, "Procedure", "100", "0010919343")
    assert res["code"]["coding"][0]["code"] == "3-200"
    assert "ops" in res["code"]["coding"][0]["system"]
    assert res["performedPeriod"]["start"] == "2026-07-15"
    # Performer = Organization(NORG) statt display (R7)
    assert res["performer"][0]["actor"]["reference"] == "Organization/" + I.rid(
        ns, "OrgNorg", "100", "RADA")
    # R8: encounter (Fall) immer gesetzt; ohne patnr faellt subject auf den Encounter zurueck
    assert res["encounter"]["reference"] == "Encounter/" + I.rid(
        ns, "Encounter", "100", "0001", "0020942094")
    assert res["subject"]["reference"] == res["encounter"]["reference"]


def test_map_procedure_r8_subject_bodysite_category():
    ns = I.make_ns()
    row = {"MANDT": "100", "EINRI": "0001", "FALNR": "42", "LNRIC": "7",
           "ICPML": "5-470", "ICPMK": "36", "BGDOP": "20240115", "BZTOP": "081500",
           "ENDOP": "20240115", "EZTOP": "093000", "ORGFA": "10000123", "ORGPF": "10000900",
           "LSLOK": "R", "OPART": "01"}
    # patnr-Kontext (Pipeline FALNR->NFAL->PATNR) -> subject=Patient (FHIR-konform)
    res = M.map_procedure(row, ns, None, patnr="0004628590")
    assert res["subject"]["reference"] == "Patient/" + I.rid(ns, "Patient", "100", "0004628590")
    assert res["encounter"]["reference"] == "Encounter/" + I.rid(ns, "Encounter", "100", "0001", "42")
    # OP-Zeit mit Uhrzeit (Rohformat der Codebasis)
    assert res["performedPeriod"] == {"start": "20240115T081500", "end": "20240115T093000"}
    # LSLOK -> bodySite (TN26E), OPART -> category (TN14O)
    assert res["bodySite"][0]["coding"][0]["system"] == "urn:ish:tn26e"
    assert res["category"]["coding"][0]["system"] == "urn:ish:tn14o"
    # abweichende erbringende OE ORGPF -> zweiter Performer
    refs = {p["actor"]["reference"] for p in res["performer"]}
    assert refs == {"Organization/" + I.rid(ns, "OrgNorg", "100", "10000123"),
                    "Organization/" + I.rid(ns, "OrgNorg", "100", "10000900")}


def test_map_bewegung_onleave():
    ns = I.make_ns()
    row = {"MANDT": "100", "EINRI": "0001", "FALNR": "1", "LFDNR": "1",
           "BEWTY": "6", "BWIDT": "2026-01-01"}
    res = M.map_encounter_bewegung(row, ns, None)
    assert res["status"] == "onleave"        # BEWTY=6 Abwesenheit Beginn (Beurlaubung)
    assert res["type"][0]["text"] == "Abwesenheit Beginn"


def test_map_coverage_nksk():
    ns = I.make_ns()
    row = {"MANDT": "100", "BELNR": "B1", "EINRI": "0001", "FALNR": "0020942275",
           "KOSTR": "0009999999", "KSTYP": "N", "BEGDT": "2026-07-01",
           "ENDDT": "2026-09-30", "STORN": " "}
    res = M.map_coverage(row, ns, None)
    assert res["resourceType"] == "Coverage"
    assert res["status"] == "active"
    assert res["type"]["text"] == "Selbstzahler"   # KOSTR=0009999999
    assert res["period"]["end"] == "2026-09-30"


def test_map_geburt_observations():
    ns = I.make_ns()
    row = {"MANDT": "100", "EINRI": "0001", "FALN1": "K1", "LFDNR": "1",
           "GBDAT": "2026-05-01", "GBGEW": 3450, "GBGRO": 52, "HEAD_SIZE": 35}
    out = M.map_geburt(row, ns, None)
    assert len(out) == 3
    codes = {o["code"]["text"] for o in out}
    assert codes == {"Geburtsgewicht", "Geburtslaenge", "Kopfumfang"}
    assert out[0]["valueQuantity"]["value"] == 3450


def test_map_location_bau():
    ns = I.make_ns()
    # R8-Korrektur: XKOOR/YKOOR sind Lageplan-Koords (NUMC3), KEINE Geoposition ->
    # duerfen NICHT als position.longitude/latitude erscheinen.
    row = {"MANDT": "100", "BAUID": "H1", "BAUNA": "Haus 1", "BKURZ": "H1",
           "BAUTY": "KH", "XKOOR": "123", "YKOOR": "456", "LOEKZ": " "}
    res = M.map_location_bau(row, ns, None)
    assert res["name"] == "Haus 1"
    assert res["status"] == "active"
    assert "position" not in res                       # KEIN Geo-Mapping mehr
    assert res["alias"] == ["H1"]                       # BKURZ
    assert res["physicalType"]["coding"][0]["system"] == "urn:ish:tn11b"
    assert res["physicalType"]["coding"][0]["code"] == "KH"
    # Adresse kommt ausschliesslich aus NADR (adr-Join), nicht aus NBAU-Koords
    res2 = M.map_location_bau(row, ns, None, adr={"STRAS": "Klinikstr. 1", "ORT": "Cottbus",
                                                  "PSTLZ": "03048", "LAND": "DE"})
    assert res2["address"]["city"] == "Cottbus"
    # NPOB-Struktur (Pflegeort, verifiziert R8 gegen replicate): ORGID -> managingOrganization
    res3 = M.map_location_bau(row, ns, None, struktur={"POBNR": "0000000123", "ORGID": "10000123"})
    org = M.map_organization_norg({"MANDT": "100", "ORGID": "10000123"}, ns)
    assert res3["managingOrganization"]["reference"] == "Organization/" + org["id"]
    # TN11H-Hierarchie (verifiziert R8 gegen replicate): UEBBE (Elternteil) -> Location.partOf
    bett = {"MANDT": "100", "BAUID": "A11X1001", "BAUNA": "Bettplatz 01", "BAUTY": "AB", "LOEKZ": " "}
    res4 = M.map_location_bau(bett, ns, None, hierarchie={"UNTBE": "A11X1001", "UEBBE": "A1006_P"})
    assert res4["partOf"]["reference"] == "Location/" + I.rid(ns, "LocationBau", "100", "A1006_P")


# --- Labor: flexible Parser + N2LABOR001/N2LABOR-Mapper (Runde 6) -----------
def test_to_float_flexibel():
    assert M._to_float("2,5") == 2.5
    assert M._to_float("122.5") == 122.5
    assert M._to_float("1.234,56") == 1234.56   # de: Tausenderpunkt, Dezimalkomma
    assert M._to_float("1,234.56") == 1234.56   # en: Tausenderkomma, Dezimalpunkt
    assert M._to_float("positiv") is None
    assert M._to_float("") is None


def test_parse_value_zahl_komparator_text():
    assert M._parse_value("2,5", "") == {"valueQuantity": {"value": 2.5}}
    assert M._parse_value("122.5", "µmol/l") == {"valueQuantity": {"value": 122.5, "unit": "µmol/l"}}
    assert M._parse_value("<0,05", "mg/l") == {"valueQuantity": {"value": 0.05, "unit": "mg/l", "comparator": "<"}}
    assert M._parse_value("positiv", "") == {"valueString": "positiv"}
    assert M._parse_value(" ", "mg") == {}


def test_parse_range_intervall_grenzen_text():
    assert M._parse_range("26 - 150") == {"low": {"value": 26.0}, "high": {"value": 150.0}}
    assert M._parse_range("0,1-2") == {"low": {"value": 0.1}, "high": {"value": 2.0}}
    assert M._parse_range("< 5") == {"high": {"value": 5.0}}
    assert M._parse_range("bis 150") == {"high": {"value": 150.0}}
    assert M._parse_range("ab 10") == {"low": {"value": 10.0}}
    assert M._parse_range("30 - 350 mg/dl") == {"low": {"value": 30.0}, "high": {"value": 350.0}}
    assert M._parse_range("negativ") == {"text": "negativ"}
    assert M._parse_range("") is None


def test_interpretation_flag_und_abgeleitet():
    # explizites Flag hat Vorrang
    assert M._interpretation("H", {"value": 9}, None)["coding"][0]["code"] == "H"
    # aus Bereich abgeleitet, wenn Haus nicht flaggt (2.5 > 2)
    rr = M._parse_range("0.1 - 2")
    assert M._interpretation("", {"value": 2.5}, rr)["coding"][0]["code"] == "H"
    # im Bereich -> N
    assert M._interpretation("", {"value": 1.0}, rr)["coding"][0]["code"] == "N"
    # unbekanntes Flag -> Rohtext
    assert M._interpretation("?", None, None) == {"text": "?"}


def _lab_fixture():
    header = {"MANDT": "100", "N2LAPATNR": "0004628590", "N2LAFALNR": "0013338095",
              "N2LAEINRI": "0001", "N2LADATUM": "2012-07-28"}
    base = {"MANDT": "100", "DOKAR": "LAB", "DOKNR": "000000000000001", "DOKVR": "01", "DOKTL": "000"}
    v = dict(base, MUSEQ="00002", N2KATTEXT="Quotient", N2LEISTID="PHETYR_Q",
             N2VALUE="2.5", N2UNIT=" ", N2NORMAL="0.1 - 2", N2ABNORMAL=" ", N2DATE="2012-07-28")
    return header, base, v


def test_map_observation_labor_werte_und_kopfbezug():
    ns = I.make_ns("sapfhir")
    header, _, v = _lab_fixture()
    o = M.map_observation_labor(v, ns, header=header)
    assert o["resourceType"] == "Observation"
    assert o["valueQuantity"]["value"] == 2.5
    assert o["referenceRange"][0] == {"low": {"value": 0.1}, "high": {"value": 2.0}}
    assert o["interpretation"][0]["coding"][0]["code"] == "H"
    assert o["subject"]["reference"].startswith("Patient/")
    assert o["encounter"]["reference"].startswith("Encounter/")
    assert o["partOf"][0]["reference"].startswith("DiagnosticReport/")


def test_diagnosticreport_result_verweist_auf_observation():
    ns = I.make_ns("sapfhir")
    header, base, v = _lab_fixture()
    o = M.map_observation_labor(v, ns, header=header)
    dr = M.map_diagnosticreport_labor(dict(base, **header, N2LASTATUS="F"), ns, value_rows=[v])
    assert dr["resourceType"] == "DiagnosticReport"
    # result[]-Referenz trifft die deterministische Observation-ID
    assert dr["result"][0]["reference"] == "Observation/" + o["id"]
    # partOf der Observation trifft die DR-ID
    assert o["partOf"][0]["reference"] == "DiagnosticReport/" + dr["id"]


# --- BEWTY-Korrektur (R6, gegen TN14T) --------------------------------------
def test_bewegungsart_2_3_korrigiert():
    assert M.BEWEGUNGSART["2"] == "Entlassung"
    assert M.BEWEGUNGSART["3"] == "Verlegung"
    ns = I.make_ns("sapfhir")
    e = M.map_encounter_bewegung({"MANDT": "100", "EINRI": "0001", "FALNR": "1", "LFDNR": "2",
                                  "BEWTY": "2"}, ns)
    assert e["type"][0]["text"] == "Entlassung"


# --- MedicationRequest (N1MEORDER) ------------------------------------------
def test_medicationrequest_kern():
    ns = I.make_ns("sapfhir")
    row = {"MANDT": "100", "MEORDID": "0000012345", "PATNR": "0004628590", "FALNR": "0013338095",
           "EINRI": "0001", "MOTX": "Ibuprofen 400mg", "EXT_DRUGID": "12345678", "APROU": "p.o.",
           "DOSDEF": "1-1-1", "DISPQUAN": "30", "DISPQUANU": "ST", "AUTIDEM": " ",
           "MOVDF": "2012-07-28", "MOVDT": "2012-08-04", "ERDAT": "2012-07-28", "STORN": " "}
    m = M.map_medicationrequest(row, ns)
    assert m["resourceType"] == "MedicationRequest" and m["status"] == "active"
    assert m["medicationCodeableConcept"]["text"] == "Ibuprofen 400mg"
    assert m["medicationCodeableConcept"]["coding"][0]["system"].endswith("pzn")  # numerisch -> PZN
    assert m["dosageInstruction"][0]["text"] == "1-1-1"
    assert m["dispenseRequest"]["quantity"]["value"] == 30.0
    assert m["dispenseRequest"]["validityPeriod"]["end"] == "2012-08-04"
    assert m["encounter"]["reference"].startswith("Encounter/")


def test_medicationrequest_storno():
    ns = I.make_ns("sapfhir")
    m = M.map_medicationrequest({"MANDT": "100", "MEORDID": "1", "PATNR": "1", "STORN": "X"}, ns)
    assert m["status"] == "entered-in-error"


# --- Risikofaktor-Routing (NRSF): Allergie vs MRE vs administrativ ----------
def test_rsf_routing_allergie():
    ns = I.make_ns("sapfhir")
    r = M.map_risikofaktor({"MANDT": "100", "PATNR": "0004628590", "RSFNR": "000009",
                            "LFDNR": "1", "KZTXT": "Penicillin", "EXIST": " ", "LOEKZ": " "}, ns)
    assert r["resourceType"] == "AllergyIntolerance"
    assert r["category"] == ["medication"]
    assert r["clinicalStatus"]["coding"][0]["code"] == "active"


def test_rsf_routing_mre_wird_flag_nicht_allergie():
    ns = I.make_ns("sapfhir")
    r = M.map_risikofaktor({"MANDT": "100", "PATNR": "1", "RSFNR": "000017",
                            "LFDNR": "1", "KZTXT": "MRSA"}, ns)
    assert r["resourceType"] == "Flag"
    assert r["category"][0]["coding"][0]["code"] == "safety"


def test_rsf_routing_admin():
    ns = I.make_ns("sapfhir")
    r = M.map_risikofaktor({"MANDT": "100", "PATNR": "1", "RSFNR": "000048",
                            "LFDNR": "1", "KZTXT": "Wartelistenpatient"}, ns)
    assert r["resourceType"] == "Flag"
    assert r["category"][0]["coding"][0]["code"] == "admin"


def test_rsf_keyword_fallback_fuer_neue_codes():
    ns = I.make_ns("sapfhir")
    # unbekannte RSFNR, aber Text enthaelt MRE-Keyword -> infection
    r = M.map_risikofaktor({"MANDT": "100", "PATNR": "1", "RSFNR": "999999",
                            "LFDNR": "1", "KZTXT": "5-MRGN Erreger"}, ns)
    assert r["resourceType"] == "Flag" and r["category"][0]["coding"][0]["code"] == "safety"


# --- Organization: NKTR (Kostentraeger) + TN01 (Einrichtung), R6 ------------
def test_org_kostentraeger_und_coverage_referenz():
    ns = I.make_ns("sapfhir")
    kt = {"MANDT": "100", "KOSTR": "0000123456", "KSSNM": "AOK PLUS", "PM301": "107299005",
          "KTART": "01", "LOEKZ": " "}
    org = M.map_organization_kostentraeger(kt, ns)
    assert org["resourceType"] == "Organization" and org["name"] == "AOK PLUS"
    assert org["active"] is True
    assert any(i["system"].endswith("iknr") and i["value"] == "107299005" for i in org["identifier"])
    # Referenz-Konsistenz: Coverage.payor zeigt genau auf diese Organization-ID
    cov = M.map_coverage({"MANDT": "100", "BELNR": "1", "EINRI": "0001", "FALNR": "9",
                          "KOSTR": "0000123456"}, ns)
    assert cov["payor"][0]["reference"] == "Organization/" + org["id"]


def test_org_einrichtung_und_encounter_serviceprovider():
    ns = I.make_ns("sapfhir")
    tn01 = {"MANDT": "100", "EINRI": "0001", "EINBZ": "Uniklinik Musterstadt",
            "INSTNR": "260140077", "STRAS": "Klinikstr. 1", "ORT": "Musterstadt", "PSTLZ": "01234"}
    org = M.map_organization_einrichtung(tn01, ns)
    assert org["name"] == "Uniklinik Musterstadt"
    assert org["address"][0]["city"] == "Musterstadt"
    # Encounter.serviceProvider muss dieselbe Einrichtungs-Org-ID treffen
    enc = M.map_encounter({"MANDT": "100", "EINRI": "0001", "FALNR": "9", "PATNR": "5",
                           "FALAR": "1", "BEGDT": "2012-01-01"}, ns)
    assert enc["serviceProvider"]["reference"] == "Organization/" + org["id"]


# --- Practitioner (NGPA) + Patient.generalPractitioner-Pfad (R7) ------------
def test_practitioner_ngpa():
    ns = I.make_ns("sapfhir")
    p = M.map_practitioner({"MANDT": "100", "GPART": "0000500123", "NAME1": "Schmidt",
                            "NAME2": "Anna", "TITEL": "Dr.", "GSCHL": "2", "INSTN": "260140077",
                            "LOEKZ": " "}, ns)
    assert p["resourceType"] == "Practitioner" and p["gender"] == "female"
    assert p["name"][0]["family"] == "Schmidt" and p["name"][0]["prefix"] == ["Dr."]
    assert any(i["system"].endswith("iknr") for i in p["identifier"])


def test_patient_generalpractitioner_referenz():
    ns = I.make_ns("sapfhir")
    pat = M.map_patient({"MANDT": "100", "PATNR": "0004628590", "GSCHL": "1",
                         "HARNR": "0000500123"}, ns)
    prac = M.map_practitioner({"MANDT": "100", "GPART": "0000500123"}, ns)
    # generalPractitioner muss exakt auf die Practitioner-ID zeigen (HARNR==GPART)
    assert pat["generalPractitioner"][0]["reference"] == "Practitioner/" + prac["id"]


def test_patient_adresse_aus_npat_direktfeldern():
    ns = I.make_ns("sapfhir")
    pat = M.map_patient({"MANDT": "100", "PATNR": "1", "GSCHL": "1", "NNAME": "Mueller",
                         "VNAME": "Max", "STRAS": "Hauptstr. 5", "ORT": "Leipzig",
                         "PSTLZ": "04109", "LAND": "DE"}, ns)  # priv=None -> Klarbetrieb
    assert pat["address"][0]["city"] == "Leipzig"
    assert pat["address"][0]["line"] == ["Hauptstr. 5"]


# --- NBEW: Bewegung + hospitalization + NORG-Organisation (R7) --------------
def test_bewegung_verifizierte_pfade():
    ns = I.make_ns("sapfhir")
    b = M.map_encounter_bewegung({"MANDT": "100", "EINRI": "0001", "FALNR": "0000000042",
        "LFDNR": "00001", "BEWTY": "1", "BWIDT": "20240115", "BWIZT": "081500",
        "BWEDT": "20240115", "BWEZT": "140000", "ORGFA": "10000123", "ORGPF": "10000900",
        "ZIMMR": "20000055", "BETT": "20000056", "BWGR1": "01", "BWGR2": "02",
        "FACHR": "0100"}, ns)
    # OE ORGFA -> Organization(OrgNorg), identisch zur map_organization_norg-ID
    org = M.map_organization_norg({"MANDT": "100", "ORGID": "10000123", "ORGNA": "Innere",
                                   "EINRI": "0001"}, ns)
    assert b["serviceProvider"]["reference"] == "Organization/" + org["id"]
    # pflegerische OE als Extension
    assert b["extension"][0]["url"] == "urn:ish:nursing-org"
    # Bett/Raum -> Location(NBAU)
    ptypes = {l["physicalType"]["coding"][0]["code"] for l in b["location"]}
    assert ptypes == {"ro", "bd"}
    # Zeitraum mit Uhrzeit (BWIDT+BWIZT, Rohformat der Codebasis)
    assert b["period"]["start"] == "20240115T081500"
    # Bewegungsgrund BWGR1+BWGR2 -> TN14G
    assert b["reasonCode"][0]["coding"][0]["system"] == "urn:ish:tn14g"
    assert b["reasonCode"][0]["coding"][0]["code"] == "0102"


def test_encounter_hospitalization_aus_bewegungen():
    ns = I.make_ns("sapfhir")
    bew = [
        {"MANDT": "100", "EINRI": "0001", "FALNR": "42", "LFDNR": "00001", "BEWTY": "1",
         "RFSRC": "01"},                        # Aufnahme -> admitSource (TN14H)
        {"MANDT": "100", "EINRI": "0001", "FALNR": "42", "LFDNR": "00009", "BEWTY": "2",
         "EZUST": "07"},                        # Entlassung -> dischargeDisposition (TN14D)
    ]
    enc = M.map_encounter({"MANDT": "100", "EINRI": "0001", "FALNR": "42", "PATNR": "1",
                           "FALAR": "1", "BEGDT": "20240115"}, ns, bewegungen=bew)
    assert enc["hospitalization"]["admitSource"]["coding"][0]["system"] == "urn:ish:tn14h"
    assert enc["hospitalization"]["admitSource"]["coding"][0]["code"] == "01"
    assert enc["hospitalization"]["dischargeDisposition"]["coding"][0]["system"] == "urn:ish:tn14d"
    assert enc["hospitalization"]["dischargeDisposition"]["coding"][0]["code"] == "07"


def test_encounter_ohne_bewegungen_ohne_hospitalization():
    ns = I.make_ns("sapfhir")
    enc = M.map_encounter({"MANDT": "100", "EINRI": "0001", "FALNR": "42", "PATNR": "1",
                           "FALAR": "2", "BEGDT": "20240115"}, ns)
    assert "hospitalization" not in enc


def test_procedure_performer_ist_norg_referenz():
    ns = I.make_ns("sapfhir")
    proc = M.map_procedure({"MANDT": "100", "EINRI": "0001", "FALNR": "42", "LNRIC": "7",
                            "ICPML": "5-470", "ICPMK": "36", "ORGFA": "10000123"}, ns)
    org = M.map_organization_norg({"MANDT": "100", "ORGID": "10000123"}, ns)
    assert proc["performer"][0]["actor"]["reference"] == "Organization/" + org["id"]


# --- NDOC -> DocumentReference (verifizierte Feld-/Schluesselpfade R8) -------
def test_map_document_reference_ndoc():
    ns = I.make_ns("sapfhir")
    row = {"MANDT": "100", "EINRI": "0001", "DOKAR": "ARZ", "DOKNR": "0000000000012345",
           "DOKVR": "01", "DOKTL": "000", "LFDDOK": "0001", "DTID": "ARZTBRIEF",
           "MEDOK": "X", "PATNR": "0004628590", "FALNR": "0013338095",
           "MITARB": "0000500123", "ORGDO": "10000123",
           "DODAT": "20240115", "DOTIM": "101500", "STORN": " "}
    d = M.map_document_reference(row, ns)
    assert d["resourceType"] == "DocumentReference" and d["status"] == "current"
    # ID + masterIdentifier aus dem DVS-Schluessel (nicht DOCID)
    assert d["id"] == I.rid(ns, "DocRef", "100", "ARZ", "0000000000012345", "01", "000", "0001")
    assert d["masterIdentifier"]["value"] == "ARZ-0000000000012345-01-000"
    assert d["type"]["coding"][0]["system"] == "urn:ish:n2dt"
    assert d["subject"]["reference"] == "Patient/" + I.rid(ns, "Patient", "100", "0004628590")
    assert d["context"]["encounter"][0]["reference"].startswith("Encounter/")
    assert d["date"] == "20240115T101500"
    # Autor: Practitioner(NGPA, MITARB) + Organization(NORG, ORGDO)
    refs = {a["reference"] for a in d["author"]}
    assert "Practitioner/" + I.rid(ns, "Practitioner", "100", "0000500123") in refs
    assert "Organization/" + I.rid(ns, "OrgNorg", "100", "10000123") in refs


def test_map_document_reference_storno():
    ns = I.make_ns("sapfhir")
    d = M.map_document_reference({"MANDT": "100", "DOKAR": "ARZ", "DOKNR": "1", "DOKVR": "01",
                                  "DOKTL": "000", "LFDDOK": "0001", "STORN": "X"}, ns)
    assert d["status"] == "entered-in-error"


# --- N1CORDER -> ServiceRequest (PK CORDERID/UUID, R8) ----------------------
def test_map_servicerequest_n1corder():
    ns = I.make_ns("sapfhir")
    row = {"MANDT": "100", "CORDERID": "0050568A1B2C1EDF9AB0C1234567890A",
           "PATNR": "0004628590", "CORDTITLE": "Konsil Kardiologie", "FRAGE": "Belastbarkeit?",
           "ORDPRI": "030", "ETRGP": "0000500123", "ORDDEP": "10000123",
           "ERDAT": "20240115", "ERTIM": "080000", "STORN": " "}
    s = M.map_servicerequest(row, ns)
    assert s["resourceType"] == "ServiceRequest" and s["status"] == "active"
    assert s["intent"] == "order"
    # ID basiert auf der UUID CORDERID (nicht ORDID)
    assert s["id"] == I.rid(ns, "ServiceRequest", "100", "0050568A1B2C1EDF9AB0C1234567890A")
    assert s["code"]["text"] == "Konsil Kardiologie"
    assert s["subject"]["reference"] == "Patient/" + I.rid(ns, "Patient", "100", "0004628590")
    # Requester = initiierender Geschaeftspartner (NGPA) hat Vorrang vor OE
    assert s["requester"]["reference"] == "Practitioner/" + I.rid(ns, "Practitioner", "100", "0000500123")
    assert s["authoredOn"] == "20240115T080000"
    assert s["note"][0]["text"] == "Belastbarkeit?"
    assert s["extension"][0]["valueString"] == "30"   # ORDPRI fuehrende Nullen entfernt


def test_map_servicerequest_storno_und_oe_fallback():
    ns = I.make_ns("sapfhir")
    # kein ETRGP -> Requester faellt auf initiierende OE (NORG) zurueck; STORN -> revoked
    s = M.map_servicerequest({"MANDT": "100", "CORDERID": "ABC", "PATNR": "1",
                              "ORDDEP": "10000123", "STORN": "X"}, ns)
    assert s["status"] == "revoked"
    assert s["requester"]["reference"] == "Organization/" + I.rid(ns, "OrgNorg", "100", "10000123")


# --- NAPX Fallzusammenfuehrung -> Account (R11: Abrechnungsklammer!) ---------
def test_account_napx_abrechnungsklammer():
    """R11: Zusammenfuehrung = Abrechnungskonstrukt. Encounter bleiben medizinisch
    unangetastet (finished, KEIN replaces/partOf); Klammer = Account je APXNR."""
    ns = I.make_ns("sapfhir")
    kopf = {"MANDT": "100", "APXNR": "0000004711", "STORN": " "}
    faelle = [
        {"MANDT": "100", "APXNR": "0000004711", "EINRI": "0001", "FALNR": "0011111111",
         "LEAD": "X", "REASON": "01"},   # fuehrender Fall (FPV-Wiederaufnahme)
        {"MANDT": "100", "APXNR": "0000004711", "EINRI": "0001", "FALNR": "0022222222",
         "LEAD": " ", "REASON": " "},
    ]
    acc = M.map_account_napx(kopf, ns, faelle=faelle, patnr="0004628590")
    assert acc["resourceType"] == "Account" and acc["status"] == "active"
    assert acc["type"]["coding"][0]["code"] == "PBILLACCT"
    assert acc["subject"][0]["reference"] == "Patient/" + I.rid(ns, "Patient", "100", "0004628590")
    # LEAD-Fall als Extension referenziert
    leads = [e for e in acc["extension"] if e["url"] == "urn:ish:apx-lead-encounter"]
    assert leads[0]["valueReference"]["reference"] == "Encounter/" + I.rid(
        ns, "Encounter", "100", "0001", "0011111111")

    # Beide Encounter zeigen per account auf DENSELBEN Account — sonst unveraendert
    enc1 = M.map_encounter({"MANDT": "100", "EINRI": "0001", "FALNR": "0011111111",
                            "PATNR": "0004628590", "FALAR": "1", "BEGDT": "20240101",
                            "ENDDT": "20240110"}, ns, apxnr="0000004711")
    enc2 = M.map_encounter({"MANDT": "100", "EINRI": "0001", "FALNR": "0022222222",
                            "PATNR": "0004628590", "FALAR": "1", "BEGDT": "20240120",
                            "ENDDT": "20240125"}, ns, apxnr="0000004711")
    assert enc1["account"][0]["reference"] == "Account/" + acc["id"]
    assert enc2["account"][0]["reference"] == "Account/" + acc["id"]
    # medizinische Wahrheit unangetastet: eigener Status/Zeitraum, KEIN replaces/partOf
    for e in (enc1, enc2):
        assert e["status"] == "finished"
        assert "partOf" not in e and "link" not in e


def test_account_napx_storno_und_encounter_ohne_apx():
    ns = I.make_ns("sapfhir")
    acc = M.map_account_napx({"MANDT": "100", "APXNR": "9", "STORN": "X"}, ns)
    assert acc["status"] == "entered-in-error"
    # Fall ohne Zusammenfuehrung -> kein account-Feld
    enc = M.map_encounter({"MANDT": "100", "EINRI": "0001", "FALNR": "7", "PATNR": "1",
                           "FALAR": "1", "BEGDT": "20240101"}, ns)
    assert "account" not in enc


# --- NFPZ -> Encounter.participant + NPER -> Practitioner (R12) --------------
def test_encounter_participant_aus_nfpz():
    ns = I.make_ns("sapfhir")
    nfpz = [
        {"MANDT": "100", "EINRI": "0001", "FALNR": "42", "PERNR": "0000012345",
         "LFDNR": "1", "FARZT": "1", "BEGDT": "20240101", "ENDDT": "20240105", "STORN": " "},
        {"MANDT": "100", "EINRI": "0001", "FALNR": "42", "PERNR": "0000067890",
         "LFDNR": "2", "FARZT": "2", "STORN": " "},
        # stornierte Zuordnung -> uebersprungen
        {"MANDT": "100", "EINRI": "0001", "FALNR": "42", "PERNR": "0000099999",
         "LFDNR": "3", "FARZT": "1", "STORN": "X"},
    ]
    enc = M.map_encounter({"MANDT": "100", "EINRI": "0001", "FALNR": "42", "PATNR": "1",
                           "FALAR": "1", "BEGDT": "20240101"}, ns, personal=nfpz)
    assert len(enc["participant"]) == 2          # Storno-Zeile faellt raus
    p1 = enc["participant"][0]
    # Referenz-Konsistenz: participant trifft exakt die NPER-Practitioner-ID
    prac = M.map_practitioner_nper({"MANDT": "100", "PERNR": "0000012345"}, ns)
    assert p1["individual"]["reference"] == "Practitioner/" + prac["id"]
    assert p1["type"][0]["coding"][0]["system"] == "urn:ish:farzt"
    assert p1["type"][0]["coding"][0]["code"] == "1"
    assert p1["period"] == {"start": "20240101", "end": "20240105"}


def test_practitioner_nper_lanr_und_rollen():
    ns = I.make_ns("sapfhir")
    p = M.map_practitioner_nper({"MANDT": "100", "PERNR": "0000012345",
                                 "FIXLANR": "123456789", "FACHR": "0100",
                                 "ARZT": "X", "PFLEG": " ", "LOEKZ": " "}, ns)
    assert p["resourceType"] == "Practitioner" and p["active"] is True
    systems = {i["system"] for i in p["identifier"]}
    assert "urn:ish:pernr" in systems and "http://fhir.de/sid/kbv/lanr" in systems
    assert p["qualification"][0]["code"]["coding"][0]["code"] == "0100"
    assert p["extension"] == [{"url": "urn:ish:nper-rolle", "valueCode": "arzt"}]
    # NPER hat keine Namensfelder -> nie ein name-Feld
    assert "name" not in p


def test_practitioner_nper_gleiche_id_wie_ngpa():
    """R13 (replicate-verifiziert): NGPA.GPART == NPER.PERNR fuer ALLE 236.114 Personen
    -> dieselbe Person MUSS dieselbe Practitioner-ID ergeben (keine Dubletten).
    NFPZ-participant, NPAT.generalPractitioner und NPER-Anreicherung treffen sich."""
    ns = I.make_ns("sapfhir")
    ngpa = M.map_practitioner({"MANDT": "100", "GPART": "0000012345"}, ns)
    nper = M.map_practitioner_nper({"MANDT": "100", "PERNR": "0000012345"}, ns)
    assert ngpa["id"] == nper["id"]
    # und der NFPZ-participant referenziert genau diese ID
    enc = M.map_encounter({"MANDT": "100", "EINRI": "0001", "FALNR": "42", "PATNR": "1",
                           "FALAR": "1", "BEGDT": "20240101"}, ns,
                          personal=[{"PERNR": "0000012345", "FARZT": "1", "STORN": " "}])
    assert enc["participant"][0]["individual"]["reference"] == "Practitioner/" + ngpa["id"]


# --- N1LSTEAM -> Procedure.performer (R15: individuelles OP-Team) ------------
def test_procedure_op_team():
    ns = I.make_ns("sapfhir")
    team = [
        {"LNRLS": "0055555555", "VRGNR": "01", "VORGANG": "OPT1", "GPART": "0000012345",
         "BEGDT": "20240115", "BEGZT": "081500"},
        {"LNRLS": "0055555555", "VRGNR": "02", "VORGANG": "INS1", "GPART": "0000067890"},
        {"LNRLS": "0055555555", "VRGNR": "03", "VORGANG": "XYZ9", "GPART": "0000011111"},
        {"LNRLS": "0055555555", "VRGNR": "04", "VORGANG": "ANA3", "GPART": "0000000000"},  # leer
    ]
    res = M.map_procedure({"MANDT": "100", "EINRI": "0001", "FALNR": "42", "LNRIC": "7",
                           "ICPML": "5-470", "ICPMK": "36", "ORGFA": "10000123"}, ns,
                          team=team)
    # OE-Performer + 3 Personen (GPART 0000000000 uebersprungen)
    assert len(res["performer"]) == 4
    personen = res["performer"][1:]
    # Operateur: gemeinsames Practitioner-Schema (R13) + kuratiertes Display
    op = personen[0]
    prac = M.map_practitioner({"MANDT": "100", "GPART": "0000012345"}, ns)
    assert op["actor"]["reference"] == "Practitioner/" + prac["id"]
    assert op["function"]["coding"][0]["system"] == "urn:ish:op-vorgang"
    assert op["function"]["coding"][0]["code"] == "OPT1"
    assert op["function"]["text"] == "Operateur"
    # unbekannter Code: Rohcode ohne Display
    assert personen[2]["function"]["coding"][0]["code"] == "XYZ9"
    assert "text" not in personen[2]["function"]


# --- NFFZ -> Encounter-Fallbezuege (R15: klinische Verknuepfung) --------------
def test_encounter_fallbezug_nffz():
    ns = I.make_ns("sapfhir")
    nffz = [
        # Mutter (dieser Fall) <-> Neugeborenes (Partnerfall) — gesicherte Deutung
        {"EINRI": "0001", "FALN1": "1000", "FALN2": "2000", "REFA1": "M", "REFA2": "N",
         "STORN": " "},
        # unbekannter Bezug Q<->Q: verlustfrei als Rohcode
        {"EINRI": "0001", "FALN1": "1000", "FALN2": "3000", "REFA1": "Q", "REFA2": "Q",
         "STORN": " "},
        # storniert -> raus
        {"EINRI": "0001", "FALN1": "1000", "FALN2": "4000", "REFA1": "M", "REFA2": "N",
         "STORN": "X"},
    ]
    enc = M.map_encounter({"MANDT": "100", "EINRI": "0001", "FALNR": "1000", "PATNR": "1",
                           "FALAR": "1", "BEGDT": "20240101", "ENDDT": "20240105"},
                          ns, verknuepfungen=nffz)
    bez = [e for e in enc["extension"] if e["url"] == "urn:ish:fallbezug"]
    assert len(bez) == 2                                  # Storno gefiltert
    # Partner-Referenz trifft die deterministische Encounter-ID des Kindfalls
    partner = bez[0]["extension"][0]
    assert partner["url"] == "partner"
    assert partner["valueReference"]["reference"] == "Encounter/" + I.rid(
        ns, "Encounter", "100", "0001", "2000")
    rollen = {x["url"]: x for x in bez[0]["extension"][1:]}
    assert rollen["rolle-dieser-fall"]["valueCodeableConcept"]["text"] == "Mutter"
    assert rollen["rolle-partner"]["valueCodeableConcept"]["text"] == "Neugeborenes"
    # Q-Bezug: Rohcode ohne Display
    q = bez[1]["extension"][1]["valueCodeableConcept"]
    assert q["coding"][0]["code"] == "Q" and "text" not in q
    # Encounter selbst bleibt medizinisch unveraendert
    assert enc["status"] == "finished" and "partOf" not in enc


# --- NVVP -> Coverage-Anreicherung (R15: Versichertennummer) -----------------
def test_coverage_nvvp_anreicherung():
    ns = I.make_ns("sapfhir")
    nksk = {"MANDT": "100", "BELNR": "B1", "EINRI": "0001", "FALNR": "9",
            "KOSTR": "0000123456", "STORN": " "}
    vvp = {"PATNR": "1", "KOSTR": "0000123456", "VERNR": "A123456789", "MGART": "1"}
    # Klarbetrieb (priv=None): KVNR roh
    cov = M.map_coverage(nksk, ns, None, vvp=vvp)
    assert cov["subscriberId"] == "A123456789"
    assert cov["extension"][0]["url"] == "urn:ish:mgart"
    assert cov["extension"][0]["valueCodeableConcept"]["coding"][0]["code"] == "1"
    # Pseudonymisierung: KVNR MUSS gehasht werden (wertbasiert stabil)
    p = Privacy(mode="pseudonymize", secret="s")
    cov2 = M.map_coverage(nksk, ns, p, vvp=vvp)
    assert cov2["subscriberId"] == p.hash_id("A123456789", "kvnr")
    assert cov2["subscriberId"] != "A123456789"
    # ohne vvp: unveraendert
    cov3 = M.map_coverage(nksk, ns, None)
    assert "subscriberId" not in cov3


def test_organization_das301():
    ns = I.make_ns("sapfhir")
    row = {"MANDT": "100", "DAS301": "DAK01", "INSTNR": "660500345",
           "NAME1": "DAK Datenannahmestelle", "NAME2": "Rechenzentrum Nord",
           "STRAS": "Nagelsweg 27-31", "PSTLZ": "20097", "ORT": "Hamburg", "LAND": "DE",
           "ANSPR": "Fr. Meyer", "TELFN": "040/2364855-0"}
    org = M.map_organization_das301(row, ns)
    assert org["resourceType"] == "Organization"
    assert org["name"] == "DAK Datenannahmestelle" and org["alias"] == ["Rechenzentrum Nord"]
    systems = {i["system"] for i in org["identifier"]}
    assert "urn:ish:das301" in systems and "http://fhir.de/sid/arge-ik/iknr" in systems
    assert org["address"][0]["city"] == "Hamburg"
    assert org["telecom"][0]["system"] == "phone"
    assert org["contact"][0]["name"]["text"] == "Fr. Meyer"
