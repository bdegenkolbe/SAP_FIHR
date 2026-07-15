@echo off
set BASE=%LOCALAPPDATA%\greenbay\sapfhir
echo Entfernt %BASE% (inkl. lokaler Daten!).
choice /M "Wirklich loeschen"
if errorlevel 2 exit /b 0
rmdir /S /Q "%BASE%"
echo Entfernt.
pause
