# sapfhir-Paket — Drop-in für das Claude-Code-Repo

Stand: R16 (16.07.2026). Inhalt und Zielpfade (Struktur entspricht dem bestehenden Repo
mit `src/sapfhir/...`-Layout, aus dem test_core.py importiert):

| Paketdatei | Zielpfad im Repo | Aktion |
|---|---|---|
| `CLAUDE.md` | `CLAUDE.md` | neu/ersetzen (Projektanweisung für Claude Code) |
| `docs/Analyse_Datenbank.md` | `docs/` | neu (verbindliche Methode) |
| `docs/VERIFY_LOG_R8-R13.md` | `docs/` | neu (Rundenprotokoll R8–R16) |
| `config/tables.yaml` | `config/tables.yaml` | ERSETZEN (76 Tabellen, PKs verifiziert) |
| `src/sapfhir/fhir/mappers/core.py` | ebenda | ERSETZEN (Mapper R8–R16) |
| `src/sapfhir/fhir/normalize.py` | ebenda | NEU (ISO-8601-Pipeline-Schritt) |
| `tests/test_core.py` | `tests/` | ERSETZEN (55 Tests; braucht ids/privacy/guard aus Repo) |
| `tests/test_normalize.py` | `tests/` | NEU (7 Tests, laufen standalone) |

Nicht im Paket (bleiben aus dem bestehenden Repo): `src/sapfhir/fhir/ids.py`,
`src/sapfhir/fhir/privacy.py`, `src/sapfhir/mcp/guard.py`, `ndjson.py`/Pipeline.

## Integrationsschritte
1. Dateien gemäß Tabelle kopieren (core.py/tables.yaml/test_core.py überschreiben Altstand).
2. `python -m pytest tests/ -q` — test_normalize läuft sofort; test_core braucht die
   bestehenden Module ids/privacy/guard.
3. `normalize_resource()` in der NDJSON-Pipeline NACH priv.shift einhängen
   (siehe Docstring in normalize.py).
4. Neue Mapper-Signaturen (Pipeline-Lookups nötig):
   - `map_encounter(row, ns, priv, bewegungen=, apxnr=, personal=, verknuepfungen=)`
   - `map_procedure(row, ns, priv, patnr=, team=)`
   - `map_coverage(row, ns, priv, vvp=)` · `map_condition(row, ns, priv, kodetext=)`
   - neu: `map_account_napx`, `map_servicerequest`, `map_practitioner_nper`,
     `map_organization_das301`, `map_organization_norg`, `map_location_bau(adr=, struktur=, hierarchie=)`
5. Danach Backlog aus `docs/Analyse_Datenbank.md` §8 abarbeiten.
