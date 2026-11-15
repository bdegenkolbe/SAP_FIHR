# MCP-Anbindung

Der Server `sapfhir.mcp.server` spricht MCP über **stdio**, ohne Netz-Egress.

## Claude Desktop (PC-A, user-scope)
`%APPDATA%\Claude\claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "sapfhir": {
      "command": "%LOCALAPPDATA%\\greenbay\\sapfhir\\.venv\\Scripts\\python.exe",
      "args": ["-m", "sapfhir.mcp.server"],
      "cwd": "%LOCALAPPDATA%\\greenbay\\sapfhir"
    }
  }
}
```

## LibreChat via Supergateway (PC-A)
Wie die übrigen sieben MCP-Server: Supergateway bridgt stdio→SSE. Beispiel-Kommando:
```
npx -y supergateway --stdio "python -m sapfhir.mcp.server" --port 8790
```
LibreChat `librechat.yaml` → `mcpServers.sapfhir.url: http://127.0.0.1:8790/sse`.

## Vor jedem Rollout
Skill `windows-infra-preflight` ausführen — PC-A vs. PC-B unterscheiden
(Profil `BjörnDegenko_ii5jj9a` / `BJRNDE~2`, LibreChat `C:\ai\LibreChat`, Docker läuft).
`C:\ai\_ops\machine.json` lesen statt raten.

## Datenschutzentscheidung (offen)
Claude Desktop nutzt Anthropic-Endpunkte — nur mit freigegebener AVV/Konzern-Policy.
Andernfalls LibreChat + lokales Modell. Diese Wahl steht vor Produktivnutzung an
(siehe docs/CONCEPT.md §20). Der MCP-Server selbst gibt keine Daten nach außen; die
Datenweitergabe entsteht erst durch das gewählte LLM-Frontend.

---

## `sapfhir-live` — Live-Analyse auf der Replika (mit lernender Wissensschicht)

Zweiter MCP-Server neben `sapfhir`: arbeitet **direkt gegen `Replicate.sap.*`** (MSSQL,
read-only) statt auf dem DuckDB-Warehouse — für die DB-Erschließung nach
`Analyse_Datenbank.md` (Dreiklang) und Ad-hoc-Fragen (z.B. RKT/ZNRKT, §301,
Bewegungsketten). Ersetzt für Analysen den generischen `mssql`-MCP (@connorbritain), weil
nur dieser die **Verkryptungspflicht** durchsetzt.

**Warum eigener Server statt fertigem MCP** (Recherche 15.11.2026): Microsofts SQL MCP
Server (Data API builder) erlaubt kein freies SQL/keine Joins; die Community-Server
(connorbritain, RichardHan/mssql_mcp_server, DBHub, DonKonfetti) sind generisch und
liefern Namen/KVNR/Freitexte ungefiltert ans LLM. Konsens aller Quellen: harte Grenze ist
ein `db_datareader`-Login — der Guard ist die zweite Linie.

### Ein-Klick-Einrichtung (empfohlen)
Im Repo-Klon auf PC-A **`Start-LiveMCP.bat`** doppelklicken (kein Admin). Das Skript
(`tools/setup_live_mcp.ps1`, idempotent) macht: git pull → `.venv` + Abhängigkeiten →
`config/connection.yaml` (Host `s050008250.medizin.uni-leipzig.de` = 10.50.8.250, DB Replicate, Login `bdegenkolbe`, per
`-Login NAME` änderbar) → `SAPFHIR_PRIVACY_SECRET` → Passwort prüfen/abfragen und im
Credential Manager ablegen (bei Bedarf neu setzen) → Offline-Tests + Live-Selbsttest
(`tools/live_smoke.py`) → **Claude Code** benutzerweit (`claude mcp add --scope user`) plus
Repo-`.mcp.json`. Für **Claude Desktop** zeigt das Skript nur den Block an, der unter
Einstellungen → Entwickler → „Konfiguration bearbeiten“ einzufügen ist. Es schreibt
bewusst nicht selbst: Die Store-Version liest je nach Zustand eine virtualisierte Kopie
unter `%LOCALAPPDATA%\Packages\Claude_*\LocalCache` (Vorfall R35). Mit `-Launch` startet es danach Claude Code mit einem ersten RKT-Auftrag.

### Einrichtung von Hand (PC-A)
1. Login: dedizierter SQL-/AD-Login nur mit `db_datareader` (+ `db_denydatawriter`).
   `verbindung_pruefen` warnt, falls der Login Schreibrechte hat.
2. `config/connection.yaml` (Block `source`, wie für den Backfill; Host
   `s050008250.medizin.uni-leipzig.de` — voller Name, der Kurzname löst außerhalb der
   UKL-Domäne nicht auf; DB `Replicate`) — Passwort über Env `SAPFHIR_DB_PW` oder Windows Credential Manager
   (`sapfhir:<environment>`). Neu setzen + hinterlegen in einem Schritt:
   `powershell -ExecutionPolicy Bypass -File tools\set_db_password.ps1`
   (ALTER LOGIN über die eigene Windows-Anmeldung, Test-Login, Ablage per keyring;
   `-Generate` für Zufallspasswort, `-StoreOnly` wenn das Passwort bekannt ist).
3. `SAPFHIR_PRIVACY_SECRET` als Benutzer-Umgebungsvariable setzen (Salt für
   `PSEUDO()`; ohne ihn sind Pseudonyme nur innerhalb einer Sitzung vergleichbar).
4. `.mcp.json.example` → `.mcp.json` (Block `sapfhir-live`, `SAPFHIR_ROOT` = Repo- bzw.
   Installationsverzeichnis). Claude Desktop analog mit
   `"args": ["-m", "sapfhir.live.server"]`.
5. Test: Werkzeug `verbindung_pruefen`, dann `kontext("NFAL")`.

### Werkzeuge (16)
| Gruppe | Werkzeuge |
|---|---|
| Kontext | `kontext(tabelle)` — Registry, Projektion, PII-Felder, Fakten, Fallstricke, Joins, bewährte Abfragen · `wissen_suchen(frage)` — BM25 über Doku + Gelerntes |
| Dreiklang | `tabellen_suchen(muster)` · `tabelle_beschreiben` (Schema, PK DB vs. Registry, Zeilen) · `pk_pruefen` · `fuellgrade` · `werteverteilung` · `stichprobe` (PII automatisch pseudonymisiert) |
| Frei | `sql_lesen(sql, zweck)` — T-SQL, ein SELECT/WITH, max. 1000 Zeilen |
| Lernen | `merken` / `fakt_bewerten` (hypothese → verifiziert/widerlegt) · `abfrage_speichern` / `abfrage_ausfuehren` / `abfragen` · `wissen_export` |
| Betrieb | `verbindung_pruefen` |

### Schutz (Defense-in-Depth)
- **Guard** (`src/sapfhir/live/tsql_guard.py`): genau ein `SELECT`/`WITH`; keine Kommentare,
  Variablen, DML/DDL, `EXEC`, `INTO`, `OPENROWSET`, `xp_`/`sp_`, Lock-Hints; nur Schemas
  `sap`, `sys`, `INFORMATION_SCHEMA`; Tabellen schema-qualifiziert; keine Linked Server.
- **Verkryptung** (Policy `config/live_mcp.yaml`, Liste aus Analyse_Datenbank §4 + RKT-
  Freitexttabellen): Felder nur als `PSEUDO(f)` (serverseitig HASHBYTES-SHA256 mit Salt),
  `LEN`, `LEFT(f,1)`, `COUNT`, `IS [NOT] NULL`, `YEAR(GBDAT)`. Klartext, WHERE-Vergleiche
  (Orakel) und `SELECT *` auf solche Tabellen werden abgewiesen; `"*"`-Tabellen (NADR,
  N2TEXT, ZNRKT_*_TXT) live aus INFORMATION_SCHEMA aufgelöst. Gleichnamige Ergebnisspalten
  werden zusätzlich nachmaskiert.
- **Last**: `READ UNCOMMITTED`, `LOCK_TIMEOUT`, Query-Timeout, Massentabellen
  (NLEI, N2LABOR001 + alle gelernten >50 Mio) nur mit `WHERE`.
- **Audit**: `data/audit/live_mcp.jsonl` mit Hash-Kette (Parameter nur als Hash).

### Wie der Server lernt
Lokal in `data/knowledge/live.sqlite` (gitignored, kein Egress, **nie Ergebniszeilen**):
- jede Abfrage **ohne Literale** + Zweck → „bewährte Abfragen" je Tabelle
- Join-Paare aus erfolgreichen Abfragen (`T1.F1 = T2.F2`, gezählt) → „gelernte Joins"
- Fehlermeldungen → „Fallstricke" (z.B. `Invalid column name 'ENDAT'` → NFAL: Spalte
  ENDAT existiert nicht) — werden beim nächsten Fehler direkt mitgeliefert
- Schema, Zeilenzahlen, Füllgrade, Werteverteilungen (nur Aggregate) → Kontext; Tabellen
  >50 Mio werden automatisch Massentabellen
- explizite Fakten über `merken`/`fakt_bewerten`

Statisches Wissen (tables.yaml-Notizen, `config/columns/*`, CLAUDE.md, Analyse_Datenbank,
Datenkatalog, VERIFY_LOG, MD_MANAGEMENT_KONZEPT, BERECHTIGUNGSKONZEPT) wird bei jedem
Start neu indiziert. **Rückfluss ins Repo** nur per Mensch: `wissen_export` schreibt
`data/knowledge/wissen_export_<datum>.md` als Vorschlag für `config/tables.yaml` und
`docs/VERIFY_LOG_R8-R13.md` (CLAUDE.md-Arbeitsregel).
