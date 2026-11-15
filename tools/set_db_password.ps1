<#
.SYNOPSIS
  Setzt das Passwort eines SQL-Logins auf der IS-H-Replika neu und hinterlegt es
  im Windows-Anmeldeinformationsspeicher fuer sapfhir (Backfill + sapfhir-live).

.DESCRIPTION
  1. Neues Passwort abfragen (verdeckt, zweimal) oder mit -Generate erzeugen.
  2. ALTER LOGIN ueber DEINE Windows-Anmeldung (Integrated Security) - dafuer
     braucht dein Windows-Login das Recht ALTER ANY LOGIN (wie in SSMS).
  3. Anmeldung mit dem neuen Passwort testen (SQL-Authentifizierung).
  4. Ablage im Windows Credential Manager ueber Python-keyring unter
     Dienst 'sapfhir:<Environment>', Konto = Login - genau dort sucht
     src/sapfhir/extract/dbsource.py, wenn in config/connection.yaml
     'password: ""' steht. Kein Klartext auf Platte, nicht in der Shell-History.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\set_db_password.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\set_db_password.ps1 -Generate
.EXAMPLE
  # Nur hinterlegen (Passwort ist bekannt, kein ALTER LOGIN):
  powershell -ExecutionPolicy Bypass -File tools\set_db_password.ps1 -StoreOnly
#>
[CmdletBinding()]
param(
  [string]$Server      = "s050008250.medizin.uni-leipzig.de",
  [int]$Port           = 1433,
  [string]$Login       = "bdegenkolbe",
  [string]$Database    = "Replicate",
  [string]$Environment = "higl-main",
  [string]$Python      = "$env:LOCALAPPDATA\greenbay\sapfhir\.venv\Scripts\python.exe",
  [switch]$Generate,          # starkes Zufallspasswort erzeugen statt abfragen
  [switch]$StoreOnly,         # kein ALTER LOGIN, nur testen + hinterlegen
  [switch]$Encrypt            # TLS fuer die Testverbindungen erzwingen
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Data

function ConvertTo-Plain([Security.SecureString]$s) {
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function New-StrongPassword([int]$len = 24) {
  # nur ASCII ohne Anfuehrungszeichen/Semikolon (Connection-String-sicher)
  $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%*+-=?@_".ToCharArray()
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  $bytes = New-Object byte[] $len
  $rng.GetBytes($bytes)
  -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

function Get-ConnString([string]$auth) {
  $enc = if ($Encrypt) { "True" } else { "False" }
  "Server=tcp:$Server,$Port;Database=master;$auth;Encrypt=$enc;TrustServerCertificate=True;Application Name=sapfhir-set-password;Connect Timeout=15"
}

# --- 1. Passwort ---------------------------------------------------------------
if ($Generate) {
  $plain = New-StrongPassword
  Write-Host "Starkes Zufallspasswort erzeugt (wird nicht angezeigt, nur hinterlegt)."
} elseif ($StoreOnly) {
  # vorhandenes Passwort: einmal abfragen, Pruefung erfolgt durch den Test-Login
  Write-Host "  (Einfuegen in der Konsole: RECHTSKLICK - Strg+V funktioniert hier nicht)"
  $p1 = Read-Host "Vorhandenes Passwort fuer SQL-Login '$Login'" -AsSecureString
  $plain = ConvertTo-Plain $p1
  if (-not $plain) { throw "Kein Passwort eingegeben." }
} else {
  Write-Host "  (Einfuegen in der Konsole: RECHTSKLICK - Strg+V funktioniert hier nicht)"
  $p1 = Read-Host "NEUES Passwort fuer SQL-Login '$Login'" -AsSecureString
  $p2 = Read-Host "Neues Passwort wiederholen" -AsSecureString
  $plain = ConvertTo-Plain $p1
  if ($plain -ne (ConvertTo-Plain $p2)) { throw "Passwoerter stimmen nicht ueberein." }
  if ($plain.Length -lt 12) { throw "Neues Passwort: bitte mindestens 12 Zeichen." }
  if ($plain -match '[;"]') { throw "Bitte kein ';' oder '""' (Connection-String)." }
}

# --- 2. ALTER LOGIN ueber Windows-Anmeldung --------------------------------------
if (-not $StoreOnly) {
  Write-Host "Setze Passwort fuer [$Login] auf $Server (Windows-Anmeldung $env:USERDOMAIN\$env:USERNAME) ..."
  $cn = New-Object System.Data.SqlClient.SqlConnection (Get-ConnString "Integrated Security=SSPI")
  $cn.Open()
  try {
    $cmd = $cn.CreateCommand()
    # Passwort als Parameter, Statement per QUOTENAME gebaut -> keine SQL-Injection,
    # Passwort taucht nicht im Statement-Text des Plan-Cache auf.
    $cmd.CommandText = @"
DECLARE @sql nvarchar(max) =
  N'ALTER LOGIN ' + QUOTENAME(@login) + N' WITH PASSWORD = ' + QUOTENAME(@pw, N'''');
EXEC sys.sp_executesql @sql;
"@
    [void]$cmd.Parameters.Add("@login", [Data.SqlDbType]::NVarChar, 128)
    [void]$cmd.Parameters.Add("@pw", [Data.SqlDbType]::NVarChar, 128)
    $cmd.Parameters["@login"].Value = $Login
    $cmd.Parameters["@pw"].Value = $plain
    [void]$cmd.ExecuteNonQuery()
  } finally { $cn.Close() }
  Write-Host "  OK: Passwort gesetzt."
}

# --- 3. Test mit SQL-Authentifizierung -----------------------------------------
Write-Host "Teste Anmeldung als '$Login' ..."
$b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder (Get-ConnString "Integrated Security=False")
$b["User ID"] = $Login
$b["Password"] = $plain
$b["Initial Catalog"] = $Database
$cn = New-Object System.Data.SqlClient.SqlConnection $b.ConnectionString
$cn.Open()
try {
  $cmd = $cn.CreateCommand()
  $cmd.CommandText = "SELECT @@SERVERNAME, DB_NAME(), SUSER_SNAME(), " +
    "IS_ROLEMEMBER('db_datareader'), IS_ROLEMEMBER('db_datawriter'), IS_ROLEMEMBER('db_owner')"
  $r = $cmd.ExecuteReader()
  [void]$r.Read()
  Write-Host ("  OK: Server={0}  DB={1}  Login={2}" -f $r[0], $r[1], $r[2])
  if (($r[4] -eq 1) -or ($r[5] -eq 1)) {
    Write-Warning "Login hat SCHREIBRECHTE in $Database. Fuer sapfhir/MCP besser einen reinen db_datareader-Login verwenden."
  } elseif ($r[3] -ne 1) {
    Write-Warning "Login ist nicht in db_datareader - Lesezugriff auf sap.* pruefen."
  }
  $r.Close()
} finally { $cn.Close() }

# --- 4. Ablage im Windows Credential Manager (keyring) --------------------------
if (-not (Test-Path $Python)) {
  $cmdPy = Get-Command py -ErrorAction SilentlyContinue
  if ($cmdPy) { $Python = $cmdPy.Source } else { throw "Python nicht gefunden: $Python (Parameter -Python angeben)." }
}
$old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
try { & $Python -c "import keyring" 2>$null } finally { $ErrorActionPreference = $old }
if ($LASTEXITCODE -ne 0) {
  Write-Host "Installiere keyring (user-space) ..."
  & $Python -m pip install --quiet keyring
  if ($LASTEXITCODE -ne 0) { throw "pip install keyring fehlgeschlagen." }
}
$svc = "sapfhir:$Environment"
# Passwort ueber stdin (nicht als Argument -> nicht in Prozessliste/History)
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$py = "import sys,keyring; pw=sys.stdin.buffer.readline().decode('utf-8-sig').rstrip('\r\n'); " +
      "keyring.set_password(sys.argv[1], sys.argv[2], pw); " +
      "print('OK' if keyring.get_password(sys.argv[1], sys.argv[2]) == pw else 'MISMATCH')"
$res = $plain | & $Python -c $py $svc $Login
if ($res -ne "OK") { throw "Ablage im Credential Manager fehlgeschlagen ($res)." }
Write-Host "  OK: hinterlegt im Windows Credential Manager (Dienst '$svc', Konto '$Login')."

$plain = $null; $p1 = $null; $p2 = $null
[GC]::Collect()

Write-Host ""
Write-Host "In config/connection.yaml (Block 'source'):"
Write-Host "  host: $Server"
Write-Host "  database: $Database"
Write-Host "  auth: sql"
Write-Host "  username: $Login"
Write-Host "  password: `"`"          # leer -> Credential Manager"
Write-Host "  environment: $Environment"
Write-Host "  trust_server_certificate: true   # falls kein Haus-Zertifikat"
