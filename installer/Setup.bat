@echo off
REM SAP_FIHR — No-Admin-Installation. Kein Program Files, keine Registry, kein Dienst.
setlocal
set BASE=%LOCALAPPDATA%\greenbay\sapfhir
echo Installiere nach %BASE%
if not exist "%BASE%" mkdir "%BASE%"
xcopy /E /I /Y "%~dp0.." "%BASE%" >nul
cd /d "%BASE%"
where python >nul 2>&1
if errorlevel 1 (
  echo Python nicht gefunden. Bitte Python 3.11+ als Benutzer installieren
  echo   ^(python.org, Option "Install for me only"^) oder Python-embeddable nutzen.
  pause & exit /b 1
)
python -m venv .venv
call .venv\Scripts\activate.bat
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
if errorlevel 1 (
  echo FEHLER: Abhaengigkeiten konnten nicht installiert werden — Ausgabe oben pruefen.
  pause & exit /b 1
)
REM kuzu (Graph) optional nachziehen: nur fertige Wheels, nie aus Quellcode bauen.
REM Auf Python 3.14 gibt es (noch) kein Windows-Wheel -> Graph-Schritt wird uebersprungen.
python -m pip install --only-binary=:all: "kuzu>=0.6" >nul 2>&1
if errorlevel 1 echo Hinweis: kuzu nicht verfuegbar — Kuzu-Graph wird uebersprungen (Rest laeuft normal).
python -m pip install -e .
python installer\first_run.py
python -m pytest tests -q
if errorlevel 1 (
  echo WARNUNG: Tests fehlgeschlagen — Installation pruefen.
)
echo.
echo Fertig.
echo   Demo ohne DB:   %BASE%\Start-Demo.bat       (synthetische Daten + Dashboard)
echo   Dashboard:      %BASE%\Start-Dashboard.bat  (http://127.0.0.1:8471)
echo   MCP-Server:     %BASE%\Start-MCP.bat        (stdio, siehe docs\MCP_SETUP.md)
echo   Nightly-Lauf:   schtasks /Create /SC DAILY /ST 02:00 /TN sapfhir-nightly /TR "%BASE%\Nightly.bat"
pause
