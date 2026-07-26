# CLAUDE.md — sapfhir: IS-H/i.s.h.med → FHIR/Analytik (HIGL/UKL)

## Projektkontext
Quell-DB: MSSQL 10.50.8.250 (read-only), DB `Replicate`, Schema `sap` (Qlik-Replikat des
SAP IS-H/i.s.h.med). Konstanten: MANDT='100', EINRI='0001'. Change-Tables `<T>__ct`.
Haus-ETL-Referenz: DB `Analysen` (E-Statistik, base-table-main-Prozeduren).
HRP-Schema: für klinisch-analytische FHIR-Ausleitung AUSGEKLAMMERT; seit R19 IN Scope
NUR für die Berechtigungs-/Datenverfügbarkeits-Strecke (Mitarbeiter↔Abteilung:
PA0105/90AD→PERNR→PA0001.ORGEH→IS-H-OE→NBEW). Siehe docs/BERECHTIGUNGSKONZEPT.md +
docs/PATIENT_DATENKATALOG.md. Mitarbeiter-Personendaten verkryptungspflichtig.

## Verbindliche Methode
Lies ZUERST `docs/Analyse_Datenbank.md` — sie definiert das komplette Vorgehen:
1. **Dreiklang je Tabelle/Feld:** sapdatasheet.org → Schema live (PK-Uniqueness!) →
   Daten live (Fill-Rates, Top 1000, Werteverteilungen). Schema-Wahrheit ≠ Daten-Wahrheit.
2. **NPAT-zentrierte Breitensuche** über den FK-Graphen; jede neue Zieltabelle in die
   Warteschlange; Status je Tabelle in `config/tables.yaml` fortschreiben.
3. **Verkryptung:** personenidentifizierende Varchars (Namen, Adressen, VERNR/KVNR,
   EDIFACT-Inhalte NC301M/V/W, Freitexte) NIE im Klartext selektieren/loggen —
   nur HASHBYTES-SHA256 oder LEN/Initial. Details/Feldliste: Analyse_Datenbank.md §4.
4. **Verlustfreiheit:** unbekannte Codes nie raten, nie verwerfen → Rohcode unter
   `urn:ish:<katalog>`; kuratierte Displays nur bei gesicherter Deutung.
5. **Medizin ≠ Abrechnung:** Encounter bleiben unangetastet; NAPX→Account-Klammer,
   NFFZ→Extension. KEIN Encounter.replaces/partOf für Zusammenführungen.
6. **Datums-Pipeline:** Mapper (roh) → privacy (Shift/hash_id auf Rohwerten) →
   `normalize_resource()` (ISO-8601 Europe/Berlin) → NDJSON. Sentinels: `_echtes_datum`
   (0101-01-01 = SAP-Leerdatum via Qlik = OFFENER Fall → status in-progress).

## Wichtigste verifizierte Fakten (Kurzliste; Vollstand: config/tables.yaml + docs/VERIFY_LOG)
- NDRG hat ENGLISCHE Spalten (CLIENT/INSTITUTION/PATCASEID). NLEI/NLEM-Key = [MANDT,LNRLS].
- GPART == PERNR == PHYSNO (1:1, 236.114) → EIN Practitioner-ID-Schema für NGPA/NPER/
  NFPZ/NKBVLANR/NBSNR. Pipeline mergt NGPA(Name)+NPER(LANR/FACHR).
- Tote Felder in DIESEM Haus: NICP.OPART, NBEW.UNFAV/VGNREF/NFGREF, NFAL.FACHR/ENDTYP,
  NDIA.DIASI (Wahrheit: DIAGW). Bewegungskette per ORDER BY BWIDT/BWIZT ableiten.
- §301-Meldedaten: NC301S (Index) + NC301M (EDIFACT-Rohtext, gechunkt) + NC301V/W (Segmente).
- N1MEORDER leer → Medikation/Vitalwerte via COPRA5/6 (siehe DIAS-Baum) erschließen.
- Nicht replizierte Kataloge: TN14K, TN14O, N2DT, TN26B/D → Rohcode-only.

## Arbeitsregeln für Sessions
- Jede neue Erkenntnis SOFORT in `config/tables.yaml` (notes, 'verifiziert Rx') und bei
  Korrekturen in `docs/VERIFY_LOG_R8-R13.md` (neue Runde anhängen) dokumentieren.
- Mapper-Änderungen IMMER mit Test in `tests/test_core.py`; Referenz-Konsistenz
  (ID-Schemata) explizit asserten. `python -m pytest tests/ -q` muss grün sein.
- Online-Aggregate >50 Mio Zeilen (NLEI, N2LABOR001) timeouten → Lastfenster/Batch.
- Backlog-Reihenfolge: Analyse_Datenbank.md §8.

## Repo-Betrieb (Ergänzung zur Methode — Details in docs/)
- **Produkt: CliniBots Patient Insight** (Codename SAP_FIHR/sapfhir); Schwesterprodukt
  CliniBots MDM (`C:\ai\MD_Management`). **Einstieg IMMER über `docs/INDEX.md`**
  (Dokumentenlandkarte): Zielbild = `CONCEPT_P360_VOLLAUSBAU.md`, Architektur =
  `CONCEPT.md` v0.3, **einzige Roadmap = `docs/ROADMAP.md`** (nirgendwo sonst Backlogs
  pflegen!). Archiv-Docs (CONCEPT_EXT, ANALYSE, GESAMTREVIEW, INGOLF_*, ALTBESTAND_*,
  VERIFY_RESULTS*) tragen Status-Banner und werden nicht fortgeschrieben.
  Verifikationslog fortlaufend ab R8: `docs/VERIFY_LOG_R8-R13.md` (aktuell R19).
- Pipeline (alles user-space, No-Admin): Keyset-Backfill + `__ct`-CDC (Delta-Parquet,
  Retention-Waechter) -> `bronze_current`-Merge-Views + Compaction (`extract/merge.py`)
  -> FHIR-NDJSON mit Index/Provenance (`fhir/ndjson.py`; Reihenfolge Mapper -> Shift ->
  `normalize_resource`) -> Gold-Marts/FTS/DQ -> maskierte `mcp.*`-Schicht -> Kuzu-Graph.
- MCP-Server gehaertet nach CONCEPT §17 (Sandbox-DuckDB, mcp.*-Zwang, Timeouts,
  Audit-Hash-Kette). Betrieb/Installation: `docs/DEPLOYMENT.md` (Setup.bat, Nightly).
- Verproben ohne DB: `python tools/seed_demo.py --pipeline` + `python -m sapfhir.api.app`.
- Tests: `python -m pytest tests/ -q` (ohne DB lauffaehig) — muss vor jedem Push gruen sein.
- Git: Branch `claude/concept-analysis-expansion-nwg4ua`; jede Session pusht ihre
  Ergebnisse dorthin (Remote- und Lokal-Sessions arbeiten am selben Stand).
