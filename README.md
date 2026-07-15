# SAP_FIHR — SAP IS-H / i.s.h.med → FHIR R4 (Read-only-Sekundärnutzung)

On-Prem-Werkzeug: liest **read-only** eine MSSQL-Replika von SAP IS-H / i.s.h.med
(`replicate`, Schemata `sap`/`hrp`) und exportiert den klinischen Bestand inkrementell
nach **FHIR R4** in einen lokalen Analysespeicher (Parquet + DuckDB). Dazu ein
Auswertungsdashboard und ein **MCP-Server** für natürlichsprachliche Patientenfragen im
LLM (DuckDB für SQL/Kohorten, **Kuzu** als eingebettete Graphdatenbank).

Klardaten verlassen die Maschine nicht. Installation und Betrieb **ohne Adminrechte**.
Reine Sekundärnutzung — **kein PVS, keine Rückschreibung, keine Abrechnung.**

Schwesterprojekt `Ingolf` (Praxis/medatixx) liefert die bewährten Bausteine; SAP_FIHR
übernimmt diese **ohne** den dortigen PVS-Ausbau.

## Struktur
```
SAP_FIHR/
├── CLAUDE.md                 # Arbeitsanleitung für Claude Code (zuerst lesen)
├── docs/
│   ├── CONCEPT.md            # Gesamtkonzept v0.2 + Architektur + Mengengerüst + Mapping
│   ├── ANALYSE.md            # Review-Befunde v0.1 → v0.2 (Lücken, Risiken, Prioritäten)
│   ├── DEPLOYMENT.md         # No-Admin-Installation, Scheduling, Betrieb, Backup
│   └── MCP_SETUP.md          # Claude Desktop / LibreChat-Anbindung
├── config/
│   ├── connection.example.yaml
│   ├── tables.yaml           # Datenlandkarte / Export-Registry (Tier, PK, CDC, FHIR)
│   └── columns/<tabelle>.yaml# Spaltenprojektion + Mapping-Hints (schmal statt 120 Spalten)
├── src/sapfhir/
│   ├── extract/  dbsource.py keyset.py cdc.py state.py backfill.py
│   ├── fhir/     ids.py privacy.py terminology.py ndjson.py mappers/*.py
│   ├── gold/     marts.sql build.py fts.py
│   ├── graph/    schema.py load.py
│   ├── api/      app.py
│   └── mcp/      server.py guard.py audit.py
├── web/          (Dashboard-SPA, vanilla JS, kein Build)
├── mockups/      (3 klickbare Prototypen, GREENBAY-CI)
├── installer/    Setup.bat first_run.py Uninstall.bat  (No-Admin)
└── tests/        (Fixtures, ohne DB lauffähig; Golden-Record-Test)
```

## Quickstart — Extraktion (im Klinik-/Analytiknetz)
```bash
pip install -r requirements.txt
cp config/connection.example.yaml config/connection.yaml   # Host, DB, Auth setzen

# Rechte-, Verbindungs- UND Registry-/PK-Check (validiert tables.yaml gegen die DB)
python -m sapfhir.extract.dbsource --check --config config/connection.yaml

# Backfill Tier 1 (Keyset-Pagination, Parquet, resümierbar, Lastfenster durchgesetzt)
python -m sapfhir.extract.backfill --config config/connection.yaml --tier 1 --out data

# Inkrement über Qlik-__ct-Change-Tables (Delta-Parquet + Retention-Wächter)
python -m sapfhir.extract.cdc --config config/connection.yaml --out data

# Merge-Views bronze_current.* + nächtliche Compaction (CONCEPT §14 — Pflichtschritt!)
python -m sapfhir.extract.merge --compact

# FHIR-Ausleitung (Silver, inkrementell, mit Index + Provenance) + Gold + Graph
python -m sapfhir.fhir.ndjson --config config/connection.yaml
python -m sapfhir.gold.build  --config config/connection.yaml
python -m sapfhir.graph.load  --config config/connection.yaml
```

## Quickstart — Dashboard + MCP
```bash
python -m sapfhir.api.app          # http://127.0.0.1:8471/
python -m sapfhir.mcp.server       # stdio-MCP für Claude Desktop / Supergateway→LibreChat
```

## Ohne DB verproben (synthetische Demo)
```bash
python tools/seed_demo.py --pipeline   # Bronze-Seed inkl. CDC-Deltas + komplette Pipeline
python -m sapfhir.api.app              # Dashboard öffnen: http://127.0.0.1:8471
```
Unter Windows übernimmt das `Start-Demo.bat` (wird von `installer/Setup.bat` erzeugt).

## Tests
```bash
python -m pytest tests/ -q
```

## Datenschutz
Besondere Kategorien (Art. 9 DSGVO). AV/Rechtsgrundlage vor Produktivbetrieb klären.
`privacy`-Modi: `off` (interner Klarbetrieb) · `pseudonymize` (HMAC + Date-Shift +
Freitext-De-ID) · `anonymize`. Re-ID-Vault getrennt. MCP ohne Netz-Egress.
