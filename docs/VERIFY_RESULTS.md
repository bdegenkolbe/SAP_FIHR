# Live-Verifikationsergebnisse (Runde 1, remote) — CliniBots Patient Insight

> **STATUS: ARCHIV** — historisches Protokoll (Remote-Runden). Fortlaufendes Log ab R8:
> `VERIFY_LOG_R8-R13.md`.

Stand 15.07.2026, gegen Datenbank `replicate` (MSSQL, read-only). Löst die `# VERIFY`-
Markierungen aus v0.1/v0.2 auf. Alle Abfragen TOP-100-stabil, keine Datenänderung.
Scope bestätigt: **MANDT=100, EINRI=0001** (Live-Stichprobe NPAT).

---

## 1. NPAT (Patientenstammdaten) — verifiziert gegen sapdatasheet + Live

Schlüssel: `MANDT, PATNR` (+ EINRI). **Kein PATID.**

| Feld | Bedeutung | Live-Befund |
|---|---|---|
| GSCHL | Geschlecht | 1=männl (704.566), 2=weibl (758.152), 3=divers (1.520), ' '=unbek (33) |
| GBDAT | Geburtsdatum (DATS 8) | bestätigt |
| NNAME/VNAME | Nach-/Vorname | bestätigt (Klartext) |
| ADRNR | → NADR (Adresse) | FK bestätigt (sapdatasheet) |
| RFPAT | **Merge-Referenz Patient** | 26.388 Patienten mit Merge-Verweis |
| INSID | eind. Versichertennr (eGK) | 798.403 befüllt |
| TODKZ/TODDT | verstorben/Sterbedatum | 32.379 verstorben |
| VIPKZ | VIP-Kennzeichen | 52 |
| RISKF | Risiko-Info vorhanden | 42.176 |
| TESTP | Testpatient | 0 (sauber) |
| STORN | storniert | 30.152 |
| INACT | inaktiv | 1 |

**Fremdschlüssel ausgehend von NPAT (aus sapdatasheet):**
- ADRNR, ADNAG, ADNN1, ADNN2, ADRN2, ADRO2 → **NADR**.ADRNR (Adressen)
- AGNUM (Arbeitgeber), HARNR (Hausarzt), EARNR/UARNR (einweisende Ärzte) → **NGPA**.GPART
- EINRI → TN01 (Einrichtungen), MANDT → T000
- LAND/GLAND/NATIO/AGLAN/ANLA1/ANLA2 → T005 (Länder)
- BLAND → T005S (Bundesland), ANVV1/ANVV2 → TN17B (Verwandtschaft)
- PASSTY → TN17D (Ausweisart), EXTAUFGA → TNWCHEA16, TODUR → TN18A (Todesursache), RACE → TN17R

**Konsequenz Mapper:** GESCHLECHT-Enum {1:male, 2:female, 3:other, ' ':unknown} bestätigt.
RFPAT als Patient.link (type=replaces) mappen. VIPKZ/RISKF/STORN/INACT → Privacy/Gate-Flags.

---

## 2. NAPX-Familie — Fallzusammenführung (das "wilde Konstrukt") — VERSTANDEN

NAPX = Kopf der Fallzusammenführung (Schlüssel `APXNR`, 10). Reine Steuerfelder
(LGTXT, OUTOD, ER/UP/ST-Audit). Die Verknüpfung liegt in **NAPX_FAL**:

| Feld | Bedeutung |
|---|---|
| APXNR | Zusammenführungs-Nummer (Klammer) |
| FALNR | zusammengeführter Fall |
| EINRI | Einrichtung |
| **LEAD** | 'X' = führender Fall der Gruppe, sonst untergeordnet |
| **REASON** | Grund der Zusammenführung |
| STORN | Storno |

**REASON-Codes (Live, ohne Storno) — FPV/KFPV-Fallzusammenführung §2/§3:**
| Code | Bedeutung | Zusammenführungen | Fallzeilen |
|---|---|---:|---:|
| WA | Wiederaufnahme (gleiche Basis-DRG, §2 Abs.1) | 12.173 | 24.611 |
| KO | Komplikation (§2 Abs.3) | 6.346 | 12.833 |
| WP | Wiederaufnahme geplant/gestuft | 1.756 | 4.105 |
| RV | Rückverlegung (§3) | 1.590 | 3.277 |
| FW | Fehlbelegung / Fallwechsel | 126 | 255 |
| **Summe** | | **21.991** | **45.081** |

Muster: je APXNR genau ein LEAD='X' + ein/mehrere untergeordnete Fälle. Ø ~2,05 Fälle
je Gruppe, teils mehr.

**Konsequenz — hochrelevant fürs Graphmodell:** Das ersetzt die heuristische
30-Tage-WIEDERAUFNAHME-Kante aus v0.1 durch die **echte, GKV-rechtlich saubere**
Fallzusammenführung. Neue Graph-Modellierung:
- Knoten `Fallzusammenfuehrung {apxnr, reason}`
- Kante `Fall -[:ZUSAMMENGEFUEHRT_IN {reason, lead}]-> Fallzusammenfuehrung`
- oder direkt: `Fall(lead) -[:FUEHRT_ZUSAMMEN {reason}]-> Fall(untergeordnet)`
Die abgeleitete 30-Tage-Kante bleibt nur als Ergänzung für Fälle OHNE formale
Zusammenführung. NAPX_DIA/ICP/BEW/DRG halten die zusammengeführten Detaildaten
(für die DRG-Neugruppierung des Gesamtfalls) — Tier 2, nur falls DRG-Analytik gewünscht.

---

## 3. NGPA (Geschäftspartner) — Referenz P1 — verifiziert

Schlüssel `MANDT, GPART`. 261.210 Sätze. Typ-Flags (je 'X'):

| Flag | Bedeutung | Anzahl |
|---|---|---:|
| PERS | Person (Arzt/Einweiser) | 236.106 |
| KOSTR | Kostenträger | 17.336 |
| DEBIT | Debitor | 20.519 |
| KRKHS | Krankenhaus | 965 |
| ARBTG | Arbeitgeber | 278 |
| LOEKZ | gelöscht | 6.252 |

Namensfelder: NAME1/2/3, TITEL, VORSW, ADRNR→NADR. GPART_HEX/PARTNER_GUID vorhanden.
**Konsequenz:** NGPA → Practitioner (PERS='X') bzw. Organization (KOSTR/KRKHS='X').
Auflösung der NPAT-FKs HARNR/EARNR/UARNR und der einweisenden Ärzte an Encounter.

---

## 4. NKTR (Kostenträger) — Referenz P1 — verifiziert

Schlüssel `MANDT, KOSTR`. 68 Spalten. Relevante Felder:
- KOSTR (Schlüssel), KTART (Kassenart: BKK/SOZ/ZIV/POL/AOK/EK/…), KTTYP (Typ)
- KSSNM (Kassenname, 120), KKSNR (IK-Nummer), PM301 (§301-Partnernr), EANR
- LOEKZ (gelöscht)

Live-Beispiele: „BKK ESSANELLE HAIR GROUP" (BKK), „SSA Erkrath" (SOZ), „JVA Tonna" (POL).
**Konsequenz:** NKTR → Organization(payer). KTART → CodeSystem Kassenart. Für Coverage
und kostenträgerbezogene Analytik.

---

## 5. NDIA (Diagnosen) — Kernmapper gehärtet

Schlüssel `MANDT, EINRI, FALNR, LFDNR` (+ `LFDBEW` Bewegungsbezug). 72 Spalten.

| Feld | Bedeutung | korrigiert ggü. v0.1 |
|---|---|---|
| **DKEY1** | ICD-10-GM-Kode (60) | war Annahme, jetzt bestätigt |
| DKAT1 | Diagnosekatalog ('56' = ICD-10-GM) | NEU |
| DKEY2/DKAT2 | Sekundär-ICD (Kreuz-Stern) | NEU — für Etiologie/Manifestation |
| DKEY_REF/DKAT_REF | Referenzdiagnose | NEU |
| DITXT | Klartext (100) | war DIATX (falsch) → **DITXT** |
| ALTERN_DIATXT | alternativer Text (264) | NEU |
| DIASI | Diagnosesicherheit (V/A/G/Z) | war Annahme, bestätigt Feldname |
| KHDIA/ENDIA/AFDIA/EWDIA/BHDIA/FHDIA | Haupt-/Entlass-/Aufnahme-/Einweis-/Behandl-/FA-Diagnose-Flags | NEU — Condition.category-Quelle |
| OPDIA/ARDIA/PODIA/TUDIA | OP-/Arbeitsunf-/Postop-/Tumordiagnose | NEU |
| DIADT/DIAZT | Diagnosedatum/-zeit | bestätigt |
| DRG_CATEGORY/DRG_CC/CCL/DRG_RELVANT | DRG-Bezug, Complication/Comorbidity Level | NEU |
| SPERR | Sperre | NEU (Datenschutz) |
| ALPHAID/ORPHACODE | Alpha-ID / Orpha (seltene Erkr.) | NEU |
| STORN | Storno | bestätigt |

**Konsequenz Mapper `map_condition`:** ICD aus DKEY1, System je DKAT1; Kreuz-Stern aus
DKEY2 als zweites coding; Klartext DITXT; Condition.category aus den *DIA-Flags
(HD wenn KHDIA='X'); recordedDate=DIADT; verificationStatus aus STORN.

---

## 6. NICP (Prozeduren/OPS) — Kernmapper gehärtet

Schlüssel `MANDT, LNRIC` (eigene Prozedur-Nr!) + `LFDBEW`. FALNR denormalisiert vorhanden.
46 Spalten.

| Feld | Bedeutung | korrigiert ggü. v0.1 |
|---|---|---|
| **ICPML** | OPS-Kode (20) | war ICPML/ICPK1-Annahme → **ICPML** bestätigt |
| ICPMK | OPS-Katalog ('36' = OPS) | NEU |
| BTEXT | Klartext (100) | NEU |
| BGDOP/ENDOP | OP-Datum von/bis | war ICDAT (falsch) → **BGDOP** |
| BZTOP/EZTOP | OP-Zeit von/bis | NEU |
| ORGFA/ORGPF | durchführende OE (z.B. RADA) | NEU |
| OPART | OP-Art | NEU |
| DRG_RELEVANT/DRG_CATEGORY/CCL | DRG-Bezug | NEU |
| LNRIC | Prozedur-PK | **PK-Korrektur** (war FALNR/LFDNR) |
| LFDBEW | Bewegungsbezug | NEU — verbindet Prozedur mit NBEW |
| STORN | Storno | bestätigt |

**Konsequenz Mapper `map_procedure`:** id aus LNRIC; code=ICPML, system je ICPMK;
performedPeriod aus BGDOP+BZTOP/ENDOP+EZTOP; performer aus ORGFA; text=BTEXT.
Registry-PK für NICP auf `[MANDT, LNRIC]` korrigieren.

---

## 7. NBEW (Bewegungen) — BEWTY-Enum verifiziert

`BEWTY` (Live, ohne Storno):
| Code | Anzahl | Bedeutung (IS-H-Standard) |
|---|---:|---|
| 4 | 22.608.609 | ambulanter Besuch (dominiert; ZNA/Ambulanz) |
| 1 | 1.616.822 | Aufnahme (stationär) |
| 2 | 1.613.511 | Verlegung (intern) |
| 3 | 1.031.768 | Entlassung |
| 7 | 240.862 | Rückkehr aus Beurlaubung |
| 6 | 240.862 | Beurlaubung (6 und 7 exakt gleich → paarweise) |

**Konsequenz Mapper `map_encounter_bewegung`:** BEWEGUNGSART-Enum
{1:Aufnahme, 2:Verlegung, 3:Entlassung, 4:ambulanter Besuch, 6:Beurlaubung,
7:Rückkehr aus Beurlaubung}. BEWTY=1/2/3 = stationäre Encounter-Location-Kette;
BEWTY=4 = ambulanter Encounter (der Massenfall!); 6/7 = Unterbrechung
(FHIR Encounter.status=onleave bzw. Location-Period-Lücke).

---

## 8. Offen geblieben (nächste stabile Läufe)

- N2LABOR: Laborcode-/Wert-/Einheit-Spalten (PARCD/WERT/EINH) noch `# VERIFY`.
- NDOC/N2TEXT: Dokumentkategorien-Verteilung (Arztbrief dünn?) noch offen — separater Lauf.
- NC301D/E/P/R: §301-Segment-Feldkennungen noch `# VERIFY`.
- NORG/NFKL/NBKZ/NKDI: Katalog-Feldkennungen für Referenzschicht noch `# VERIFY`.
- NAPX_DIA/ICP/BEW/DRG: Struktur der zusammengeführten Detaildaten (Tier 2).
Diese sind unkritisch für den v0.1-Kern und werden im nächsten Durchlauf gezogen.
