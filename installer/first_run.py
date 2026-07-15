# -*- coding: utf-8 -*-
"""Erstlauf-Check ohne Adminrechte: AppLocker/WDAC-Status, Verzeichnisse, Config-Kopie."""
import os, shutil, subprocess, sys

def check_applocker():
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Get-AppLockerPolicy -Effective -ErrorAction SilentlyContinue | Out-String"],
            capture_output=True, text=True, timeout=30).stdout
        return "kein AppLocker aktiv" if not out.strip() else "AppLocker-Policy vorhanden (pruefen)"
    except Exception as e:
        return f"AppLocker-Status unbekannt ({e})"

def main():
    base = os.getcwd()
    for d in ("data", "data/bronze", "data/silver", "data/audit", "data/logs"):
        os.makedirs(os.path.join(base, d), exist_ok=True)
    cfg = os.path.join(base, "config", "connection.yaml")
    ex = os.path.join(base, "config", "connection.example.yaml")
    if not os.path.exists(cfg) and os.path.exists(ex):
        shutil.copy(ex, cfg)
        print(f"config/connection.yaml angelegt — bitte Host/DB/Auth eintragen.")
    print("AppLocker:", check_applocker())
    # Startskripte
    with open(os.path.join(base, "Start-Dashboard.bat"), "w") as f:
        f.write("@echo off\r\ncall .venv\\Scripts\\activate.bat\r\n"
                "python -m sapfhir.api.app\r\n")
    with open(os.path.join(base, "Start-MCP.bat"), "w") as f:
        f.write("@echo off\r\ncall .venv\\Scripts\\activate.bat\r\n"
                "python -m sapfhir.mcp.server\r\n")
    with open(os.path.join(base, "Start-Demo.bat"), "w") as f:
        f.write("@echo off\r\ncall .venv\\Scripts\\activate.bat\r\n"
                "python tools\\seed_demo.py --pipeline\r\n"
                "python -m sapfhir.api.app\r\n")
    # Nightly: CDC -> Compaction -> Silver-Delta -> Gold -> Graph -> DQ
    # (docs/DEPLOYMENT.md §4; per schtasks im Benutzerkontext einplanen)
    with open(os.path.join(base, "Nightly.bat"), "w") as f:
        f.write("@echo off\r\ncd /d %~dp0\r\ncall .venv\\Scripts\\activate.bat\r\n"
                "set LOG=data\\logs\\nightly-%DATE:~-4%%DATE:~-7,2%%DATE:~-10,2%.log\r\n"
                "echo === CDC ===>> %LOG%\r\n"
                "python -m sapfhir.extract.cdc --config config\\connection.yaml >> %LOG% 2>&1\r\n"
                "echo === Merge/Compaction ===>> %LOG%\r\n"
                "python -m sapfhir.extract.merge --compact >> %LOG% 2>&1\r\n"
                "echo === Silver (FHIR) ===>> %LOG%\r\n"
                "python -m sapfhir.fhir.ndjson --config config\\connection.yaml >> %LOG% 2>&1\r\n"
                "echo === Gold + DQ ===>> %LOG%\r\n"
                "python -m sapfhir.gold.build --config config\\connection.yaml >> %LOG% 2>&1\r\n"
                "echo === Graph ===>> %LOG%\r\n"
                "python -m sapfhir.graph.load --config config\\connection.yaml >> %LOG% 2>&1\r\n"
                "echo === Fertig %DATE% %TIME% ===>> %LOG%\r\n")
    print("Startskripte erzeugt (Start-Dashboard/Start-MCP/Start-Demo/Nightly).")

if __name__ == "__main__":
    main()
