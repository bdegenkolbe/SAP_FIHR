# Analyse_Datenbank.md — Vorgehenskonzept SAP IS-H/i.s.h.med → FHIR/Analytik
*(CliniBots Patient Insight — verbindliche Methode; Dokumentenlandkarte: `INDEX.md`)*

**Zweck:** Verbindliche Arbeitsanweisung für Claude Code (und jede weitere Session) zur
systematischen Erschließung der Replicate-Datenbank. Dieses Dokument definiert METHODE,
REIHENFOLGE und REGELN. Der jeweils aktuelle Erkenntnisstand steht in `tables.yaml`
(Export-Registry) und `VERIFY_LOG_R8-R13.md` (Rundenprotokoll) — beide im selben Ordner.

**Umgebung:**
- Quell-DB: MSSQL `10.50.8.250` (Environment `higl-main`, read-only), DB `Replicate`,
  Schema `sap` (IS-H/i.s.h.med via Qlik Replicate), daneben `hrp` (ausgeklammert),
  `Replicate_QTS` (Testsystem), `Analysen` (Haus-ETL-Ziel, E-Statistik).
- Konstanten (live verifiziert): `MANDT='100'`, `EINRI='0001'`.
- Change-Tables: `<TABELLE>__ct` (Qlik CDC, Spalte `header__change_seq`); `__ct__bak` ignorieren.
- Artefakte im Repo: `tables.yaml`, `core.py` (Mapper), `normalize.py` (ISO-8601),
  `test_core.py`, `test_normalize.py`, `VERIFY_LOG_R8-R13.md`.

---

## 1. Leitprinzip: Der Dreiklang (nicht verhandelbar)

Jede Tabelle/jedes Feld durchläuft DREI Prüfstufen, bevor es gemappt oder dokumentiert wird.
Schema-Wahrheit ≠ Daten-Wahrheit — beide Fehlerklassen sind real aufgetreten:

1. **Wörterbuch (sapdatasheet.org):** offizieller Schlüssel, Datenelemente, Domänen,
   Fremdschlüssel, Prüftabellen. → Abschnitt 3 (Analyseplan).
2. **Schema (Replicate live):** Existiert die Tabelle? Existieren die Spalten wirklich
   (Qlik lädt teils englische Namen — NDRG: `CLIENT/INSTITUTION/PATCASEID`!)?
   PK-Kandidat per Uniqueness-Test bestätigen.
3. **Daten (Replicate live):** Befüllungsraten, Werteverteilungen, Stichproben-Inhalte.
   Gefundene Klassen von Datenfallen (alle real):
   - Feld existiert, ist aber IMMER leer (NICP.OPART, NBEW.UNFAV/VGNREF/NFGREF,
     NFAL.FACHR/ENDTYP, NDIA.DIASI → Wahrheit lag in DIAGW).
   - Sentinel-Werte: SAP-Leerdatum `00000000` kommt via Qlik als `0101-01-01` an
     (NFAL.ENDDT: 23 % aller Fälle = OFFENE Fälle!), SAP-Unendlich `9999-12-31`.
   - Feld semantisch anders als der Name suggeriert (NBAU.XKOOR/YKOOR = Lageplan,
     nicht Geo; NFPZ = Personen, nicht Versicherung; NAPX = Fallzusammenführung,
     nicht Archiv; NKDI = ICD-Texte, nicht Diagnosearten).
   - Tabelle im Standard vorgesehen, im Haus ungenutzt (N1MEORDER = 0 Zeilen → Medikation
     läuft über COPRA; NLOC = 0 Zeilen).

---

## 2. NPAT-zentrierte Erschließung (Breitensuche über Referenzen)

**Algorithmus:** Ausgehend von `NPAT` werden ALLE erreichbaren Tabellen inkl. sämtlicher
Referenz-/Katalogtabellen erarbeitet — als Breitensuche über den Fremdschlüsselgraphen.

```
Warteschlange W = [NPAT]
Erledigt      E = {Tabellen mit Status 'auditiert' in tables.yaml}
solange W nicht leer:
    T = W.pop()
    1. sapdatasheet-Analyse von T (Abschnitt 3) → PK, FKs, Prüftabellen, Datenelemente
    2. Schema-Check live (Spalten, PK-Uniqueness, Zeilenzahl)
    3. Datenaudit live (Abschnitt 4: Top 1000 + Fill-Rates)
    4. Ergebnis in tables.yaml eintragen (Status, PK 'verifiziert Rx', Befunde in notes)
    5. Alle neu entdeckten Zieltabellen (FKs, Prüftabellen, *T-Texttabellen,
       fachlich erkannte Partner wie __ct, _ZNA-, APX-, SHIFT-Varianten) → W,
       sofern nicht in E
Priorisierung in W: (a) Tier-1-Kern, (b) von DIAS genutzt (Abschnitt 5),
(c) Zeilenzahl/Nutzungsgrad, (d) Kataloge zuletzt (billig, cdc:full)
```

**Statusmodell je Tabelle** (in `tables.yaml` über die notes-Konvention geführt):
`entdeckt → schema-verifiziert (PK live) → daten-auditiert (Fill/Sample) → gemappt (Mapper+Test) | nur-analytik | leer/ausgeschlossen`

**Bereits erledigt (Stand R16):** ~76 Tabellen in `tables.yaml`, davon Kern (NPAT, NFAL,
NBEW, NDIA, NICP, N2LABOR/001, NDOC, N2TEXT, NORG, NADR, NGPA, NKTR, NKSK, NRSF, NBAU,
NPOB, TN11H/O, N1CORDER, NAPX-Familie, NFPZ, NPER, NC301-Familie, N1LSTEAM, NFFZ, NVVP…)
mit verifizierten PKs und Datenaudits. Vollinventur: 127 befüllte N*-Tabellen gelistet.
HRP-Schema auf Anweisung ausgeklammert.

---

## 3. Analyseplan sapdatasheet.org (strukturiert)

**URL-Muster:**
| Objekt | URL |
|---|---|
| Tabelle | `https://www.sapdatasheet.org/abap/tabl/<tabelle_klein>.html` |
| Feld | `.../abap/tabl/<tabelle>-<feld>.html` |
| Datenelement | `.../abap/dtel/<datenelement_klein>.html` |
| Domäne (inkl. Festwerte!) | `.../abap/doma/<domaene_klein>.html` |

**Je Tabelle extrahieren (in dieser Reihenfolge):**
1. **Components-Tabelle:** Feldliste mit Datenelement + Domäne + Länge + Prüftabelle.
   Achtung: die „Key"-Spalte ist im HTML oft leer gerendert → PK NICHT von dort ablesen,
   sondern (a) aus den ersten Feldern + Domänenlogik ableiten und (b) IMMER live per
   Uniqueness-Test bestätigen (`COUNT(*) vs COUNT(DISTINCT CONCAT(pk-felder))`).
2. **Foreign-Keys-Abschnitt:** Quelle→Zieltabelle-Paare (z. B. NICP: EINRI→TN01,
   FALNR→NFAL, ICPMK→TNK01, ICPML→NTPK, LFDBEW→NBEW, LSLOK→TN26E, OPART→TN14O).
   Jede Zieltabelle wandert in die Warteschlange (Abschnitt 2).
3. **Datenelement-Kurztexte:** entscheiden Deutungskonflikte (Beispiele: PODIA =
   „Preoperative Diagnosis" nicht postoperativ; ORGFA in NICP = ISH_FACHOE_PROC;
   RI_XKOOR = „Coordinate in Overview Graphic" ⇒ kein Geo-Mapping).
4. **Gleiche Datenelemente = gleiche Semantik über Tabellen hinweg** (EZUST↔ENTZU,
   RFSRC↔REFSRC, UNFAV↔ARRIVE teilen je ein Datenelement — Katalogfelder heißen anders
   als Transaktionsfelder, das ist normal).

**Grenzen von sapdatasheet:** zeigt SAP-Standard, nicht Haus-Customizing und nicht die
Befüllung. Delivery Class C (Customizing) heißt: Werte sind hausspezifisch → immer
live nachschlagen. Fehlende Kataloge im Replicate (TN14K, TN14O, N2DT, TN26B/D) sind
dokumentiert; ggf. Replikation beantragen.

---

## 4. Datenprüfung (echte Daten, Top 1000, Verkryptung)

**Standard-Audit je Tabelle (read-only, `higl-main`):**
```sql
-- 1) Zeilenzahl (billig, ueber Partitionsstatistik):
SELECT SUM(p.rows) FROM Replicate.sys.tables t
JOIN Replicate.sys.schemas s ON s.schema_id=t.schema_id
JOIN Replicate.sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
WHERE s.name='sap' AND t.name='<T>';

-- 2) PK-Uniqueness:
SELECT COUNT(*) n, COUNT(DISTINCT CONCAT(<PK-Felder mit '|'>)) d FROM Replicate.sap.<T>;

-- 3) Fill-Rate aller Mapper-Kandidatenfelder (EIN Scan, CASE WHEN ... SUM):
SELECT COUNT(*) n, SUM(CASE WHEN LTRIM(RTRIM(ISNULL(F,'')))<>'' AND F NOT IN
  ('0','00000000','0000000000') THEN 1 ELSE 0 END) f_belegt, ... FROM Replicate.sap.<T>;

-- 4) Werteverteilung kodierter Felder:
SELECT TOP 20 <F>, COUNT(*) FROM Replicate.sap.<T> GROUP BY <F> ORDER BY COUNT(*) DESC;

-- 5) Inhalts-Stichprobe: TOP 1000 (nie mehr), nur benoetigte Spalten projizieren.
```

**Verkryptungsregel (VERBINDLICH) — personenidentifizierende Varchar-Felder werden nie
im Klartext selektiert, angezeigt oder protokolliert.** In Stichproben stattdessen:
```sql
-- deterministisch verkryptet (vergleichbar, nicht rueckrechenbar):
CONVERT(varchar(16), HASHBYTES('SHA2_256', CONCAT('<SALT>', <feld>)), 2) AS <feld>_h
-- oder nur Struktur pruefen:
LEN(<feld>), LEFT(<feld>,1)  -- Laenge/Initial statt Inhalt
```
**Verkryptungspflichtige Felder (Liste erweitern, nie kürzen):**
NPAT.NNAME/VNAME/GBNAM + Adresse (STRAS/ORT/PSTLZ/TELF*), NGPA.NAME1/NAME2/KNAME +
Adresse, NADR/NADR2 komplett, NVVP.VERNN/VERVN/VERGE + **VERNR (KVNR!)**, NEHC.EGK_ICCSN,
NC301M.MAIL und NC301V/W.SGMINH (EDIFACT enthält NAD-Segmente mit Namen/Geburtsdatum/
Adresse im Klartext!), NFAL/NBEW/NRSF.KZTXT (Freitext kann Namen enthalten), N1CORDER.
FRAGE/KANAM (Freitext). Geburtsdaten (GBDAT) in Stichproben nur als Jahr.
Zahlschlüssel (PATNR, FALNR, GPART, PERNR…) sind Pseudonym-IDs und dürfen roh erscheinen;
in der FHIR-Ausleitung greift zusätzlich `privacy.py` (Pseudonymisierung + Date-Shift +
`hash_id` für KVNR).

**Massentabellen-Regel:** Online-Aggregate über >50 Mio Zeilen (NLEI 210 Mio,
N2LABOR001 322 Mio) timeouten über MCP → Fill-Audits dafür ins Lastfenster/Batch
verlagern; online nur TOP-Stichproben mit Schlüsselfilter.

---

## 5. DIAS-Objektbaum = Abdeckungs-SOLL

`TEST_DIAS_Objektbaum.xml` (Baum „D_1 DIAS ANALYTICS", 4.252 Objekte: 2.451 Sichten,
753 Tabellen, 438 Funktionen) dokumentiert, was das Haus HEUTE verarbeitet.

**Verbindlichkeit:** Alle dort verarbeiteten Objekte müssen auch künftig versorgt werden —
**auch die Nicht-FHIR-Objekte.** Konsequenz für die Zielarchitektur: zwei Abnehmer-Pfade
aus derselben Bronze-Schicht:
- **FHIR-Pfad** (klinischer Kern → NDJSON/Server), Registry-Feld `fhir:` in tables.yaml.
- **Analytik-Pfad** (`fhir: null`, Tier 2/3): E-Statistik, Erlöse (NLEI/NLCO/NLKZ/NDRG),
  §301 (NC301*), Termine (NAPP/NTMN), Tarifkataloge (NTPK*) usw.

**Abdeckungs-Controlling (Aufgabe für Claude Code):**
1. Aus dem XML alle SAP-Tabellenreferenzen extrahieren (Regex über SQL-Inhalte der
   Sichten; bekanntes Ranking: NDOC 203, NBEW 131, NPAT 35, NFAL 31, NDIA 29, NFPZ 28,
   NBAU/TN11* 31, NGPA 15, NAPP 14, NLEI/NICP 11, NC301S 9, NDRG 7 …).
2. Gegen `tables.yaml` diffen → jede DIAS-genutzte Tabelle ohne Registry-Eintrag ist
   eine Lücke und wandert in die Warteschlange (Abschnitt 2).
3. Nicht-SAP-Quellen im Baum (COPRA5/COPRA6, HCM, PEP, UKL-Daten, Referenzdaten) als
   eigene Quellsysteme führen — COPRA ist der Schlüssel für Medikation/Vitalwerte
   (IS-H-seitig leer, s. N1MEORDER).

**Automatisierte Diff-Methode (R17, reproduzierbar):**
```
1. legacy/dias/TEST_DIAS_Objektbaum.zip entpacken -> TEST_DIAS_Objektbaum.xml (SOAP/CLR-
   serialisiert, ~1 Mio Zeilen). SQL-Text der Sichten liegt NICHT in eigenen <m_SQL>-Tags,
   sondern als Klartext-Tokens im Fliesstext (Tabellennamen ungeschema't, ohne 'sap.'-Praefix).
2. Kandidaten extrahieren: grep -oE '\b(N[A-Z0-9]{2,8}|TN[A-Z0-9]{2,8}|ZN[A-Z0-9_]{2,10}|
   HRP[0-9]{3,6})\b' TEST_DIAS_Objektbaum.xml | sort | uniq -c | sort -rn
   -> reproduziert das dokumentierte Ranking EXAKT (NDOC 203/201 diff durch __ct-Varianten,
   NBEW 131, NPAT 35 - Treffer bestaetigt die Methode).
3. Rauschen filtern: SQL-Keywords (NULL/NOT/NUMERIC/NVARCHAR/NEXT/NOCOUNT/NEWID/NULLIF),
   deutsche Fuellwoerter (NICHT/NUR/NEU/NEIN), Spaltennamen (NAME1-4/NAMS/NOTKZ/NPKZ/
   NACH*-Familie = Adressfelder, NWAT*-Familie = Flag-Spalten) manuell aus der Trefferliste
   entfernen.
4. VERBINDLICH: verbleibende Kandidaten NICHT aus der Wortliste als "existent" werten
   (Text-Wahrheit ist NICHT Schema-Wahrheit!) -> gegen Replicate.INFORMATION_SCHEMA.TABLES
   (schema='sap') pruefen. Nur live bestaetigte Treffer sind echte Tabellenreferenzen.
5. Gegen tables.yaml-Tabellennamen diffen (comm/Mengendifferenz) -> Luecken-Liste.
```
**R17-Ergebnis:** 85 live bestaetigte SAP-Tabellenreferenzen im DIAS-Baum, davon 43 bereits
in tables.yaml, **42 Luecken** (siehe `config/tables.yaml` Block "R17 DIAS-Diff-Neufunde").
Vier davon (N2ANKER, NPAP, NOEK, NTPK/NTPT) waren als informeller Freitext-Kommentar aus der
R14-Vollinventur bereits vermerkt; 38 sind echte Erstfunde, darunter die komplette
`ZNRKT_*`-Tabellenfamilie (13 Tabellen, Erlös-Nachrechnung, größte NLCO mit 72,4 Mio Zeilen)
und mehrere kleine Kataloge (TN10B/S, TN11C/P, TN14B, TN15S, TN17U/18U, TN40B, TNK01, TNKFA).
Alle 42 tragen Status `entdeckt` (Zeilenzahl via sys.partitions, noch KEIN PK-Uniqueness-Test,
noch KEIN Datenaudit) — nächste Session: Dreiklang je Tabelle vor jeder weiteren Nutzung.

---

## 6. base-table-main = historisierte Real-Time-Transformationsstrecke

Der Ordner `base-table-main/` (Stored Procedures, Ziel-DB `Analysen`) ist die produktive
E-Statistik-Aufbereitung. Architektur-Erkenntnisse und verbindliche Übernahmen:

1. **CT-Lücken sind real:** In den Qlik-`__ct`-Daten fehlen gelegentlich Transaktionen.
   **Deshalb MUSS die Historisierung zusätzlich SAP-Änderungsbelege CDPOS/CDHDR nutzen**
   (Parameter `@CDPOS_laden`: 0=nie, 1=bei Änderungen, 2=immer; 161 CDPOS-Referenzen im
   Bestand). CDHDR/CDPOS sind in tables.yaml als Tier-3-Provenance-Quellen registriert.
2. **Trennung Echtzeit vs. Historisierung (Ziel-Design):** Die Skripte laufen teils
   Stunden. Daher entkoppeln:
   - **Echtzeit-Strang:** leichtgewichtig, nur `__ct`-Deltas → aktuelle Zustände
     (für FHIR-NDJSON und Live-Sichten). Kein CDPOS, keine SCD2-Rekonstruktion.
   - **Historisierungs-Strang:** Batch/Lastfenster, `__ct` + CDPOS-Abgleich → SCD2
     (`datensatz_gueltig_von/bis`), Fullload-Zyklen (`@DaysToFullLoad`, `@FullloadYears`).
   Beide Stränge lesen dieselbe Bronze; der FHIR-Pfad hängt NUR am Echtzeit-Strang,
   `Provenance`/Versionierung optional am Historisierungs-Strang.
3. **Übernehmenswerte Semantik** aus den Prozeduren:
   - Storno-Gültigkeit: `@ValidToStorno/@ValidBeforeStorno` (Datensatz endet EINE
     Zeiteinheit vor Storno) — kompatibel zu unserer entered-in-error-Logik.
   - Hausbewährte schmale Projektionen (NBEW/NFAL/NDIA/NLEI-Spaltenlisten in tables.yaml
     §v0.8) als Ausgangspunkt für Export-Projektionen.
   - Fallzusammenführung über NAPX (`UpdateBaseTable_Fallzusammenfuehrung`, inkl.
     tSplit-Logik) — im FHIR-Modell als Account-Klammer umgesetzt (KEIN replaces:
     Zusammenführung ist Abrechnung, die Einzelfälle waren medizinisch real).
   - NSHIFT_ID = produktives Umhänge-Protokoll (SOURCE→DEST für FALNR/LFDBEW/LNRLS)
     → Audit-Trail für historische Abgleiche, nicht für laufende Joins.

---

## 7. FHIR-Ausleitungsregeln (Kurzreferenz, Details in core.py-Docstrings)

- Deterministische IDs: `rid(ns, Typ, MANDT, …)`; EIN Practitioner-Schema für
  GPART==PERNR==PHYSNO (live bewiesen: 236.114 identisch, 99,8 % NKBVLANR).
- Reihenfolge: Mapper (roh) → `privacy` (Shift/Pseudonym/hash_id auf ROH-Werten) →
  `normalize_resource()` (ISO-8601, Europe/Berlin, DST) → NDJSON.
- Sentinels: `_echtes_datum` filtert Jahr<1901 und ≥9999; offene Fälle =
  `status in-progress` ohne `period.end`.
- Medizinische vs. Abrechnungswahrheit strikt trennen (Encounter unangetastet;
  NAPX→Account, NFFZ→Extension `urn:ish:fallbezug`, kein partOf/replaces).
- Nicht auflösbare Kataloge: Rohcode unter `urn:ish:<katalog>` ausleiten, nie raten;
  kuratierte Display-Maps nur bei gesicherter Deutung (OP_VORGANG, FALLBEZUG M/N).
- Verlustfreiheit: Unbekannte Codes/Zeilen nie verwerfen — Rohcode/Extension/Flag.

## 8. Arbeits-Backlog — VERSCHOBEN nach `ROADMAP.md`

> Dieser Abschnitt ist in die einheitliche Roadmap aufgegangen (Mapping dort als
> `[Analyse_DB §8.x]`). Historischer Stand unten unverändert; NICHT mehr hier pflegen.

1. **Pipeline-Integration:** `normalize_resource()` nach priv.shift einhängen; Lookups
   als Broadcast-Joins (NAPX_FAL FALNR→APXNR, NFPZ je Fall, NKDI-Kodetexte, NVVP je
   PATNR+KOSTR, N1LSTEAM je LNRLS); NGPA+NPER-Merge zu EINER Practitioner-Ressource.
2. **Lastfenster-Verifikationen:** NICP↔N1LSTEAM-Joinpfad (LNRLM leer! Kandidat:
   FALNR+EINRI+LFDBEW→NLEI, deckt aber nur 22,5 % — Alternativpfad über
   N2OPDIAGNOSEN.LNRLS prüfen); Fill-Audit NDOC (54 Mio) und N2LABOR-Familie.
3. **DIAS-Abdeckungsdiff** (Abschnitt 5) vollständig automatisieren.
4. **ref_*-Loader** für die 19 replizierten Kataloge (NKDI dominiert mit 390k);
   Rest-Kataloge (TN14K/O, N2DT, TN26B/D) zur Replikation anmelden.
5. **NFFZ-REFA-Katalog** klären (Q/T/S-Deutung), dann ggf. Patient.link für M/N.
6. **Echtzeit-/Historisierungs-Trennung** (Abschnitt 6.2) als Zielarchitektur umsetzen.
7. **COPRA-Schiene** für MedicationRequest/-Administration und Vitalwerte erschließen.
