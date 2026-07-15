# CLAUDE.md — Arbeitsanleitung für Claude Code

Kontext, um an diesem Projekt zu arbeiten, ohne alle Dokumente neu zu erschließen.
Details in `docs/`. Einstieg immer: `docs/CONCEPT.md`.

## Was das Projekt ist
Ein On-Prem-Werkzeug, das **read-only** eine MSSQL-Replika von **SAP IS-H / i.s.h.med**
ausliest (Datenbank `replicate`, Schemata `sap` und `hrp`, gespeist von Qlik Replicate)
und den klinischen Bestand inkrementell nach **FHIR R4** in einen lokalen, spalten-
orientierten Analysespeicher (Parquet + DuckDB) exportiert. Darauf: ein Auswertungs-
dashboard und ein **MCP-Server**, über den ein LLM natürlichsprachliche Fragen zum
Patienten stellt (DuckDB für Kohorten/SQL, **Kuzu** als eingebettete Graphdatenbank für
Patient-Fall-Bewegung-Diagnose-Beziehungen).

Schwesterprojekt `Ingolf` (medatixx/Praxis) liefert die bewährten Muster (dbsource,
privacy, Registry-getriebener Export, Golden-Record-Test). **Dieses Projekt übernimmt
diese Muster, aber NICHT den PVS-Ausbau.**

Randbedingungen (nicht verhandelbar):
- Reine **Sekundärnutzung**. Kein Schreiben in SAP, keine KIS-/PVS-Funktion, keine
  Abrechnung, keine Arbeitsliste, keine Primärdokumentation. §301/DRG nur lesend als Analytik.
- Klardaten verlassen die Maschine nicht. Pseudonymisierung/Date-Shift ist Export-Option.
- Installation und Betrieb **ohne Adminrechte** (siehe `docs/DEPLOYMENT.md`).
- Read-only auf die Quelle (dedizierter Login `db_datareader`).

## Abgrenzung zu Ingolf (WICHTIG)
Aus Ingolf übernommen: `dbsource` (pyodbc→pytds-Fallback), `privacy` (HMAC-Pseudonyme,
per-Patient-Date-Shift, wertbasiertes `hash_id`, Freitext-De-ID, Gate enforce/warn/off),
Registry-Ansatz (`tables.yaml`), stabile FHIR-IDs (uuid5), idempotenter Upsert,
Golden-Record-Test, No-Admin-Store.
**NICHT übernommen: der gesamte `pvs/`-Zweig** (klinischer Kernel/Ereignisstrom,
Fall/Schein-Aggregat, KVDT/ADT-Serializer, GOÄ/PADneXt-Rechnung, Strangler-Migration).
SAP_FIHR bleibt Read-only-Analytik.

## Quelle (verifiziert 15.07.2026)
- MSSQL `replicate`, Schema `sap` (1.152 Basistab.) + `hrp` (~101). CDC über Qlik-`__ct`.
- IS-H-Kern: NPAT, NFAL, NBEW, NDIA/NDIP, NICP, NLEI, NDRG, NDOC, N2TEXT, N2LABOR,
  NORG/NGPA/NADR, NKTR/NFPZ (Kostenträger/Versicherung), NC301* (§301).
- i.s.h.med: N1CORDER/N1ANF (Aufträge), N2TEXT (Dok.), N2LABOR (Befunde).
- HR/Orga: hrp.HRP1000/HRP1001, hrp.PA0001-0003 (→ Practitioner).
- Mengengerüst siehe `docs/CONCEPT.md` §2. Größte Tabelle NLEI ≈ 210 Mio Zeilen.

## Verifikationsdisziplin
Feldkennungen und Enum-Kodierungen, die noch nicht gegen die Live-DB bzw. offizielle
Doku (sapdatasheet.org, SAP IS-H Datenmodell) geprüft sind, sind im Code mit `# VERIFY`
markiert. Vor Produktivlauf auflösen — nicht raten. NPAT/NFAL/NBEW sind gegen die
Live-`replicate` verifiziert; NDIA/NICP/N2LABOR-Detailfelder sind `# VERIFY`.

## Baureihenfolge (Roadmap — Details + Akzeptanzkriterien in docs/CONCEPT.md §12)
Phase 1:  dbsource + Rechte-/PK-Check + `tables.yaml`-Registry + Spaltenkataloge aller
          Tier-1-Tabellen + Keyset-Backfill Tier 1 → Parquet (Lastfenster durchgesetzt).
Phase 2a: CDC über `__ct` als Delta-Parquet + Watermark-State + Retention-Lückenerkennung.
Phase 2b: Merge-Views `bronze_current.*` + nächtliche Compaction (CONCEPT §14) —
          ohne diesen Schritt sehen Gold/Silver/MCP keine CDC-Änderungen!
Phase 3:  FHIR-Mapper Kern (Patient, Encounter, Condition, Procedure, Observation,
          DocumentReference) mit subject-Lookup FALNR→PATNR, durchgängigem Date-Shift,
          Provenance + FHIR-Index (CONCEPT §16), gegen Golden-Record-Patient.
Phase 4:  Gold-Marts (DuckDB, über bronze_current) + Dashboard (FastAPI 127.0.0.1:8471)
          inkl. DQ-Kacheln (CONCEPT §15).
Phase 5:  Kuzu-Graph + MCP-Server (7 Tools) mit Härtung nach CONCEPT §17
          (Sandbox-DuckDB, mcp.*-Views, Timeouts, Parameter-Hash-Audit).
Phase 6:  Härtung — Pseudonymisierung End-to-End, Benutzerverwaltung, DSFA-Freigabe.

Vor Implementierungsarbeit an einer Phase: `docs/ANALYSE.md` lesen — dort sind die
bekannten Lücken des v0.1-Skeletts (z. B. CDC-Merge fehlt, MCP liest Bronze-Klardaten,
Date-Shift inkonsistent, NPAT-PK fraglich) mit Datei-/Zeilenbezug priorisiert.

## Konventionen
- Python 3.11+, stdlib-first. DB treiberfrei über `pytds` (No-Admin); `pyodbc` optional.
- Analysespeicher: DuckDB-Datei (kein Dienst, kein Admin). Graph: Kuzu (embedded, Cypher).
- FHIR-IDs stabil per uuid5 (idempotenter Upsert). Datumswerte laufen durch Date-Shift.
- Kodiersysteme: ICD-10-GM, OPS, ATC, LOINC (Map-Konfig), UCUM.
- Schlüssel im IS-H immer mandantenscharf: (MANDT, EINRI, FALNR/PATNR, LFDNR).

## Tests (ohne DB lauffähig)
`python -m pytest tests/ -q` — Fixtures statt Live-DB. Golden-Record-Test mit fixierten
Sollwerten für einen bekannten Testfall (`tests/test_golden.py`).

## Datenschutz
Verarbeitung besonderer Kategorien (Art. 9 DSGVO). AV/Rechtsgrundlage vor Produktivbetrieb
klären (Christopher Schrey). Re-ID-Vault getrennt sichern, niemals in Exporte/Analysezone.
MCP-Server hat keinen Netz-Egress. LLM-Frontend-Entscheidung (Claude Desktop vs. LibreChat
+ lokales Modell) ist eine Datenschutzentscheidung — siehe `docs/CONCEPT.md` §20.
