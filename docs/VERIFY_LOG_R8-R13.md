# Verifikationslog Runden 8–13 — IS-H/i.s.h.med → FHIR R4

Stand: 16.07.2026 · Methode je Tabelle: **erst Schlüsselpfad über sapdatasheet.org, dann
Gegenprüfung gegen die Live-Replicate-DB** (`10.50.8.250 → Replicate.sap`, Spalten-Existenz,
Zeilenzahlen, Uniqueness-Tests der PK-Kandidaten, Wertestichproben). Artefakte: `core.py`
(Mapper), `tables.yaml` (Export-Registry), `normalize.py` (ISO-8601), `test_core.py` /
`test_normalize.py` (Tests, alle grün im Harness bzw. pytest 7/7).

---

## R8 — NICP, TN14-Kataloge, NBAU/Struktur, NDOC/N2TEXT, N1CORDER

**NICP (Prozeduren):** PK `[MANDT, LNRIC]` bestätigt; `LFDBEW` ist FK→NBEW, nicht PK.
Performer-Pfad `ORGFA`=ISH_FACHOE_PROC→NORG bestätigt. Neu erschlossen: `LSLOK`→TN26E
(bodySite), `OPART`→TN14O (category), OP-Uhrzeiten `BZTOP/EZTOP`. `subject` FHIR-konform
auf Patient umgestellt (patnr-Pipeline-Kontext, Fallback Encounter). NICP trägt kein PATNR.

**TN14G/D/H/K:** PKs `[MANDT,BEWTY,POSIT,GRUND]` / `[MANDT,EINRI,ENTZU]` /
`[MANDT,EINRI,BEWTY,REFSRC]` / `[MANDT,EINRI,ARRIVE]`. Wichtig: Die NBEW-Feldnamen
`EZUST/RFSRC/UNFAV/BWGR1+2` im Code sind **korrekt** (Katalogfelder heißen anders, teilen
aber dieselben Datenelemente). TN14K/TN14O/N2DT sind im Haus **nicht repliziert** → Codings
bleiben Rohcode ohne lokale Textauflösung.

**NBAU (Gebäude):** Bug gefunden und behoben — `XKOOR/YKOOR` sind Lageplan-Koordinaten
(NUMC3, replicate: nvarchar(3)), **keine Geo-Position**. `position`-Mapping entfernt;
Adresse nur noch via `ADRNR+ADROB='NBAU'`→NADR. `BAUTY`→TN11B als physicalType.

**NDOC:** Frühere Feldnamen (DOCID/DOCKA/DOCDT/DOCTX) existieren nicht. Real:
PK `[MANDT,DOKAR,DOKNR,DOKVR,DOKTL,LFDDOK]` (DVS-Schlüssel), `PATNR/FALNR/LFDBEW`-FKs,
Autor `MITARB`→NGPA + `ORGDO`→NORG, Kategorie `DTID`→N2DT, Datum `DODAT/DOTIM`.
Mapper komplett neu. **NDOC ist mit 203 DIAS-Referenzen die meistgenutzte Tabelle im Haus.**

**N2TEXT:** PK `[MANDT,DOKAR,DOKNR,DOKVR,DOKTL,DOKTAB,DOKFLD,DOKOCC]`; Volltext in `TXT`
(LCHR 8070) → DuckDB-FTS, nicht FHIR.

**N1CORDER:** PK `[MANDT,CORDERID]` (32-stellige UUID), nicht ORDID. Patientenbezogen,
kein FALNR. Neuer Mapper `map_servicerequest` (Requester ETRGP→NGPA, OE-Fallback).

## R9 — Uniqueness-Tests der offenen PKs (alle live gezählt)

| Tabelle | PK (verifiziert) | Zeilen | Korrektur |
|---|---|---|---|
| NDIP | `[MANDT,DIPNO]` | 694.408 | war [EINRI,FALNR,LFDNR]; Diagnose-Pool |
| NDRG | `[CLIENT,INSTITUTION,PATCASEID,DRG_SEQNO]` | 4,15 Mio | **englische Spalten!** |
| NLEI | `[MANDT,LNRLS]` | ~210 Mio | LNRLS global eindeutig |
| NLEM | `[MANDT,LNRLS]` | 22,45 Mio | Detail zu NLEI |
| NFPZ | `[MANDT,EINRI,FALNR,PERNR,LFDNR]` | 26,76 Mio | **war fälschlich „Coverage" — ist Fall↔Person!** |
| NAPP | `[MANDT,LNRAPP]` | 11,52 Mio | kein APPID |
| N2OPDIAGNOSEN | `[MANDT,EINRI,LNRLS,LFDDIA]` | 747.460 | OP-Leistungsbezug |
| NBKZ | `[MANDT,EINRI,FALNR,LFDNR,BELNR]` | 13,73 Mio | **kein Katalog, transaktional** |
| NFKL | `[...,KLFTYP,KLFART,FKLBDT,FKLBZT]` | 5,72 Mio | **kein FAB-Katalog, Fallverlauf** |
| NKDI | `[MANDT,SPRAS,DKAT,DKEY]` | 390.504 | **ICD-Textkatalog** (nicht Diagnosearten) |
| NPER | `[MANDT,PERNR]` | 236k | kein EINRI |
| NLOC | — | 0 | leer; Ort kommt aus NBEW.ZIMMR/BETT→NBAU |

## R10 — NC301-Familie, DIAS-Objektbaum, base-table-main

**NC301 (These Björn bestätigt):** Die §301-**Meldedaten** liegen in
`NC301S` (Vorgangsindex, 11,58 Mio; O/I, EVENT, SESTA, FALNR/KOSTR, PK `[MANDT,LF301]`) +
`NC301M` (**EDIFACT-Rohnachrichten** in 1024-Byte-Blöcken, 12,79 Mio, PK
`[MANDT,LF301,FOLGENR]`, Rekonstruktion per STRING_AGG über FOLGENR) +
`NC301V` (Ausgangs-) / `NC301W` (Eingangs-Segmente, 892k — **NAD mit Klartext-
Patientendaten → De-ID-pflichtig!**). Peripherie: D/DX (Dateilog), E/I (Fehler), KTR, B
(Config), **P (Datenannahmestellen → Organization)**, CEX; NC301/R/T/TX leer.
Die pauschale Entfernung der Familie aus Runde 2 war zu grob → Registry korrigiert.

**DIAS-Objektbaum** (`TEST_DIAS_Objektbaum.xml`, 4.252 Objekte): Nutzungsranking
NDOC(203) > NBEW(131) > NPAT(35) > NFAL(31) > NDIA(29) > **NFPZ(28)** … Quellsysteme im
Baum: SAP PRD/QTS, **COPRA5+COPRA6** (→ Medikations-/Vitaldaten-Lücke), HCM, PEP, UKL.

**base-table-main** (Haus-ETL „E-Statistik"): (1) SCD2-Historisierung aus __ct-Tabellen +
**CDPOS/CDHDR** (als Tier-3-Provenance-Quellen registriert, live bestätigt); übernehmens-
werte Storno-Gültigkeitssemantik. (2) Hausbewährte Spaltenprojektionen NBEW/NFAL/NDIA/NLEI
(bestätigen unabhängig DIAGW-Befund R4 und LNRLS-Schlüssel R9). (3) **NAPX =
Fallzusammenführung** (nicht Archiv): Kopf `[MANDT,APXNR]`, NAPX_FAL `[MANDT,APXNR,FALNR]`
mit LEAD/REASON, NAPX_BEW mit FALNR_OLD/LFDBEW_OLD→NEW (Splits möglich!).

## R11 — Fachliche Entscheidung: NAPX ist NUR Abrechnung

Einwand Björn: Die zusammengeführten Fälle waren medizinisch real abgeschlossene
Aufenthalte (FPV-Wiederaufnahme). **Modell:**
- Encounter je FALNR bleiben unangetastet (`finished`, echte Zeiträume).
- **KEIN** `Encounter.replaces` (= „ersetzt/fehlerhaft") und **kein** `partOf`.
- Abrechnungsklammer = **ein `Account` je APXNR** (`map_account_napx`, Typ PBILLACCT);
  beteiligte Encounter referenzieren ihn via `Encounter.account`
  (`map_encounter(..., apxnr=)`). LEAD-Fall/REASON als Extensions.
- Auswertungsregel: klinisch je Encounter, DRG/Erlöse je Account (sonst Doppelzählung).

## R12 — NFPZ→participant, NPER→Practitioner, NC301P→Organization

- `map_encounter(..., personal=[NFPZ])` → `Encounter.participant` (FARZT als Rohcode
  `urn:ish:farzt`, live belegt 1/2/5/6/7/9/E; Storno-Zeilen übersprungen).
- `map_practitioner_nper`: NPER hat **keine Namensfelder**; dafür `FIXLANR` → **LANR-
  Identifier** (fhir.de/sid/kbv/lanr), FACHR→qualification, Rollen-Flags.
- `map_organization_das301`: 123 Datenannahmestellen mit IK/Adresse/Kontakt; macht
  `NC301S.DAS301` auflösbar.

## R13 — ISO-8601, NKDI-Texte, NPER↔NGPA-Identität

**`normalize.py` (wirkungsvollster offener Punkt seit R7, jetzt geschlossen):**
Pipeline-Schritt **nach** dem Privacy-Shift (der auf rohem DATS rechnet). Rekursiver Walk
über fertige Ressourcen; normalisiert nur bekannte Datumsfelder (nie identifier/codes):
`20240115`→`2024-01-15`, `20240115T081500`→`2024-01-15T08:15:00+01:00` (Europe/Berlin,
DST-korrekt), SAP-`24:00:00`→`23:59:59`, ISO ohne Offset→Offset ergänzt. Unplausibles
(`00000000`, 30.02., Jahr<1880, `99991231`) und Teilpräzision (`1957` aus Pseudonymisierung)
bleiben unangetastet — kein Datenverlust. pytest 7/7 grün.

**NKDI-Kodetexte:** `map_condition(..., kodetext={'56|J36': 'Peritonsillarabszess', …})`
→ `coding.display` + `code.text`-Fallback wenn DITXT leer (DITXT behält Vorrang).
Live bestätigt: Text in `DTEXT1`, SPRAS='D'.

**NPER↔NGPA (wichtigster R13-Befund):** `NGPA.GPART == NPER.PERNR` für **alle 236.114**
Personen (PERS='X') — dieselbe Person unter demselben Schlüssel, 1:1. `PNUMB` ist NICHT
der Link (569 belegt, 0 Treffer). Konsequenz: das in R12 eingeführte getrennte ID-Schema
`PractitionerNper` hätte Dubletten **erzeugt** → zurückgebaut auf das gemeinsame Schema
`Practitioner`. NFPZ-participant, NPAT.generalPractitioner, NGPA- und NPER-Mapper treffen
jetzt dieselbe Ressource; Pipeline mergt NGPA-Anteil (Name/Titel/IK) + NPER-Anteil
(LANR/FACHR/Rollen).

## R14 — Vollinventur aller N*-Tabellen (127 befüllte)

Neue FHIR-relevante Funde (alle Spalten live geprüft): **N1LSTEAM** (12,63 Mio — OP-Team:
wer hat operiert), **NFFZ** (1,90 Mio — klinische Fall↔Fall-Verknüpfung, Gegenstück zur
NAPX-Abrechnungsklammer), Coverage-Familie **NVVP/NVVF/NPIR/NCIR/NKSD** (NVVP mit 295k
Versichertennummern!), **NKBVLANR/NBSNR** (LANR-/BSNR-Historien; PHYSNO=GPART zu 99,8 %),
**N1VKG** (Vorgangsklammer, löst VKGID aus NDIP/N1COMPA auf). Als Nur-Analytik eingeordnet:
NLCO (72,4 Mio), NLKZ (64 Mio), NLLZ, N1LSSTZ, NTMN, NPAE, NDOC_ZNA/NDOCSTORNO, N1FAT u.a.
**NSHIFT_ID geklärt** (Stichprobe): produktives Umhänge-Protokoll — 4,47 Mio Fall-, 3,71 Mio
Bewegungs-, 2,63 Mio Leistungs-Umhängungen (SOURCE→DEST). Aktuelle Tabellen = DEST-Stand;
relevant für Provenance und Abgleich historischer §301-Meldungen, nicht für laufende Joins.

## R15 — OP-Team, Fallbezüge, Versichertennummer

- **N1LSTEAM → Procedure.performer:** VORGANG-Codes live entschlüsselt (OPT1=Operateur,
  ASS1-4, ANA*/ANS*, INS1, SPR1, HEB, GAST; STATUS F=fixiert). `map_procedure(..., team=)`
  ergänzt individuelle Personen (gemeinsames GPART-Schema R13) zur OE. Kuratierte
  Display-Map `OP_VORGANG`. VERIFY (Lastfenster): Join NICP↔N1LSTEAM — `NICP.LNRLM` ist
  **leer** (0/10,3 Mio); erwarteter Pfad NICP[FALNR,EINRI,LFDBEW]→NLEI→LNRLS (Online-Join
  timeoutet auf 210 Mio).
- **NFFZ-REFA live verteilt:** Q↔Q 1,74 Mio (Deutung offen), P↔B 88k (Patient↔Begleit-
  person), **M↔N 54k = Mutter↔Neugeborenes (gesichert via NGEB-Größenordnung 61k)**,
  T↔T 16k, S↔S 3,6k. `map_encounter(..., verknuepfungen=)` leitet ALLE Bezüge verlustfrei
  als Extension `urn:ish:fallbezug` aus (Partner-Referenz + Rollencodes, Display nur für
  gesicherte Codes). Kein partOf/replaces — Konsistenz mit R11.
- **NVVP → Coverage:** `map_coverage(..., vvp=)` setzt `subscriberId` (KVNR-Kandidat VERNR,
  **gehasht via priv.hash_id** sobald priv aktiv; roh nur im Klarbetrieb) + MGART-Extension.

## R16 — Befüllungs-Audit der gemappten Felder (Antwort auf „schaust du in die Daten?")

Systematischer Fill-Rate-Scan über die im Mapper verwendeten Felder. Ergebnisse:

| Tabelle.Feld | Befüllung | Konsequenz |
|---|---|---|
| **NFAL.ENDDT = 0101-01-01** | **2,21 Mio (23 %!)** | **MAPPER-BUG GEFUNDEN+GEFIXT:** Qlik lädt SAP-Leerdatum als 0101-01-01 → das sind OFFENE Fälle. Neu: `_echtes_datum`-Sentinel (Jahr<1901 od. ≥9999 → None), `status=in-progress`, kein `period.end`. Auch in map_coverage. |
| NFAL.FACHR / ENDTYP | 0 / 0 | tote Quellen (yaml-Notes korrigiert) |
| NBEW.UNFAV | 0 | TN14K-admitSource-Fallback ist hier toter Code (bleibt für andere Häuser) |
| **NBEW.VGNREF / NFGREF** | **0 / 0** | Bewegungskette NICHT gepflegt → Kette per `ORDER BY BWIDT/BWIZT` je FALNR ableiten, nicht über Referenzfelder |
| NBEW.FACHR | 5.676 (0,02 %) | serviceType aus NBEW praktisch leer |
| NBEW.EZUST / RFSRC / BWGR1 | 1,53 / 1,88 / 3,39 Mio | plausibel (Aufnahme-/Entlassbewegungen) — hospitalization funktioniert |
| NBEW.ZIMMR / BETT | 13,3 Mio (47 %) / 2,68 Mio | Location-Referenzen gut nutzbar |
| NICP.OPART | **0** | Procedure.category hier toter Code (defensiv: wird nur gesetzt wenn befüllt) |
| NICP.LSLOK | 1,36 Mio (13 %) | bodySite teilbefüllt — ok |
| **NICP.LFDBEW** | **2,32 Mio (22,5 %)** | der NICP↔NLEI↔N1LSTEAM-Join über die Bewegung deckt nur ~22 % — OP-Team-Anbindung braucht ggf. Alternativpfad (z. B. über N2OPDIAGNOSEN.LNRLS/FALNR+Datum) |
| NICP.BZTOP / ORGPF / BTEXT | 78 % / 74 % / 54 % | gut |
| N1CORDER.ETRGP/ORDDEP/CORDTITLE/PATNR | 97–100 % | Mapper voll trägt |
| N1CORDER.FRAGE | 46 % | ok |

Methodik-Merksatz bestätigt: Schema-Wahrheit ≠ Daten-Wahrheit. Jede Mapper-Quelle braucht
den Dreiklang sapdatasheet → Spalten-Existenz → **Befüllung/Inhalt**.

---

## R17 — DIAS-Abdeckungs-Kandidaten (9x Dreiklang) + automatisierter DIAS-Diff

**Anlass:** Live-DB (`higl-main`) wieder erreichbar (VPN); Abarbeitung der 9 offenen
`# VERIFY`-PKs aus der GESAMTREVIEW-§2.2-Ergänzung + Backlog-Punkt 3 (DIAS-Diff
automatisieren). Alle Prüfungen read-only, Schreibzugriff dreifach ausgeschlossen
(Environment `readonly:true` + Tool-Level-Guard vor jeder DB-Verbindung + Script-Flag).

**Katalogtexte (TN14U/TN14W/TN24T):**
- **TN14U** (Bewegungsart-Texte): PK `[MANDT,EINRI,BEWTY,BWART]` bestätigt, 82 Zeilen,
  100 % eindeutig. `SPRAS` existiert, Haus ist aber einsprachig (`D`) → Uniqueness
  unberührt. BWART-Beispiele bestätigt: `AO`=amb. Operation (BEWTY=4), `VB`=vorstationär
  (BEWTY=1 UND 4, je nach Aufnahme-/Fallart-Kontext).
- **TN14W** (Entlassungszustand-Texte): **Registry-Tippfehler korrigiert** — Spalte heißt
  `ENTZU`, nicht `ENTLZ` (existiert nicht!). PK `[MANDT,EINRI,ENTZU]`, nur 3 Zeilen
  (AF/AU/KA = Arbeitsfähig/-unfähig/keine Angabe — Arbeitsfähigkeits-Status, kein
  allgemeiner Entlassungsgrund). Zusatzfund: `TN14D` teilt dieselbe Spalte `ENTZU` ohne
  Textspalte = Customizing-Gültigkeitstabelle je Einrichtung; TN14W liefert die Texte.
- **TN24T** (Behandlungskategorie-Texte): PK `[MANDT,BEKAT]` bestätigt, 140 Zeilen,
  100 % eindeutig (`EINRI` existiert, aber nicht zur Eindeutigkeit nötig). `BLTXT`
  (30 Zeichen) = Langtext bestätigt. Katalog enthält u. a. ASV-Verträge mit
  Partnerklinik-Namen im Klartext (Institutions-, keine Patientendaten).

**NAPX-Peripherie (NAPX_BEW/DIA/ICP/DRG) — alle vier bestätigt/korrigiert:**
- **NAPX_BEW**: PK `[MANDT,APXNR,LFDBEW_NEW]` — 612.532 Zeilen, 100 % eindeutig. Der in
  GESAMTREVIEW vermerkte „Split-Verdacht" bestätigt sich **nicht**: keine Duplikate.
  `STORN='X'` bei 25,9 % (158.854 Zeilen).
- **NAPX_DIA**: PK `[MANDT,APXNR,LFDNR_NEW]` — 547.765 Zeilen, 100 % eindeutig.
- **NAPX_ICP**: PK `[MANDT,APXNR,LNRIC]` — 415.734 Zeilen, 100 % eindeutig.
- **NAPX_DRG**: **PK-Korrektur** — `[MANDT,APXNR]` allein ist NICHT eindeutig (nur 28.755
  von 35.849 Zeilen distinct). Richtige PK: `[MANDT,APXNR,DRG_SEQNO]` (dann 100 %
  eindeutig) — mehrere DRG-Regruppierungen je Zusammenführung möglich.
  `CANCEL_FLAG='X'` bei 38,6 % (13.851/35.849), konsistent mit Storno-Neugruppierung.

**NTMN (Termine, Appointment-Kandidat):** PK `[MANDT,TMNID]` bestätigt — 11.527.423
Zeilen (exakt die dokumentierte „11,5 Mio"-Schätzung), 100 % eindeutig, `EINRI` nicht
zur Eindeutigkeit nötig. Privacy-konformer Fill-Audit (nur Fill-Rate, kein Klartext):
PATNR 85,9 %, FALNR 66,8 %, BEKAT 35,8 % (→ TN24T), STORN='X' 16,7 %. **Wichtig:**
NNAME/VNAME zu 7,6 % befüllt (Termine ohne PATNR-Link, z. B. externe Zuweisungen) —
diese Felder sind personenidentifizierend und MÜSSEN durch `privacy.py` laufen, dürfen
nie roh exportiert werden; ebenso TELF1 (9,4 %) und EMAIL (0,06 %). Tote Felder in
diesem Haus: `FATYP` (>99,999 % leer), `NOTI_STATUS` (100 % leer). Datums-Sentinel-
Ausreißer: `TMNDT`-Maximum ist `3007-03-14` (kein Standard-`9999-12-31` — separat in
`normalize.py` abfangen, falls NTMN gemappt wird).

**TNDRG — vollständige Neudeutung:** Die Registry-Annahme „DRG-Katalog, löst NDRG-Codes
auf" ist **widerlegt** — die Tabelle hat **gar keine DRG-Spalte**. Tatsächlich:
Landesbasisfallwert(LBFW)-Historie je Gültigkeitsperiode (`BEGDT/ENDDT`, 48 Zeilen,
2002 bis heute, `BASER` in EUR, `WAERS`, `CAREVAL`). PK `[MANDT,EINRI,ENDDT]`, 100 %
eindeutig. Dient der Euro-Umrechnung von `COST_WEIGHT` (aus NAPX_DRG) im
base-table-main-Erlösstrang, nicht der Code-Textauflösung — DRG-Codes (z. B. „F14A")
bleiben Rohcode, kein Textkatalog im Haus gefunden (Verlustfreiheits-Prinzip bestätigt).

**Neufund bei der TNDRG-Recherche:** `sap.ZNRKT_DRG` (147 Spalten, 193.243 Zeilen) —
bislang unerfasste Haus-Z-Tabelle für die vollständige Erlös-Nachrechnung je
Fall+Kostenträger über 6 parallele Sichten (`_ISH/_KK/_MDK/_MDE/_ANF/_RKT` =
i.s.h.med/Krankenkasse/MDK-Prüfung/MDE/Anforderung/Rechnung). PK-Kandidat
`[MANDT,EINRI,FALNR,KOSTR,LFDNR]` — noch NICHT Dreiklang-geprüft.

**DIAS-Abdeckungsdiff automatisiert (Backlog #3):** `legacy/dias/TEST_DIAS_Objektbaum.zip`
entpackt (SOAP/CLR-serialisiert, ~1 Mio Zeilen; SQL-Text liegt als Klartext-Token im
Fließtext, nicht in eigenen Tags). Methode: Regex-Extraktion aller `N*/TN*/ZN*/HRP*`-
Wortgrenzen-Tokens, Häufigkeit gezählt — reproduziert das dokumentierte Ranking exakt
(NBEW 131, NPAT 35 — Treffer bestätigt die Methode). Rauschen (SQL-Keywords, deutsche
Füllwörter, Spaltennamen) gefiltert, verbleibende Kandidaten gegen
`Replicate.INFORMATION_SCHEMA.TABLES` live verifiziert (Text-Wahrheit ≠ Schema-Wahrheit).
**Ergebnis: 85 live bestätigte Tabellenreferenzen im DIAS-Baum, davon 42 OHNE
Registry-Eintrag.** Vier waren als Freitext-Kommentar aus der R14-Vollinventur bereits
bekannt (N2ANKER, NPAP, NOEK, NTPK+NTPT); 38 sind echte Erstfunde — darunter die
komplette `ZNRKT_*`-Familie (13 Tabellen neben ZNRKT_DRG, größte `NLCO` mit 72,4 Mio
Zeilen als eigenständige Tabelle außerhalb der ZNRKT-Familie) und mehrere kleine
Kataloge (TN10B/S, TN11C/P, TN14B, TN15S, TN17U/18U, TN40B, TNK01, TNKFA). Alle 42 als
Status `entdeckt` in `tables.yaml` (Block „R17 DIAS-Diff-Neufunde") mit live
bestätigter Zeilenzahl (sys.partitions) dokumentiert — PK-Uniqueness und Fill-Audit
stehen für jede einzeln noch aus, bevor sie gemappt oder in den Analytik-Pfad
übernommen werden dürfen. Methode ist in `Analyse_Datenbank.md` §5 als reproduzierbares
Rezept festgehalten (für künftige Neuläufe nach Objektbaum-Updates).

---

## Offene Punkte (Stand R17)

1. **Pipeline-Integration:** `normalize_resource()` nach priv.shift in ndjson.py einhängen;
   NAPX_FAL-Lookup (FALNR→APXNR) und NFPZ-/NKDI-Lookups als Broadcast-Joins.
2. **NGPA+NPER-Merge** in der Ausleitung (gleiche ID, Attribute vereinigen).
3. **MedicationAdministration/Vitalwerte:** nur via COPRA5/6 (im DIAS-Baum als Quelle
   vorhanden) oder i.s.h.med-Parametrik (N2ANKER/N2PMDETEXT).
4. **HRP-Schema** bewusst ausgeklammert (Anweisung Björn R10).
5. Rest-`# VERIFY` in tables.yaml: NAPX-Peripherie-Reihenfolgen, NC301V-Feinschlüssel,
   nicht-replizierte Kataloge (TN26B/D, TN14K/O, N2DT), NLOC (leer) — alle niedrigprior.
6. **De-ID-Pflicht** bei NC301M/W (EDIFACT-Klartext, NAD-Segmente) vor jeder Ausleitung.
7. **NEU R17:** 42 DIAS-genutzte Tabellen ohne Registry-Eintrag (Status `entdeckt`,
   siehe `tables.yaml` Block „R17 DIAS-Diff-Neufunde") — vor jeder Nutzung vollen
   Dreiklang fahren. Priorität nach Zeilenzahl/DIAS-Häufigkeit: ZNRKT_*-Familie
   (Erlös-Nachrechnung, direkt an ZNRKT_DRG/TNDRG/NAPX_DRG anschließend), danach
   NLCO/N1COMPA/NTSP/NCIR/N1APCN (großvolumig, Domäne noch unklar).
8. **ZNRKT_DRG** (147 Spalten, 193.243 Zeilen) noch nicht Dreiklang-geprüft.
