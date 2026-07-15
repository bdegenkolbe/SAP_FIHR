# GREENBAY clinical — IS-H Edition (Arbeitstitel „ishx")
## FHIR-basiertes Entladetool + Auswertungsdashboard + Patienten-MCP-Server

Version 0.1 · 15.07.2026 · Konzept für Rollout via Claude Code
Verwandtes Projekt: `ingolf` (medatixx/Praxis) — **hier explizit OHNE PVS-Ansatz**: reine Read-only-Sekundärnutzung, keine Rückschreibung, keine Abrechnung, keine Primärdokumentation.

---

## 1. Ziel und Abgrenzung

Drei Produkte auf einer gemeinsamen Datenbasis:

1. **Entladetool (ETL)** — inkrementelle, wiederaufsetzbare Extraktion des IS-H/i.s.h.med-Bestands aus der MSSQL-Replika in ein lokales, spaltenorientiertes Analyselager (Parquet + DuckDB), inklusive vollständiger FHIR-R4-Ausleitung als NDJSON-Bundles.
2. **Auswertungsdashboard** — lokales Web-Dashboard (kein IIS, kein Adminrecht) für Fallzahlen, Verweildauer, Case-Mix, Diagnosen/Prozeduren, Belegung, Dokumentenbestand.
3. **MCP-Server** — stdio-basierter MCP-Server, über den ein LLM (Claude Desktop / LibreChat) natürlichsprachliche Fragen zum Patienten stellt. Rückgrat: DuckDB (SQL/Kohorten) + **Kuzu** als eingebettete Graphdatenbank (Patient-Fall-Bewegung-Diagnose-Graph, Cypher).

**Nicht-Ziele:** kein Schreiben in SAP, keine KIS-Funktionalität, kein PVS, keine Arbeitsliste, keine Abrechnungslogik. §301/DRG-Tabellen werden nur lesend für Analytik verwendet.

---

## 2. Verifizierte Quellenlage (Stand 15.07.2026)

- Server: MSSQL, Datenbank **`replicate`**, Schemata **`sap`** (1.152 Basistabellen) und **`hrp`** (~101 Basistabellen), gespeist durch **Qlik Replicate** (erkennbar an `attrep_*` und `__ct`/`__ct__bak`-Change-Tables je Basistabelle).
- IS-H-Kern vollständig: NPAT, NFAL, NBEW, NDIA, NDIP, NICP, NLEI, NDRG, NDOC, NORG, NGPA, NADR, NKTR/NFPZ/NFFZ (Versicherung/Kostenträger), NC301* (§301), NAPP/NTMN (Termine), NLEM (Leistungspositionen).
- i.s.h.med: N1CORDER/N1ANF (klinische Aufträge), N2TEXT (med. Dokumente/Texte), N2LABOR (Befundwerte), N2DTT, N1LSSTA.
- HR/Orga: hrp.HRP1000/HRP1001 (Orgeinheiten/Verknüpfungen), hrp.PA0000–PA0003 ff. (Personal → Practitioner).
- Kundeneigene Felder: `ZZ*`-Spalten (z. B. NBEW.ZZPLS, ZZSST) und `/ISHFR/`-Namespace vorhanden → Mapping muss erweiterbar sein.

Mengengerüst (gezählt via `sys.partitions`):

| Tabelle | Zeilen | Tier |
|---|---:|---|
| NLEI | 210.722.384 | 2 |
| NDOC | 53.956.942 | 1 |
| N2TEXT | 53.924.586 | 1 |
| NBEW | 28.373.260 | 1 |
| NDIA | 25.196.321 | 1 |
| NLEM | 22.450.827 | 2 |
| N2LABOR | 14.964.260 | 1 |
| NAPP | 11.520.644 | 2 |
| NICP | 10.294.535 | 1 |
| NFAL | 9.655.156 | 1 |
| NADR | 6.107.934 | 1 |
| NDRG | 4.146.005 | 2 |
| N1CORDER | 3.641.785 | 2 |
| NPAT | 1.464.261 | 1 |
| NORG | 2.406 | 1 |

**Tier 1** = klinischer Kern (Pflicht für Patient-360 + FHIR), **Tier 2** = Analytik/Abrechnung (optional nachladbar), **Tier 3** = Rest on demand. Grobe Volumenschätzung Tier 1+2 als zstd-Parquet: **60–120 GB** (Faktor ~15–25 Kompression auf nvarchar-lastigen SAP-Tabellen). Zielplatte: lokale SSD, ≥ 250 GB frei einplanen (Parquet + DuckDB + Kuzu + FHIR-NDJSON).

---

## 3. Architektur (Medaillon, alles user-space)

```
MSSQL replicate (sap/hrp, read-only)
        │  python-tds (pure Python, kein ODBC-Treiber nötig)
        ▼
[BRONZE]  Parquet-Staging  data/bronze/<tabelle>/jahr=YYYY/*.parquet
        │  Keyset-Pagination Vollabzug + __ct-CDC-Inkremente
        ▼
[SILVER]  FHIR R4 NDJSON    data/silver/fhir/<ResourceType>/*.ndjson.gz
        │  Mapper (Tabelle 6), Terminologie (ICD-10-GM, OPS, LOINC-Map)
        ▼
[GOLD]    DuckDB warehouse.duckdb (Marts, FHIR-Index, FTS auf N2TEXT)
          Kuzu   graph.kuzu       (Property-Graph, Cypher)
        │
        ├── Dashboard  (FastAPI/uvicorn, 127.0.0.1:8471, statisches HTML+SVG)
        └── MCP-Server (stdio → Claude Desktop / Supergateway → LibreChat)
```

Entscheidungen und Begründung:

- **python-tds statt pyodbc**: pyodbc benötigt den systemweit installierten MS-ODBC-Treiber (Adminrecht). python-tds ist pure Python, pip-installierbar, ausreichend schnell für Bulk-Reads (Engpass ist ohnehin Netz/Disk). Fallback: `pymssql` (Wheel, ebenfalls adminfrei).
- **DuckDB statt Postgres**: eine Datei, kein Dienst, kein Adminrecht, exzellent auf Parquet, verkraftet die 210-Mio-Zeilen-NLEI problemlos out-of-core.
- **Kuzu statt Neo4j**: Neo4j braucht JVM + Dienst (Admin, Betriebsaufwand). Kuzu ist eine eingebettete, spaltenorientierte Graph-DB (pip install kuzu), spricht Cypher, lädt direkt aus Parquet (`COPY FROM`), skaliert in den Milliarden-Kanten-Bereich. Perfekt für den No-Admin-Constraint.
- **FHIR als Datei-Ausleitung (NDJSON), kein FHIR-Server als Pflicht**: Bulk-Data-kompatibel ($export-Format). Optionaler HAPI/Medplum-Import bleibt möglich, ist aber nicht Betriebsvoraussetzung.

---

## 4. No-Admin-Betrieb (harte Anforderung)

- **Python embeddable** (zip) oder User-Install + venv unter `%LOCALAPPDATA%\greenbay\ishx` — kein Registry-Eintrag, kein Program Files.
- Abhängigkeiten ausschließlich als Wheels: `python-tds`, `duckdb`, `kuzu`, `pyarrow`, `fastapi`, `uvicorn`, `mcp`. Kein Compiler, kein ODBC, kein Dienstkonto.
- Dashboard-Server bindet auf `127.0.0.1`, Port > 1024 (Default 8471) → keine Firewall-/URLACL-Rechte nötig.
- Start über `Setup.bat` / `Start-Dashboard.bat` / `Start-MCP.bat` (Muster aus GREENBAY clinical, AppLocker-Check aus `first_run.py` wiederverwenden).
- Autostart optional per HKCU-Run-Key oder Aufgabenplanung im Benutzerkontext (beides adminfrei).
- MCP-Anbindung: Claude Desktop `claude_desktop_config.json` (user-scope) bzw. Supergateway-Bridge in LibreChat auf PC-A — Preflight-Skill `windows-infra-preflight` vor jedem Rollout ausführen.

---

## 5. Extraktionsstrategie (große Datenmengen)

**Vollabzug (Backfill):**
- Keyset-Pagination über den Clustered-PK (MANDT, EINRI, FALNR, LFDNR …) statt OFFSET — konstante Latenz auch bei 210 Mio Zeilen.
- Batchgröße adaptiv (Start 100k Zeilen, Ziel ~120 s/Batch), Schreiben als Parquet-RowGroups (zstd, level 3), Partitionierung nach Jahr (ERDAT bzw. fachlichem Datum).
- Spaltenprojektion: nur gemappte + analytisch benötigte Spalten (NBEW hat 120 Spalten — wir brauchen ~40). Spaltenkatalog pro Tabelle in `config/columns/*.yaml`.
- Resumierbarkeit: Statustabelle `_meta.extract_state` in DuckDB (tabelle, letzter Schlüssel, Zeilen, Dauer, Hash). Jeder Batch idempotent, Abbruch jederzeit möglich.
- Zeitfenster-Drossel: konfigurierbares Nachtfenster + max. parallele Verbindungen (Default 2), um die Replika nicht zu belasten.

**Inkrement (CDC):**
- Primär über die Qlik-`__ct`-Tabellen: Spalten `header__change_seq`, `header__change_oper` (I/U/D) → Merge in Bronze, Watermark = letzte change_seq je Tabelle.
- Fallback für Tabellen ohne brauchbares ct: UPDAT/ERDAT-Watermark (IS-H pflegt beides) — Achtung: Datum ohne Zeit in manchen Tabellen → 1 Tag Überlappung + Dedup über PK.
- Storno-Semantik beachten: NBEW.STORN/NDIA/NICP-Stornokennzeichen werden nicht gelöscht, sondern als `status: entered-in-error` in FHIR gemappt.

**Durchsatzschätzung:** konservativ 30–60k Zeilen/s über python-tds bei schmaler Projektion → NLEI-Backfill 1–2 Nächte, Tier 1 komplett < 1 Nacht. Danach CDC-Läufe im Minuten-Bereich.

---

## 6. FHIR-R4-Mapping (Kern, ISiK-Basis-orientiert)

| IS-H | FHIR-Ressource | Anmerkungen |
|---|---|---|
| NPAT (+NADR, NPAE) | Patient | Identifier: PATNR (+ optional KVNR aus NKSK/NFPZ-Kontext); Adresse aus NADR via ADRNR |
| NFAL | Encounter (Top-Level) + Account | FALAR → class (stationär/ambulant/teilstat.); Encounter.identifier = EINRI-FALNR |
| NBEW | Encounter.location[] + Sub-Encounter je Bewegung | BEWTY (Aufnahme/Verlegung/Entlassung/amb. Besuch), ORGFA/ORGPF → Location/ServiceProvider, Zeitraum BWIDT/BWIZT–BWEDT/BWEZT; STORN → entered-in-error |
| NDIA (+NDIP) | Condition | ICD-10-GM (DKEY1), Lokalisation, Diagnosetyp (Aufnahme/Entlass/Neben) via NDIP-Verwendung; encounter-Referenz über FALNR |
| NICP | Procedure | OPS (ICPK1/ICPML), Datum, durchführende OE |
| N2LABOR | Observation (laboratory) | Wert/Einheit/Referenzbereich; LOINC-Mapping-Tabelle als Konfig (Start: hauseigene Codes als CodeableConcept.text) |
| NLEI/NLEM | ChargeItem (Tier 2) | nur Analytik, kein Billing-Workflow |
| NDRG | Encounter-Extension + Claim (optional) | DRG, CMI-Berechnung im Gold-Layer |
| NDOC + N2TEXT | DocumentReference (+ Binary optional) | Kategorie aus Dokumenttyp; Volltext in DuckDB-FTS, nicht in FHIR |
| N1CORDER/N1ANF | ServiceRequest | klinische Aufträge |
| NAPP/NTMN | Appointment (Tier 2) | |
| NORG + hrp.HRP1000/1001 | Organization + Location (Hierarchie) | OE-Baum aus HRP1001-Relationen (A/B 002, 003) |
| hrp.PA0002 (+PA0001) | Practitioner (+ PractitionerRole) | pseudonymisierbar (Konfig-Schalter) |
| NFPZ/NKTR | Coverage + Organization (Kostenträger) | |

Konventionen: `Resource.id = sha1(quelle|MANDT|EINRI|<PK>)`, `meta.source = ishx/<tabelle>`, Provenance pro Ausleitungslauf. Profile: ISiK-Basismodul wo deckungsgleich, sonst DE-Basisprofile; Validierung stichprobenhaft mit `fhir.resources` (Pydantic) im CI, nicht im Massenpfad.

---

## 7. Graphmodell (Kuzu)

Knoten: `Patient`, `Fall`, `Bewegung`, `Diagnose`, `Prozedur`, `Labor` (aggregiert je Parameter+Tag), `Dokument`, `OE`, `Practitioner`, `Kostentraeger`.
Kanten: `HAT_FALL`, `HAT_BEWEGUNG`, `IN_OE`, `HAT_DIAGNOSE`, `HAT_PROZEDUR`, `HAT_BEFUND`, `HAT_DOKUMENT`, `BEHANDELT_VON`, `VERSICHERT_BEI`, `FOLGT_AUF` (Bewegungskette via LFDREF/VGNREF), `WIEDERAUFNAHME` (abgeleitet, < 30 Tage gleiche Hauptdiagnose-Gruppe).

Der Graph wird direkt aus Bronze-Parquet geladen (`COPY Patient FROM 'bronze/npat/*.parquet'`) — kein Umweg über CSV. Beispielfragen, die SQL schlecht und Cypher gut kann:

```cypher
// Alle Fälle eines Patienten mit Wiederaufnahme-Kette und beteiligten OEs
MATCH (p:Patient {patnr:$p})-[:HAT_FALL]->(f:Fall)
OPTIONAL MATCH (f)-[:WIEDERAUFNAHME]->(f2:Fall)
OPTIONAL MATCH (f)-[:HAT_BEWEGUNG]->(:Bewegung)-[:IN_OE]->(o:OE)
RETURN f, f2, collect(DISTINCT o.name)
```

---

## 8. Auswertungsdashboard

Lokal, FastAPI + statisches Frontend (kein Build-Tooling nötig, Vanilla JS + Inline-SVG-Charts). Seiten:
1. **Entlade-Monitor** — Tabellenstatus, Watermarks, CDC-Lag, Durchsatz, Läufe (Mockup 1).
2. **Klinik-Analytik** — Fälle/Monat, Verweildauer, CMI/DRG, Top-Diagnosen/Prozeduren, Belegung nach OE, ambulant/stationär (Mockup 2).
3. **Patient 360** — Read-only-Zeitstrahl (aus FHIR/Gold), Absprung in MCP-Chat.

Alle Aggregationen als DuckDB-Views im Gold-Layer (`gold/marts.sql`), Frontend liest JSON von `127.0.0.1:8471/api/*`.

---

## 9. MCP-Server „ishx-mcp"

stdio, Python `mcp`-SDK, read-only. Tools:

| Tool | Zweck |
|---|---|
| `patient_search(name?, gebdat?, patnr?, falnr?)` | Identifikation, max. 20 Treffer |
| `patient_360(patnr)` | kompakte strukturierte Zusammenfassung (Fälle, Dx, OPS, letzte Labore, Doks) |
| `patient_timeline(patnr, von?, bis?)` | chronologische Ereignisliste |
| `fhir_get(resource_type, id)` / `fhir_search(...)` | Zugriff auf Silver-NDJSON-Index |
| `graph_query(cypher)` | Kuzu, read-only, Timeout 30 s, Zeilenlimit |
| `cohort_sql(select)` | DuckDB, nur SELECT/WITH, Zeilenlimit 1.000 (Muster mssql-praxis) |
| `doc_search(patnr?, query)` | FTS über N2TEXT (BM25), optional später Embeddings |

Schutzschicht: SELECT-only-Parser, Row-Limits, Audit-Log (JSONL: wer/wann/Tool/Parameter-Hash), optionaler Pseudonymisierungs-Modus (Namen/Adressen maskiert, PATNR bleibt), Mandant/EINRI-Filter fest konfiguriert. Kein Netzwerkzugriff des Servers nach außen — EU-/On-Prem-Souveränität by design.

---

## 10. Datenschutz

Verarbeitung ausschließlich on-prem im Benutzerkontext; keine Patientendaten verlassen die Maschine (MCP → lokales LLM-Frontend; bei Claude Desktop gilt: nur mit freigegebener AVV/Konzern-Policy, sonst LibreChat + lokales Modell). Audit-Log verpflichtend, Löschkonzept = Verzeichnis-Wipe (`data/`), Rollen-Gating über Benutzerverwaltung aus GREENBAY clinical wiederverwendbar. Vor Produktivnutzung: DSFA-Kurzcheck + Freigabe Christopher Schrey.

---

## 11. Repo-Struktur (Claude-Code-ready)

```
ishx/
├── CONCEPT.md                  # dieses Dokument
├── Setup.bat / Uninstall.bat   # adminfreie Installation (Muster GREENBAY clinical)
├── config/
│   ├── connection.yaml         # Server, DB, Auth (Windows-Auth via python-tds NTLM)
│   ├── tables.yaml             # Tier, PK, Watermark-Strategie, Partition
│   └── columns/<tabelle>.yaml  # Spaltenprojektion + FHIR-Mapping-Hints
├── src/ishx/
│   ├── extract/  (mssql.py, keyset.py, cdc.py, state.py)
│   ├── fhir/     (mapper/<ressource>.py, terminology.py, ndjson.py)
│   ├── gold/     (marts.sql, build.py, fts.py)
│   ├── graph/    (schema.py, load.py)
│   ├── api/      (app.py, routes_*.py)
│   └── mcp/      (server.py, tools_*.py, guard.py, audit.py)
├── web/          (index.html, monitor.html, analytics.html, assets/)
├── mockups/      (die drei HTML-Mockups aus diesem Konzept)
└── tests/        (Golden-Record-Tests gegen 1 bekannten Testpatienten, ohne DB lauffähig via Fixtures)
```

## 12. Phasenplan

| Phase | Inhalt | Akzeptanz |
|---|---|---|
| 1 (Woche 1) | Extractor Tier-1-Backfill + State + Parquet | NPAT/NFAL/NBEW/NDIA/NICP vollständig in Bronze, Zeilenzahlen == Quelle |
| 2 | CDC via __ct, Merge, Scheduler | Inkrementlauf < 10 min, Dedup nachweisbar |
| 3 | FHIR-Mapper Kern (Patient, Encounter, Condition, Procedure, Observation, DocumentReference) | 1.000 Stichproben validieren fehlerfrei; Golden-Record-Patient korrekt |
| 4 | Gold-Marts + Dashboard | Mockup-Parität, Ladezeit < 2 s je Ansicht |
| 5 | Kuzu-Graph + MCP-Server | Patient-360-Frage im LLM in < 10 s beantwortet, Audit-Log vollständig |
| 6 | Härtung: Pseudonymisierung, Benutzerverwaltung, Doku | Freigabe Datenschutz |

## 13. Offene Punkte (vor Phase 1 klären)

1. Zugangsdaten/Auth für `replicate` aus dem Zielrechner (SQL-Auth vs. Windows/NTLM) und Lastfenster mit DB-Betrieb abstimmen.
2. Produktname (Vorschlagsliste folgt; „ishx" ist Arbeitstitel).
3. MANDT/EINRI-Scope: ein Mandant oder mehrere? (Filter fest verdrahten.)
4. LLM-Frontend fürs MCP: Claude Desktop (PC-A) vs. LibreChat + lokales Modell — Datenschutzentscheidung.
5. LOINC-Mapping für N2LABOR: hauseigenen Parameterkatalog exportieren lassen.
