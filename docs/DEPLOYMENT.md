# DEPLOYMENT — CliniBots Patient Insight: No-Admin-Installation & Betrieb (Windows)

Zielumgebung: Windows-Arbeitsplatz im Klinik-/Analytiknetz, **ohne Adminrechte**,
mit Netzzugang zur MSSQL-Replika (`replicate`). Alles läuft im Benutzerkontext.

> **Ist-Deployment auf MFAI_BDE_HOME (R19):** beide Apps laufen nativ (Patient Insight
> :8471, CliniBots MDM :8492), Autostart via `shell:startup` (Aufgabenplanung dort per
> Policy gesperrt), Verwaltung `C:\ai\_ops\ops.ps1`, Logs `C:\ai\_ops\logs\` — Details
> in `C:\ai\_ops\README.md`. Achtung: korrektes Python ist `pythoncore-3.14`
> (Kurzpfad `BJRNDE~2`), NICHT das Store-Python 3.13.
>
> **⚠ DIE Instanz ist `C:\ai\SAP_FIHR` (verbindlich, R31).** Dort liegen der
> Datenbestand (`data\warehouse.duckdb` mit der geladenen Kohorte) und der Code, auf den
> Autostart und `ops.ps1` zeigen (`start-patient-insight.ps1`: `Set-Location
> 'C:\ai\SAP_FIHR'`). **Deployen = in diesem Verzeichnis aktualisieren + `ops.ps1
> restart`** — NICHT irgendwohin kopieren.
>
> Der Installer (`installer\Setup.bat`, Abschnitt 1) legt eine EIGENSTÄNDIGE Kopie unter
> `%LOCALAPPDATA%\greenbay\sapfhir` an — das ist der Weg für eine Erstinstallation auf
> einem FREMDEN Rechner, nicht für diese Maschine. Existiert dort eine Alt-Kopie, ist sie
> nicht in Betrieb (kein Autostart-Eintrag) und trägt nur eine veraltete eigene
> `data\warehouse.duckdb`. Da darin pseudonymisierte Echtdaten liegen, sollte sie
> aufgeräumt werden (Löschkonzept: Verzeichnis-Wipe, CONCEPT §10).

## 1. Installation

```bat
:: 1) Repo/Release nach %LOCALAPPDATA%\greenbay\sapfhir entpacken
:: 2) Setup ausführen (prüft AppLocker, legt venv an, installiert Wheels)
installer\Setup.bat
```

`Setup.bat` macht (Muster GREENBAY clinical, `installer/first_run.py`):
- AppLocker-/SRP-Check: darf `python.exe` aus `%LOCALAPPDATA%` starten? Falls nein →
  Python-Embeddable-Fallback bzw. freigegebenen Pfad mit IT abstimmen.
- venv unter `%LOCALAPPDATA%\greenbay\sapfhir\.venv`, `pip install -r requirements.txt`
  (nur Wheels: pytds, duckdb, kuzu, pyarrow, fastapi, uvicorn, mcp — kein Compiler,
  kein ODBC-Treiber, kein Registry-Eintrag, kein Dienst).
- `config\connection.example.yaml` → `connection.yaml` kopieren (falls nicht vorhanden).

Danach Konfiguration setzen:
- `config/connection.yaml`: Host, DB, Auth (dedizierter Read-only-Login mit
  `db_datareader`; Passwort **nicht** in die Datei — Env `SAPFHIR_DB_PW`).
- Secrets als **Benutzer**-Umgebungsvariablen (`setx`, kein Admin nötig):
  `SAPFHIR_DB_PW`, `SAPFHIR_PRIVACY_SECRET` (HMAC-Secret; Verlust = Pseudonyme nicht
  mehr reproduzierbar → im Passwortmanager sichern, nie im Repo).

## 2. Verbindungs- und Rechte-Check (vor dem ersten Backfill)

```bash
python -m sapfhir.extract.dbsource --check --config config/connection.yaml
```
Prüft: Verbindung, `db_datareader`-Rolle (und dass **kein** `db_datawriter` vorliegt),
Sichtbarkeit der Kerntabellen, PK-Registry gegen `INFORMATION_SCHEMA` (CONCEPT §5).

## 2b. Ohne DB verproben (Abnahme der Installation)

```bat
Start-Demo.bat
:: entspricht: python tools\seed_demo.py --pipeline && python -m sapfhir.api.app
```
Erzeugt 500 synthetische Patienten (inkl. CDC-Delta-Beispielen), baut die komplette
Pipeline (bronze_current → FHIR → Gold → Graph → mcp.*-Views) und startet das
Dashboard auf `http://127.0.0.1:8471`. Der MCP-Server (`Start-MCP.bat`) ist damit
ebenfalls sofort testbar — ganz ohne Zugang zur Klinik-Replika.

## 3. Erstbefüllung (Backfill)

```bash
python -m sapfhir.extract.backfill --config config/connection.yaml --tier 1 --out data
```
- Läuft nur im konfigurierten Lastfenster (`extract.window`), pausiert außerhalb und
  setzt am Keyset-Cursor wieder auf — Abbruch (Strg+C, Reboot) ist jederzeit erlaubt.
- Reihenfolge: Tier 1 zuerst (eine Nacht), NLEI/Tier 2 separat (1–2 Nächte).
- Danach Reconciliation prüfen (Dashboard → Entlade-Monitor bzw.
  `_meta.reconciliation`), erst dann Phase CDC aktivieren.

## 4. Regelbetrieb (Scheduling ohne Admin)

Aufgabenplanung im **Benutzerkontext** (kein Admin, kein Dienstkonto):

```bat
schtasks /Create /SC DAILY /ST 02:00 /TN "sapfhir-nightly" ^
  /TR "%LOCALAPPDATA%\greenbay\sapfhir\installer\Nightly.bat"
```

`Nightly.bat` (Reihenfolge fix): CDC-Lauf → Compaction/Merge → Silver-Delta-Ausleitung
→ Gold-Build → Graph-Refresh → DQ-Checks. Jeder Schritt idempotent; Exit-Codes werden
in `data/logs/nightly-YYYYMMDD.log` protokolliert (Rotation 14 Tage).

Dashboard/MCP-Start bei Anmeldung optional per HKCU-Run-Key oder Aufgabenplanung
(`/SC ONLOGON`) — beides adminfrei.

## 5. Überwachung

- **Entlade-Monitor** (Dashboard, `127.0.0.1:8471`): Watermarks, CDC-Lag,
  Retention-Alarm, Reconciliation-Status, Durchsatz.
- Disk-Wächter: neue Backfill-/Compaction-Läufe brechen ab, wenn die Freigrenze
  (Default 30 GB) unterschritten ist — halbe Parquet-Dateien werden verworfen,
  der State bleibt konsistent.
- Audit-Log MCP: `data/audit/mcp.jsonl` (Hash-Kette, CONCEPT §17.4).

## 6. Update

```bat
:: Neues Release entpacken, dann:
installer\Setup.bat   :: idempotent; venv-Update, keine Datenmigration noetig
python -m pytest tests/ -q
```
Schema-Migrationen der `_meta`-Tabellen laufen automatisch beim ersten Start
(CREATE IF NOT EXISTS-Disziplin). Bronze/Silver sind versionsstabil (Parquet/NDJSON).

## 7. Backup & Wiederanlauf

Zu sichern (klein): `config/` (ohne Secrets), `_meta`-Export (Watermarks/State),
`config/loinc_map.csv` und Terminologie-Stände. **Getrennt und verschlüsselt**:
`SAPFHIR_PRIVACY_SECRET` und ggf. das Re-ID-Vault.
Nicht zu sichern: `data/bronze|silver|gold` — vollständig aus der Quelle reproduzierbar
(Backfill). Wiederanlauf nach Totalverlust: Setup → Config einspielen → Backfill.

## 8. Deinstallation / Löschkonzept

```bat
installer\Uninstall.bat
```
Entfernt geplante Aufgaben, HKCU-Run-Keys und das Programmverzeichnis. Datenlöschung =
Wipe von `data\` (dokumentieren für das Löschkonzept, CONCEPT §10/§20.12). Secrets
(`setx SAPFHIR_... ""`) und Claude-Desktop-/LibreChat-Konfigurationseinträge manuell
entfernen (`docs/MCP_SETUP.md`).

## 9. Lokal mit Claude Code + eigenem mssql-MCP arbeiten (PC-A)

Die Remote-Sessions (claude.ai/code) erreichen weder lokale MCP-Server noch die
On-Prem-Replika. Für Live-Verifikation deshalb **lokal** arbeiten:

```bat
:: 1) Projekt holen (Git for Windows vorausgesetzt; alternativ GitHub Desktop
::    oder "Code -> Download ZIP" im Browser)
git clone https://github.com/bdegenkolbe/SAP_FIHR.git
cd SAP_FIHR
git checkout claude/concept-analysis-expansion-nwg4ua

:: 2) Umgebung (optional, fuers Verproben): installer\Setup.bat
::    oder minimal:  python -m venv .venv && .venv\Scripts\pip install -r requirements.txt -e .

:: 3) mssql-MCP fuer dieses Projekt registrieren:
::    Variante a) .mcp.json.example -> .mcp.json kopieren, Command aus der
::    bestehenden %APPDATA%\Claude\claude_desktop_config.json uebernehmen
::    Variante b) per CLI:  claude mcp add mssql -- <startkommando-des-servers>

:: 4) Claude Code im Projektordner starten:
claude
```

Beim ersten Start fragt Claude Code, ob die Projekt-`.mcp.json` geladen werden
darf → bestätigen. Danach stehen die mssql-Tools in der lokalen Session bereit;
CLAUDE.md wird automatisch gelesen, der Arbeitsstand ist identisch mit dem Branch.
Ergebnisse (VERIFY-Läufe, Registry-Korrekturen) committen und pushen — dann kann
jede andere Session (auch die Remote-Session) nahtlos weitermachen.
`.mcp.json` ist gitignored (lokale Pfade/Secrets gehören nicht ins Repo).

## 10. Troubleshooting

| Symptom | Ursache/Abhilfe |
|---|---|
| `Login failed` trotz korrektem Passwort | SQL- vs. NTLM-Auth verwechselt (`source.auth`); bei NTLM `DOMAIN\user` als username |
| TLS-Fehler beim Connect | `encrypt: true` + Unternehmens-CA: `cafile` auf CA-Bundle setzen, **nicht** `trust_server_certificate: true` als Dauerlösung |
| Backfill bricht mit `Invalid column name 'EINRI'` | PK-Registry falsch (CONCEPT §5 PK-Validierung, ANALYSE A6) — `tables.yaml` korrigieren |
| CDC-Lauf meldet Retention-Lücke | Änderungen von Qlik abgeräumt → Re-Backfill der Tabelle (CONCEPT §14) |
| Dashboard-Port belegt | `api.port` in `connection.yaml` ändern (>1024) |
| AppLocker blockiert python.exe | `installer/first_run.py`-Report an IT; Embeddable-Python in freigegebenem Pfad |
| Abfragen im MCP brechen mit Timeout ab | gewollt (CONCEPT §17.3) — Query einschränken; Limits in `connection.yaml → mcp` |
