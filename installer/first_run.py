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
    for d in ("data", "data/bronze", "data/silver", "data/audit"):
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
    print("Startskripte erzeugt.")

if __name__ == "__main__":
    main()
