<#
.SYNOPSIS
  Ein Klick: sapfhir-live (Analyse-MCP auf der IS-H-Replika) auf diesem PC
  einrichten, testen und Claude Code damit starten. Idempotent - beliebig oft
  ausfuehrbar, ueberspringt Erledigtes.

.DESCRIPTION
  1. Repo aktualisieren (git pull --ff-only, falls sauberer Klon)
  2. Python >= 3.11 finden, .venv im Repo anlegen, Abhaengigkeiten + keyring
  3. config/connection.yaml anlegen (aus Beispiel, Login eingesetzt) bzw. lesen
  4. SAPFHIR_PRIVACY_SECRET (Salt fuer Pseudonyme) als Benutzer-Variable anlegen
  5. DB-Passwort im Windows Credential Manager pruefen, sonst abfragen
     (tools\set_db_password.ps1); bei falschem Passwort Neusetzen anbieten
  6. Offline-Tests + Live-Selbsttest (tools\live_smoke.py)
  7. .mcp.json + .claude\settings.local.json (MCP vorab freigegeben) schreiben
  8. Claude Code im Repo starten

  Kein Admin noetig. Start per Doppelklick auf Start-LiveMCP.bat im Repo-Root.
#>
[CmdletBinding()]
param(
  [string]$Login = "bdegenkolbe",
  [switch]$NoLaunch,        # Claude Code am Ende nicht starten
  [switch]$NoPull           # kein git pull
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

function Step($n, $t) { Write-Host ""; Write-Host "[$n/8] $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "  OK  $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  !!  $t" -ForegroundColor Yellow }
function Ask($q) {
  $a = Read-Host "$q (J/n)"
  return ($a -eq "" -or $a -match "^[JjYy]")
}
function Invoke-Quiet([scriptblock]$Block) {
  # Windows PowerShell 5.1: stderr-Umleitung nativer Programme wird bei
  # ErrorActionPreference=Stop zum Abbruch -> hier gezielt 'Continue'.
  # Skriptblock statt $args, damit Argumente wie --ff-only/-p unveraendert ankommen.
  $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { & $Block 2>$null } finally { $ErrorActionPreference = $old }
}
function Write-Utf8NoBom($path, $text) {
  [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
}

Write-Host "sapfhir-live Einrichtung in $Root" -ForegroundColor White

# --- 1. Repo aktualisieren ---------------------------------------------------------
Step 1 "Repo aktualisieren"
$git = Get-Command git -ErrorAction SilentlyContinue
if ($NoPull) { Ok "uebersprungen (-NoPull)" }
elseif (-not $git -or -not (Test-Path (Join-Path $Root ".git"))) { Warn "kein Git-Klon - uebersprungen" }
else {
  $dirty = & git status --porcelain --untracked-files=no
  $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
  if ($dirty) { Warn "lokale Aenderungen auf '$branch' - kein Pull" }
  else {
    Invoke-Quiet { git pull --ff-only --quiet } | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "Branch '$branch' aktuell" } else { Warn "git pull nicht moeglich - weiter mit lokalem Stand" }
  }
}

# --- 2. Python + venv ---------------------------------------------------------------
Step 2 "Python-Umgebung"
$Py = Join-Path $Root ".venv\Scripts\python.exe"
if (-not (Test-Path $Py)) {
  $base = $null
  foreach ($cand in @(@("py", "-3"), @("python"))) {
    $c = Get-Command $cand[0] -ErrorAction SilentlyContinue
    if (-not $c) { continue }
    $args2 = @($cand | Select-Object -Skip 1) + @("-c", "import sys; print(sys.executable); print('{}.{}'.format(*sys.version_info[:2]))")
    $exe = $c.Source
    $out = Invoke-Quiet { & $exe @args2 }
    if ($LASTEXITCODE -eq 0 -and $out.Count -ge 2) {
      $ver = [version]$out[1]
      if ($ver -ge [version]"3.11") { $base = $out[0]; break }
    }
  }
  if (-not $base) {
    throw "Python 3.11+ nicht gefunden. Installieren (python.org, 'Install for me only' - kein Admin) und Skript erneut starten."
  }
  Write-Host "  lege .venv an mit $base ..."
  & $base -m venv (Join-Path $Root ".venv")
  if ($LASTEXITCODE -ne 0) { throw "venv konnte nicht angelegt werden." }
}
Write-Host "  installiere/aktualisiere Abhaengigkeiten (kann beim ersten Mal dauern) ..."
& $Py -m pip install --quiet --disable-pip-version-check -r requirements.txt keyring
if ($LASTEXITCODE -ne 0) { throw "pip install fehlgeschlagen - Ausgabe oben pruefen (Proxy?)." }
& $Py -m pip install --quiet --disable-pip-version-check -e .
if ($LASTEXITCODE -ne 0) { throw "pip install -e . fehlgeschlagen." }
Ok ("Python " + (& $Py -c "import sys; print(sys.version.split()[0])"))

# --- 3. connection.yaml ---------------------------------------------------------------
Step 3 "Verbindungskonfiguration"
$conn = Join-Path $Root "config\connection.yaml"
if (-not (Test-Path $conn)) {
  $tpl = Get-Content (Join-Path $Root "config\connection.example.yaml") -Raw -Encoding UTF8
  $tpl = $tpl -replace "(?m)^(\s*username:\s*)\S+", "`${1}$Login"
  Write-Utf8NoBom $conn $tpl
  Ok "config\connection.yaml aus Beispiel angelegt (Login $Login)"
} else { Ok "config\connection.yaml vorhanden - unveraendert" }
$srcJson = & $Py -c "import yaml,json; c=yaml.safe_load(open('config/connection.yaml',encoding='utf-8')) or {}; print(json.dumps(c.get('source') or {}))"
$src = $srcJson | ConvertFrom-Json
if (-not $src.host) { throw "config\connection.yaml: 'source.host' fehlt." }
$envName = if ($src.environment) { $src.environment } else { "higl-main" }
Write-Host ("  Server {0}  DB {1}  Login {2}  Auth {3}" -f $src.host, $src.database, $src.username, $src.auth)
if ($src.password) { Warn "Passwort steht im Klartext in connection.yaml - besser leer lassen (Credential Manager)." }

# --- 4. Salt fuer Pseudonyme ---------------------------------------------------------
Step 4 "Pseudonymisierungs-Schluessel"
$salt = [Environment]::GetEnvironmentVariable("SAPFHIR_PRIVACY_SECRET", "User")
if (-not $salt) {
  $b = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  $salt = [Convert]::ToBase64String($b)
  [Environment]::SetEnvironmentVariable("SAPFHIR_PRIVACY_SECRET", $salt, "User")
  Ok "SAPFHIR_PRIVACY_SECRET neu erzeugt (Benutzer-Umgebungsvariable)"
} else { Ok "SAPFHIR_PRIVACY_SECRET vorhanden" }
$env:SAPFHIR_PRIVACY_SECRET = $salt

# --- 5. Passwort ---------------------------------------------------------------------
Step 5 "DB-Passwort (Windows Credential Manager)"
$pwScript = Join-Path $PSScriptRoot "set_db_password.ps1"
$pwArgs = @{ Server = $src.host; Login = $src.username; Environment = $envName; Python = $Py }
if ($src.database) { $pwArgs.Database = $src.database }
$has = & $Py -c "import sys,keyring; print(1 if keyring.get_password(sys.argv[1], sys.argv[2]) else 0)" "sapfhir:$envName" $src.username
if ($src.auth -eq "ntlm") { Ok "Windows-Authentifizierung konfiguriert - kein Passwort noetig" }
elseif ($src.password) { Ok "Passwort aus connection.yaml" }
elseif ($has -eq "1") { Ok "Passwort fuer '$($src.username)' ist hinterlegt" }
else {
  Write-Host "  Kein Passwort hinterlegt. Bekanntes Passwort eingeben:"
  $stored = $false
  for ($try = 1; $try -le 3 -and -not $stored; $try++) {
    try { & $pwScript @pwArgs -StoreOnly; $stored = $true }
    catch { Warn "Versuch $try fehlgeschlagen: $($_.Exception.Message)" }
  }
  if (-not $stored) {
    if (Ask "  Passwort fuer '$($src.username)' jetzt NEU SETZEN (braucht ALTER ANY LOGIN fuer deine Windows-Anmeldung)?") {
      & $pwScript @pwArgs
    } else { throw "Ohne gueltiges Passwort kein Live-Zugriff - Skript einfach erneut starten." }
  }
}

# --- 6. Tests ------------------------------------------------------------------------
Step 6 "Tests"
Invoke-Quiet { & $Py -m pytest tests -q -p no:cacheprovider } | Select-Object -Last 1 | ForEach-Object { Write-Host "  offline: $_" }
Write-Host "  Live-Selbsttest gegen $($src.host) ..."
& $Py tools\live_smoke.py
$rc = $LASTEXITCODE
if ($rc -eq 2 -and $src.auth -ne "ntlm" -and -not $src.password) {
  Warn "Hinterlegtes Passwort passt nicht."
  if (Ask "  Passwort neu eingeben (bekanntes Passwort)?") {
    try { & $pwScript @pwArgs -StoreOnly }
    catch {
      if (Ask "  Weiterhin falsch - Passwort NEU SETZEN?") { & $pwScript @pwArgs } else { throw }
    }
    & $Py tools\live_smoke.py
    $rc = $LASTEXITCODE
  }
}
if ($rc -eq 0) { Ok "Live-Selbsttest bestanden" }
else { Warn "Live-Selbsttest mit Fehlern (Ausgabe oben) - MCP wird trotzdem eingerichtet." }

# --- 7. MCP registrieren ----------------------------------------------------------------
Step 7 "MCP fuer Claude Code registrieren"
$mcpPath = Join-Path $Root ".mcp.json"
if (Test-Path $mcpPath) {
  $mcp = Get-Content $mcpPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $mcp = New-Object psobject }
if (-not ($mcp.PSObject.Properties.Name -contains "mcpServers")) {
  $mcp | Add-Member -NotePropertyName mcpServers -NotePropertyValue (New-Object psobject)
}
$entry = [ordered]@{
  command = $Py
  args    = @("-m", "sapfhir.live.server")
  env     = [ordered]@{ SAPFHIR_ROOT = $Root }
}
$mcp.mcpServers | Add-Member -NotePropertyName "sapfhir-live" -NotePropertyValue ([pscustomobject]$entry) -Force
Write-Utf8NoBom $mcpPath ($mcp | ConvertTo-Json -Depth 10)
Ok ".mcp.json: Server 'sapfhir-live' eingetragen"

$setDir = Join-Path $Root ".claude"
if (-not (Test-Path $setDir)) { New-Item -ItemType Directory $setDir | Out-Null }
$setPath = Join-Path $setDir "settings.local.json"
if (Test-Path $setPath) { $set = Get-Content $setPath -Raw -Encoding UTF8 | ConvertFrom-Json }
else { $set = New-Object psobject }
$list = @()
if ($set.PSObject.Properties.Name -contains "enabledMcpjsonServers") { $list = @($set.enabledMcpjsonServers) }
if ($list -notcontains "sapfhir-live") { $list += "sapfhir-live" }
$set | Add-Member -NotePropertyName enabledMcpjsonServers -NotePropertyValue $list -Force
Write-Utf8NoBom $setPath ($set | ConvertTo-Json -Depth 10)
Ok ".claude\settings.local.json: 'sapfhir-live' freigegeben (lokal, nicht im Repo)"

# --- 8. Claude Code starten --------------------------------------------------------------
Step 8 "Claude Code"
$claude = Get-Command claude -ErrorAction SilentlyContinue
if ($NoLaunch) { Ok "nicht gestartet (-NoLaunch). Spaeter: im Repo-Ordner 'claude' ausfuehren." }
elseif (-not $claude) {
  Warn "Claude Code (Befehl 'claude') nicht gefunden. Installation ohne Admin:"
  Write-Host "      npm install -g @anthropic-ai/claude-code   (oder: https://claude.com/claude-code)"
  Write-Host "      danach im Ordner $Root einfach 'claude' starten."
} else {
  Ok "starte Claude Code mit sapfhir-live ..."
  $prompt = "Nutze den MCP sapfhir-live: verbindung_pruefen, dann tabellen_suchen('ZNRKT%') und " +
            "kontext('ZNRKT_KOPF'). Fasse kurz zusammen, was wir zur RKT-Familie live sehen."
  & $claude.Source $prompt
}
