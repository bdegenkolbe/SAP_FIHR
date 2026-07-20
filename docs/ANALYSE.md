# Analyse des Projektstands (Konzept v0.1 → Basis für v0.2)

> **STATUS: ARCHIV** (siehe `INDEX.md`). Historisches Review; alle Punkte in CONCEPT
> v0.2/v0.3 eingearbeitet. Nicht mehr fortschreiben.

Stand: 15.07.2026 · Reviewer: Claude Code · Bezug: `docs/CONCEPT.md` v0.1 + Quellcode-Skelett

Gesamturteil: Das Konzept ist tragfähig und die Architekturentscheidungen (Medaillon,
DuckDB/Kuzu embedded, Keyset-Pagination, Qlik-`__ct`-CDC, No-Admin) sind für den
Anwendungsfall richtig gewählt. Das Code-Skelett deckt den Happy Path ab. Es gibt
jedoch **eine strukturelle Lücke in der Pipeline (CDC-Deltas erreichen Gold nie)**,
**mehrere Datenschutz-Inkonsistenzen** und **eine Reihe von Sicherheitslücken im
MCP-Pfad**, die vor Phase 2/5 konzeptionell geschlossen werden müssen. Die daraus
abgeleiteten Erweiterungen sind in `docs/CONCEPT.md` v0.2 (§14–§19) eingearbeitet.

---

## 1. Strukturelle Befunde (blockierend für den jeweiligen Phasenabschluss)

### A1 — CDC-Deltas werden nie mit Bronze zusammengeführt (Phase 2)
`src/sapfhir/extract/cdc.py` (`_merge_delta`) schreibt Änderungszeilen in DuckDB-Tabellen
`_delta.delta_<tabelle>` — alle Spalten als `VARCHAR`. Die Gold-Views
(`src/sapfhir/gold/marts.sql`) und alle MCP-Tools lesen aber ausschließlich
`data/bronze/**/*.parquet`. **Folge: Nach dem Backfill eingehende Änderungen sind in
Analytik, FHIR-Ausleitung und MCP unsichtbar.** Es fehlt der Merge-/Compaction-Schritt
(Bronze ∪ Delta, last-write-wins über `header__change_seq`, Delete-/Storno-Flag).
→ Konzept v0.2 §14 definiert `bronze_current`-Views + nächtliche Compaction.

### A2 — Qlik-`__ct`-Retention ist ein unerkanntes Datenverlust-Risiko (Phase 2)
Qlik Replicate räumt Change-Tables nach konfigurierter Retention ab. Liegt die
gespeicherte Watermark (`change_seq`) vor der ältesten noch vorhandenen Sequenz
(z. B. nach Urlaub/Ausfall des Extraktors), gehen Änderungen **still** verloren —
`cdc.py` prüft das nicht. → Lückenerkennung (min. verfügbare Sequenz ≥ Watermark,
sonst Alarm + gezielter Re-Backfill) in v0.2 §14.3; Retention beim DB-/Qlik-Team
erfragen (offener Punkt §20).

### A3 — Privacy-Modus wirkt nur auf Silver, MCP liest Klardaten aus Bronze (Phase 5/6)
Die `Privacy`-Pipeline (HMAC, Date-Shift, De-ID) greift nur in der FHIR-Ausleitung
(`fhir/ndjson.py`). Die MCP-Tools (`mcp/server.py`) lesen jedoch **direkt Bronze-Parquet**
mit Klardaten: `cohort_sql` liefert ungefiltert alles, `_mask()` greift nur in
`patient_search` und nur auf eine hartkodierte Spaltenliste. `pseudonymize_view: true`
suggeriert einen Schutz, der real nicht existiert. → v0.2 §17.2: MCP darf ausschließlich
auf eine definierte, maskierte View-Schicht (`mcp.*`) zugreifen, nie auf Bronze-Rohdaten.

### A4 — Date-Shift ist inkonsistent und damit wirkungslos (Phase 3/6)
`map_encounter` verschiebt BEGDT/ENDAT, aber `map_encounter_bewegung`, `map_condition`,
`map_procedure`, `map_observation_labor` und `map_document_reference` exportieren
**Echtdaten** (`mappers/core.py:94,114,135`). Damit lässt sich der Shift trivial
zurückrechnen (Bewegungsdatum ≈ Falldatum) und die Zeitachsen von Fall und Bewegung
passen nicht mehr zusammen. → Regel in v0.2 §16.4: *jedes* Datum läuft durch
`priv.shift(pid, …)`; dazu muss die PATNR an allen Mappern verfügbar sein (siehe A5).

### A5 — Condition/Observation/DocumentReference ohne Patient-Referenz (Phase 3)
NDIA/NICP/N2LABOR/NDOC-Mapper erzeugen Ressourcen ohne `subject` (nur `encounter`).
ISiK-Basis und MII KDS verlangen `subject: Patient/...`; auch der Date-Shift (A4)
braucht die PATNR. Die Auflösung FALNR→PATNR muss als Lookup (DuckDB-Join gegen NFAL)
in die Silver-Stufe. → v0.2 §16.2.

### A6 — NPAT-Primärschlüssel vermutlich falsch registriert (Phase 1)
`config/tables.yaml` führt NPAT mit PK `[MANDT, EINRI, PATNR]`. Im IS-H-Datenmodell ist
der Patient **einrichtungsunabhängig** (Schlüssel MANDT+PATNR; NPAT hat i. d. R. keine
EINRI-Spalte). Der Keyset-Backfill würde mit `ORDER BY [EINRI]` sofort mit SQL-Fehler
abbrechen. Gleiches Muster prüfen für NADR, NDOC, N2TEXT. → vor Phase 1 gegen
`INFORMATION_SCHEMA.COLUMNS` der Live-Replika verifizieren (offener Punkt §20;
`--check` um PK-Validierung erweitern, v0.2 §15.4).

---

## 2. Sicherheitsbefunde MCP (vor Phase 5 zu schließen)

### S1 — `cohort_sql` erlaubt beliebige Dateilesezugriffe
Der Guard (`mcp/guard.py`) blockt DDL/DML-Keywords, aber nicht DuckDB-Tabellenfunktionen:
`SELECT * FROM read_csv('C:/Users/.../secrets.txt')` oder `read_parquet` auf beliebige
Pfade sind gültige SELECTs. Ein LLM-getriebener Client kann so die gesamte Platte lesen.
→ v0.2 §17.3: DuckDB-Verbindung des MCP mit `enable_external_access=false` +
`memory_limit` öffnen; MCP-Views materialisieren die benötigten Daten vorab, sodass
kein `read_parquet` im Anfragepfad nötig ist. Zusätzlich Funktions-Blockliste im Guard.

### S2 — Query-Timeout konfiguriert, aber nicht durchgesetzt
`TIMEOUT` wird in `mcp/server.py:40` gelesen und nie verwendet. Eine teure Anfrage
(Kreuzprodukt über 210 Mio NLEI-Zeilen) blockiert den Server unbegrenzt.
→ Interrupt-Thread bzw. `duckdb` Progress-Handler; für Kuzu Query-Timeout-Parameter (§17.3).

### S3 — Audit-Log enthält Klartext-Parameter
Konzept v0.1 §9 verspricht „Parameter-Hash", `audit.py`/`server.py` loggen aber rohe
SQL-/Cypher-Strings und Suchparameter (können Patientennamen enthalten). Das Audit-Log
wird damit selbst zur schutzbedürftigen Datei. → v0.2 §17.4: Parameter hashen,
Log-Datei ACL-beschränkt, Hash-Kette für Manipulationsnachweis.

### S4 — Prompt-Injection über Dokumententexte (doc_search)
N2TEXT-Inhalte (Arztbriefe, Befunde) fließen als Tool-Ergebnis in den LLM-Kontext.
Ein Dokument, das Anweisungstext enthält (auch versehentlich, z. B. zitierte E-Mails),
kann das LLM zu weiteren Tool-Aufrufen verleiten. Da alle Tools read-only sind, ist der
Schaden auf Datenabfluss *innerhalb* der Session begrenzt — trotzdem: Ergebnisse als
Daten kennzeichnen (Delimiter/Hinweistext), Row-Limits klein halten (§17.5).

### S5 — Kleinere Härtungen
- `enforce_limit` hängt `LIMIT` nur außen an; Memory-Schutz kommt erst mit S1/S2.
- `check_cypher`-Blockliste verbietet `SET` — trifft auch legitime Query-Teile nicht,
  ok; aber `LOAD`-Extension-Blockade fehlt für Kuzu nicht (kein Extension-Load dort).
- `fhir_get` und `patient_360` maskieren nie (unabhängig von `pseudonymize_view`).

---

## 3. Konsistenz-Deltas Konzept ↔ Code ↔ README

| # | Befund | Ort |
|---|---|---|
| K1 | Konzept sagt `Resource.id = sha1(...)`, Code/CLAUDE.md nutzen uuid5 | CONCEPT §6 vs. `fhir/ids.py` — **uuid5 ist richtig** (idempotenter Upsert), Konzept in v0.2 korrigiert |
| K2 | Referenzierte, aber fehlende Dateien: `fhir/terminology.py`, `gold/fts.py`, `graph/schema.py`, `docs/DEPLOYMENT.md`, `tests/test_golden.py` | README/CLAUDE.md — DEPLOYMENT.md jetzt angelegt; Module in Roadmap v0.2 §21 verankert |
| K3 | Repo-Layout in CONCEPT §11 (`ishx/`, Setup.bat im Root) ≠ realer Baum (`installer/`, `docs/`, Paketname `sapfhir`) | in v0.2 §11 an Realität angepasst |
| K4 | `config/columns/` deckt nur NBEW+NFAL ab; Konzept verlangt Projektion je (breiter) Tabelle — für NLEI (210 Mio × alle Spalten) sonst Backfill-Killer | Roadmap §21: Spaltenkataloge für alle Tier-1/2-Tabellen sind Phase-1-Deliverable |
| K5 | Totes/verwirrendes Codefragment: `"finished" if ... and False else "finished"` | `mappers/core.py:70` |
| K6 | Dead Code `if False else _fetch(...)` | `mcp/server.py:64-71` |
| K7 | `patient_search` ignoriert `name`/`gebdat`/`falnr`; `patient_timeline` liefert nur Fälle (keine Bewegungen/Dx/OPS) | `mcp/server.py:81-137` — als Stub ok, in Phase 5 ausbauen |
| K8 | `Encounter.class` ohne CodeSystem-URI (`http://terminology.hl7.org/CodeSystem/v3-ActCode`) — ISiK-Pflicht | `mappers/core.py:71` |
| K9 | FTS-Aufruf vermutlich falsch (Indexname `fts_main_gold_doc_text` bei Schema-qualifizierter Tabelle, Spalten VERIFY) | `mcp/server.py:177`, `gold/build.py` |
| K10 | Lastfenster (`extract.window`) und `max_connections` konfiguriert, aber nicht implementiert | `backfill.py` — Phase-1-Deliverable §21 |

## 4. Technische Detailbefunde (nicht blockierend, einplanen)

| # | Befund | Empfehlung |
|---|---|---|
| T1 | Small-Files-Problem: 1 Parquet-Datei pro Batch×Jahr → NLEI-Backfill erzeugt tausende Kleindateien | Compaction-Job (v0.2 §14.2): Ziel-RowGroup ~128 MB, jahrweise zusammenfassen |
| T2 | `_merge_delta` verliert Typen (alles VARCHAR) | Delta als Parquet mit Bronze-Schema schreiben, nicht als DuckDB-VARCHAR-Tabelle |
| T3 | Keyset bricht bei NULL in PK-Spalte (lexikografischer `>`-Vergleich) | PK-NULL-Check im `--check`; SAP-Schlüssel sind praktisch nie NULL |
| T4 | `where_extra` (MANDT/EINRI) per f-String statt Parameter | Werte kommen aus eigener Config (kein Injection-Vektor), trotzdem parametrisieren |
| T5 | `fhir_get` scannt alle NDJSON-Dateien linear (53 Mio DocumentReference!) | FHIR-Index-Tabelle in DuckDB: (resource_type, id) → Datei+Zeile (v0.2 §16.3) |
| T6 | Silver-Ausleitung ist immer Full-Rewrite (`part-0.ndjson.gz`) | Run-basierte Teildateien + Provenance je Lauf (v0.2 §16.3) |
| T7 | Kuzu-Load: Bewegung/Diagnose/Prozedur/OE-Knoten im DDL, aber nie befüllt; `FOLGT_AUF` nie erzeugt; WIEDERAUFNAHME ohne ICD-Gruppen-Bedingung (Konzept verlangt „gleiche Hauptdiagnose-Gruppe") | Phase-5-Deliverable §21; Wiederaufnahme-Definition fachlich fixieren (§20) |
| T8 | Observation ohne UCUM-Einheit, Wert ungecastet | Terminologie-Schicht v0.2 §18 |
| T9 | Keine Provenance-Ressourcen trotz Konzept-Zusage §6 | v0.2 §16.3 |
| T10 | Watermark-CDC (`SELECT *`) ignoriert Spaltenprojektion → NLEI-Inkrement zieht alle Spalten | Projektion aus `config/columns/` auch im CDC-Pfad |
| T11 | Golden-Record-Test fehlt (CLAUDE.md verweist auf `tests/test_golden.py`) | Phase-3-Akzeptanzkriterium; Fixture-Patient definieren (§20) |
| T12 | Keine Reconciliation Quelle↔Bronze (Zeilenzahlen, Checksummen) | DQ-Framework v0.2 §15 |

## 5. Was ausdrücklich gut ist (beibehalten)

- **Keyset-Pagination mit entfalteter Tupel-Bedingung** (`keyset.py`) — korrekt für
  MSSQL ohne Row-Value-Constructor, resümierbar, konstant schnell.
- **Trennung Registry (`tables.yaml`) / Projektion (`columns/*.yaml`)** — erweiterbar
  für ZZ*-Felder und `/ISHFR/`-Namespace ohne Codeänderung.
- **`# VERIFY`-Disziplin** — ehrliche Markierung ungesicherter Feldannahmen; in v0.2
  zum formalen Gate ausgebaut (§15.4).
- **Privacy-Baustein aus Ingolf** (HMAC-Pseudonym, patientenfixer Date-Shift,
  wertbasiertes `hash_id`) — Logik solide, nur die konsequente Anwendung fehlt (A3/A4).
- **uuid5-IDs** für idempotente Upserts; **stdio-MCP ohne Netz-Egress**;
  **No-Admin-Konsequenz** durch alle Ebenen (pytds, DuckDB, Kuzu, Port>1024, HKCU).

## 6. Priorisierte Handlungsliste

1. **Vor Phase 1:** A6 (PK-Verifikation via INFORMATION_SCHEMA), K4 (Spaltenkataloge
   Tier 1), K10 (Lastfenster), T3-Check.
2. **Phase 2 neu geschnitten:** A1 (Merge/Compaction = eigener Meilenstein 2b),
   A2 (Retention-Lückenerkennung), T1, T2, T10.
3. **Phase 3:** A4+A5 (PATNR-Lookup + durchgängiger Date-Shift), K5, K8, T5, T6, T9, T11.
4. **Phase 5:** komplette MCP-Härtung S1–S5, K6, K7, K9, T7.
5. **Phase 6:** A3 (maskierte MCP-View-Schicht) als Datenschutz-Freigabekriterium.
