@echo off
REM sapfhir-live: alles einrichten, testen und Claude Code starten (kein Admin noetig).
REM Optionen: -Login NAME, -Launch (Claude Code starten), -NoPull
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\setup_live_mcp.ps1" %*
if errorlevel 1 (
  echo.
  echo FEHLER - Ausgabe oben pruefen.
)
pause
