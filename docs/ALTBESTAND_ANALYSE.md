# Analyse des Altbestands: BaseTable-Ladeprozesse + DIAS-Objektbaum

Stand 15.07.2026 · Quellen: `legacy/base-table/Stored Procedures/` (16 T-SQL-Prozeduren,
~12.600 Zeilen, DB `Analysen` auf dem MSSQL-Server) und `legacy/dias/` (DIAS-ANALYTICS-
Objektbaum, 4.220 Objekte, Index in `legacy/dias/OBJEKTBAUM_INDEX.md`).

**Kernaussage:** Wir übernehmen **keinen Code** aus dem Altbestand (T-SQL-Framework mit
dynamischem SQL, TEMP-Tabellen-Orchestrierung, wöchentlichem Fullload — genau die
Stunden-Läufe, die SAP_FIHR durch Keyset-Backfill + `__ct`-CDC + Compaction ersetzt).
Wir übernehmen aber **die fachliche Semantik**: verifizierte Feldbedeutungen,
Katalogtabellen, Bereinigungsregeln und — über die DIAS-DataMart-Liste — den faktischen
**Anforderungskatalog** der Analytik des Hauses. Drei Enum-Annahmen aus unseren
VERIFY-Runden werden durch den produktiven Altbestand **korrigiert**.

---

## 1. Was der Altbestand ist

### 1.1 BaseTable-Framework (`Analysen.dbo.UpdateBaseTable_*`)
Ein generischer SCD2-Historisierungs-Lader (3.251 Zeilen Engine +
parametrisierte Aufrufe je Fachobjekt):
- Quellen: `replicate.sap.*` (dieselbe Qlik-Replika wie SAP_FIHR) inkl. `__ct`-Tabellen
  **und SAP-Änderungsbelegen (CDPOS/CDHDR)** für die Historisierung.
- Je Datensatz wird eine Gültigkeitshistorie (`Datensatz_gueltig_von/bis`) gebaut,
  mit Heuristiken für fehlende INSERT/UPDATE/DELETE-Ereignisse, Storno-Semantik
  (`ValidToStorno`, STDAT) und Änderungs-Entprellung (`IgnoreChangesWithinTime`).
- Ladeverfahren: automatisch Delta, alle `@DaysToFullLoad=7` Tage ein **Fullload über
  5 Jahre** — die Ursache der stundenlangen Läufe.
- Fachobjekte (Ordner `E-Statistik`): Falldaten, Bewegungen (inkl. Aufenthaltsblock-
  Rechnung), Diagnosen, Patienten, Leistungen (inkl. Tarif-/PEPP-/DRG-Kataloge),
  Fallzusammenführung (NAPX), ISH-Organisation, SETNODE-Hierarchien (SAP-Sets),
  Filtertabelle Fallnummer.
- `ProcStarter` + `Admin_TabTree`: Konfigurations-DB, aus der dynamisches SQL in
  4000-Zeichen-Häppchen zusammengesetzt und `exec`-t wird.

### 1.2 DIAS-Objektbaum („D_1 DIAS ANALYTICS", R4.2_5)
Der Objektbaum des hauseigenen DWH-Werkzeugs: 2.451 Sichten, 753 Tabellen,
224 eindeutige **DataMarts**, tägliche/komplette Aufbereitungs-Sequenzen.
Er dokumentiert, **was das Haus tatsächlich auswertet** (Index:
`legacy/dias/OBJEKTBAUM_INDEX.md`).

---

## 2. Erkenntnisgewinn 1 — Korrekturen an unseren Feldannahmen

Der Altbestand läuft seit Jahren produktiv; wo er unseren VERIFY-Runden widerspricht,
wiegt er schwer. **Konflikte, jetzt in Code/Registry nachgezogen:**

| Feld | Unsere Annahme (VERIFY 1–3) | Altbestand (produktiv) | Entscheidung |
|---|---|---|---|
| NBEW.BEWTY=2 | Verlegung | **Entlassung** (`BEWTY=2 → Bewegung_Entlassung`) | **Altbestand.** Live-Zahlen stützen ihn: 1,617 Mio Aufnahmen (1) ≈ 1,614 Mio (2) — jeder stationäre Fall hat genau eine Entlassung; Verlegungen (3) 1,03 Mio. Enum korrigiert; endgültige Wahrheit = Katalog **TN14T** |
| NBEW.BEWTY=3 | Entlassung | Verlegung | dito |
| NDIA.TUDIA | „Tumordiagnose" | **Todesursache** (`Diagnose_ist_Todesursache`) | **Altbestand** (SAP-Namenskonvention TU=Todesursache; Tumordoku liegt in Credos) |
| NDIA-Sicherheit | DIASI (im Haus leer) | **DIAGW** (`Diagnose_Sicherheit`) | beide Spalten mitnehmen, DIAGW primär |
| NDIA.PODIA | „postoperative Diagnose" | „Präoperativ" | Konflikt offen → `# VERIFY-KONFLIKT`, gegen sapdatasheet auflösen |
| NDIA.ARDIA | Arbeitsunfalldiagnose | „Arbeitsdiagnose" | dito |
| NKDI | „Katalog Diagnosearten" | **ICD-Katalog des Hauses** (DKEY→DTEXT1–4 Klartext, GSCHL-Restriktion, ICD10GM_P301/P295) | **Altbestand** — NKDI ist die Klartext-Quelle für Diagnosen! Registry korrigiert |

**Neue NDIA-Felder aus dem Altbestand** (in `config/columns/NDIA.yaml` ergänzt):
`DIAGW` (Sicherheit), `DTYP1` (Zusatz), `DIALO` (Lokalisation), `DIAPR`
(med. Nebendiagnose), `KZTXT` (Bemerkung), `DIAZT` (Uhrzeit — mit DIADT kombinieren).

**Neue NFAL-Felder** (Falldaten-Prozedur): `STASP` (**Statistiksperre** — muss als
Ausschlussregel in Analytik/MCP!), `FSPER` (Fakturasperre), `ABRKZ` (Abrechnungsstatus
0=nicht/1=zwischen/2=end/3=vorläufig), `BEKAT`→TN24T (Behandlungskategorie), `FATYP`,
`FOREI` (Auslandsfall), `EINZG` (Einzugsgebiet), `TOB`/`MDTOB` (Tage ohne Berechnung),
`MDVSTAT` (MD-Verfahren), `STATU` (I=aktuell/E=abgeschlossen/P=Plan).

**Neue NBEW-Felder** (Bewegungs-Prozedur): `BWGR1`/`BWGR2` (Bewegungsgründe →
TN14R; BEWTY=1 & BWGR1=3 markiert **teilstationäre** Aufnahme; BWGR1 ∈ {01,02,08} =
PrüfVV-relevant), `PLANB`/`BWPDT`/`BWPZT` (Planbewegung), `STATU`. Regeln:
`BWART='VB'` = vorstationär, `BWART='AO'` = AOP (ambulantes Operieren) — beide sind
bei BEWTY=4 **keine** normalen Ambulanzbesuche. **`BWEDT` mit Jahr 9999 = offenes
Ende → NULL**, sonst rechnet jede Verweildauer falsch (in `gold.belegung_oe` +
Mapper berücksichtigt).

## 3. Erkenntnisgewinn 2 — die echten Katalogtabellen

CONCEPT_EXT §2 hat die Referenzschicht auf Verdacht benannt (NBKZ, NFKL …). Der
Altbestand zeigt die **tatsächlich verjointen** Kataloge:

| Katalog | Inhalt | löst auf |
|---|---|---|
| **TN14T** | Bewegungstyp-Texte | NBEW.BEWTY (die autoritative Enum-Quelle!) |
| **TN14R** | Bewegungsgrund-Texte (Schlüssel MANDT+BEWTY+Pos+Grund) | NBEW.BWGR1/BWGR2 |
| **TN14U** | Bewegungsart-Texte | NBEW.BWART |
| **TN14W** | Entlassung-Zustand | Entlassungszustand |
| **TN14V** | Unfallart | NBEW-Unfallkontext |
| **TN14B** | Bewegungsart-Kennzeichen | BWART-Eigenschaften |
| **TN24 / TN24T** | Behandlungskategorie (+Texte) | NFAL.BEKAT |
| **NKDI (+TNK00)** | hauseigener ICD-Katalog mit Klartext | NDIA.DKEY1/DKAT1 |
| **TN10S / TN10B / TN10H** | OE-/Stations-Kataloge | NBEW.ORGFA/ORGPF, NORG |
| **NOEK** | OE↔Kostenstelle | Erlös-/Kostenzuordnung |
| **TNDRG / TNPEPP** | DRG-/PEPP-Kataloge | NDRG, Entgelte |
| **NTPK/NTPKD/NTPT/NTSP/NTST** | Tarif-/Preiskataloge | NLEI-Klartexte (Tier 3) |
| **SETHEADER/SETNODE/SETLEAF** | SAP-Set-Hierarchien (z. B. `CA_FAKU`) | frei definierte Fach-Hierarchien (Tier 3) |

→ in `config/tables.yaml` als Referenzschicht (`cdc: full`, Tier 1) aufgenommen:
TN14T, TN14R, TN14U, TN14W, TN24T, NKDI. Rest dokumentiert, on demand.

## 4. Erkenntnisgewinn 3 — Fallzusammenführung (NAPX) im Detail

Die Prozedur `UpdateBaseTable_Fallzusammenfuehrung` bestätigt VERIFY_RESULTS §2 und
liefert Details, die dort fehlten:

- **REASON-Katalog vollständiger:** neben WA/KO/WP/RV/FW kennt der Altbestand
  `OG` („Wiederaufnahme §2(1) FPV"), `MD` („Wiederaufnahme §2(2) FPV"), und deutet
  `WP`/`RP` als **Psychiatrie/Psychosomatik**-Wiederaufnahme/-Rückverlegung
  (VERIFY_1 hatte WP als „geplant/gestuft"). → Klartexte aus dem Altbestand übernommen.
- **Bereinigungsregel `STDAT<>ERDAT`:** Zusammenführungen, die am Erstellungstag
  wieder storniert wurden, sind Fehleingaben und werden ausgefiltert. → in den
  Graph-Load übernommen.
- **NAPX_BEW/NAPX_DIA/NAPX_ICP** mappen Alt→Neu (`FALNR_OLD/LFDBEW_OLD` →
  `LFDBEW_NEW/LFDNR_NEW`) inkl. DRG-Attributen (`DRG_DIA_SEQNO`, `DRG_CATEGORY`
  S=Neben/P=Haupt, `CCL`). Split-Erkennung: gleiche Alt-Bewegung auf mehrere
  Neu-Bewegungen (Bewegung_Typ_Split37).

→ Graph: Kante `FUEHRT_ZUSAMMEN (Fall→Fall, reason)` aus `bronze_current.napx_fal`
(LEAD='X' als Quelle), die heuristische 30-Tage-`WIEDERAUFNAHME` bleibt als Ergänzung.

## 5. Erkenntnisgewinn 4 — der Anforderungskatalog aus DIAS

Die 224 DataMarts (`legacy/dias/OBJEKTBAUM_INDEX.md`) sind die Ist-Analytik des
Hauses. Für SAP_FIHR heißt das:

**Deckungsgleich mit unserem Kern (Phase 4/5 bestätigt):** DataMart Fall / Patient /
Bewegung / Diagnose / Prozedur / Leistung / DRG, „Erste Bewegung ambulant/stationär",
„Fälle Heute", Mitternachtsstatistik, Betten-/Belegungsstatistik, Kostenträger/
Versichertenverhältnis, Stammdaten (Adressen, Geschäftspartner, Personen, Strukturbaum).

**Bestätigte Zusatzquellen (Registry angepasst):**
- **NC301S wird aktiv ausgewertet** (4 Referenzen) — die pauschale Streichung der
  NC301-Familie aus VERIFY_2 war zu hart; NC301S (Entgeltsätze im §301-Strom) als
  Tier-3-Kandidat wieder aufgenommen, Rest der Familie bleibt draußen.
- **SOOD/SRGBTBREL** (SAP-Office-Dokumente + Objektrelationen) werden für Dokumente
  genutzt → der vermisste Arztbrief-Pfad läuft offenbar über SAP Office, nicht N2TEXT.
  Als Kandidat für DocumentReference-Anreicherung notiert (CONCEPT_EXT §1-Frage).
- NAPX_FAL, NKSK, NFFZ, NPER, NGPA, N2LABOR001, NTMN, NAPP — alle bereits in
  Registry/CONCEPT_EXT, durch DIAS-Nutzung bestätigt.

**Bewusst NICHT übernommen (außerhalb unseres Scopes Read-only-FHIR-Analytik):**
PEP/PPUG-Personaldaten (hrp.PA0008 Bezüge!), Erlösverteilung/DDMI, RKT-Fakturierung,
OP-Saalsteuerung, COPRA5-Intensivdaten, Credos-/Ultima-Tumordokumentation, Biobank,
Mirth-HL7-Feeds. Das sind eigene Quellsysteme bzw. Personal-/Abrechnungsdomänen —
falls je gewünscht, sind es neue Quellen-Adapter, kein IS-H-Mapping.

**Interessant für später:** „DM Einwilligungen für DIZ" — es existiert eine
Consent-Verwaltung; für FHIR `Consent` und die MII-Perspektive (CONCEPT §19.1
Stufe 3) relevant.

## 6. Was wir explizit NICHT übernehmen (und warum)

1. **Das SCD2-/Fullload-Framework selbst** — dynamisches SQL aus einer Konfig-Tabelle
   (`ProcStarter` exec't 44.000-Zeichen-Strings), wöchentlicher 5-Jahres-Fullload,
   TEMP-Tabellen-Ketten. SAP_FIHR erreicht dasselbe Ziel (aktueller Stand + Änderungs-
   nachvollzug) mit Keyset-Backfill einmalig + `__ct`-Deltas + Compaction in Minuten
   statt Stunden. Die `_delta_archive/`-Ablage ersetzt die Änderungshistorie für
   Audit-Zwecke; eine echte SCD2-Historie (Gültigkeitsintervalle je Satz) ist bei
   Bedarf eine DuckDB-View über Archiv-Deltas — kein eigenes Framework.
2. **CDPOS/CDHDR-Auswertung** (SAP-Änderungsbelege) — nur nötig für Historisierung
   VOR Beginn der `__ct`-Aufzeichnung. Als Option dokumentiert, nicht gebaut.
3. **Hartkodierte Fall-Listen** (`Falldaten_Merkmale`, „Kinder2023" mit eingebetteten
   Fallnummern im Prozedurtext) — Anti-Pattern; solche Kohorten sind bei uns
   `cohort_sql`-Abfragen bzw. eine Merkmal-CSV, nie Code.
4. **Filter_Fallnummer-Zwangsjoin** — der Altbestand filtert alles über eine
   Filtertabelle; wir scopen über MANDT/EINRI in der Registry.

## 7. Umgesetzte Übernahmen (dieser Stand)

| # | Übernahme | Ort |
|---|---|---|
| 1 | BEWTY-Enum korrigiert (2=Entlassung, 3=Verlegung) + 6/7 Beurlaubung | `fhir/mappers/core.py` |
| 2 | BWEDT=9999 → offenes Ende (NULL) | Mapper + `gold/marts.sql` |
| 3 | NDIA: DIAGW/DIALO/DIAPR/KZTXT/DIAZT + Flag-Klartexte des Altbestands | Mapper, `config/columns/NDIA.yaml` |
| 4 | NICP verifiziert (PK LNRIC, ICPML/ICPMK, BGDOP/ENDOP, BTEXT) | Registry, Mapper, `config/columns/NICP.yaml` |
| 5 | NAPX-REASON-Klartexte inkl. OG/MD/RP + `STDAT<>ERDAT`-Filter | `graph/load.py` (`FUEHRT_ZUSAMMEN`) |
| 6 | Katalog-Registry TN14T/TN14R/TN14U/TN14W/TN24T/NKDI (cdc: full) | `config/tables.yaml` |
| 7 | NFAL-Zusatzfelder inkl. STASP-Ausschlussregel | Spaltenkatalog, `mcp/views.py` (STASP-Filter), Marts |
| 8 | V2-Verifikationsstand komplett integriert (Coverage/NKSK, NGEB, NBAU, RFPAT-Link, Diagnose-Flags, DKEY2-Regel, Scope EINRI=0001) | Registry, Mapper, docs/VERIFY_RESULTS*.md |
| 9 | gold.diagnose_typen (Verwendungs-Flags je Monat) | `gold/marts.sql` |
| 10 | DIAS-DataMart-Katalog als Anforderungs-Backlog | `legacy/dias/OBJEKTBAUM_INDEX.md`, dieses Dokument §5 |

## 8. Offene Punkte aus dieser Analyse (in CONCEPT §20 gespiegelt)

1. PODIA/ARDIA-Bedeutung gegen sapdatasheet/Customizing auflösen (`# VERIFY-KONFLIKT`).
2. TN14T/TN14R einmalig entladen und die Mapper-Enums durch Katalog-Lookups ersetzen.
3. SOOD/SRGBTBREL als Arztbrief-Quelle prüfen (Füllstand + Kategorien).
4. NC301S-Struktur prüfen (Entgelte im §301-Strom; DIAS nutzt sie).
5. Historisierungsbedarf klären: reicht `_delta_archive`, oder braucht eine
   Auswertung echte Gültigkeitsintervalle (dann SCD2-View über Archiv-Deltas)?
6. „Einwilligungen für DIZ": Consent-Quelle identifizieren (für MII-Stufe).
