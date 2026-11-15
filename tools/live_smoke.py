# -*- coding: utf-8 -*-
"""Selbsttest sapfhir-live gegen die echte Replika (ohne MCP-Client).

Prueft: Verbindung + Rechte, Tabellenliste (RKT), Schema einer Kerntabelle,
Wissensschicht, Verkryptungs-Guard. Gibt nur Aggregate/Metadaten aus.
Exit 0 = alles ok, 2 = Anmeldung gescheitert, 1 = sonstiger Fehler.

Aufruf (im Repo-Root):  .venv\\Scripts\\python tools\\live_smoke.py
"""
from __future__ import annotations
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from sapfhir.live.server import build_service  # noqa: E402

_LOGIN_ERR = ("login failed", "anmeldung", "18456", "password", "kennwort")


def main() -> int:
    svc = build_service(".")
    print("1) Verbindung ...")
    try:
        info = svc.verbindung_pruefen()
    except Exception as e:  # noqa: BLE001
        msg = str(e)
        print(f"   FEHLER: {msg[:300]}")
        return 2 if any(k in msg.lower() for k in _LOGIN_ERR) else 1
    print(f"   Server {info.get('version')} ({info.get('edition')}), DB {info.get('db')}, "
          f"Login {info.get('login')}")
    if info.get("warnung"):
        print(f"   WARNUNG: {info['warnung']}")
    if not info.get("salt_stabil"):
        print("   Hinweis: SAPFHIR_PRIVACY_SECRET fehlt — Pseudonyme nur je Sitzung stabil.")

    print("2) Tabellen RKT (ZNRKT%) ...")
    t = svc.tabellen_suchen("ZNRKT%")
    if "fehler" in t:
        print(f"   FEHLER: {t['fehler']}")
        return 1
    rows = t["zeilen"]
    print(f"   {len(rows)} Tabellen, z.B. " +
          ", ".join(f"{r['tabelle']} ({int(r['zeilen'] or 0):,})".replace(",", ".")
                    for r in rows[:5]))

    print("3) Schema NFAL ...")
    d = svc.tabelle_beschreiben("NFAL")
    if "fehler" in d:
        print(f"   FEHLER: {d['fehler']}")
        return 1
    print(f"   {len(d['spalten'])} Spalten, PK DB {d['pk_db']} / Registry {d['pk_registry']}"
          f"{'  ABWEICHUNG!' if d['pk_abweichung'] else ''}, Zeilen {d['zeilen']}")

    print("4) Verkryptungs-Guard ...")
    g = svc.sql_lesen("SELECT TOP 1 NNAME FROM sap.NPAT", zweck="Selbsttest Guard")
    ok_guard = "fehler" in g and "verkryptungspflichtig" in g["fehler"]
    print("   OK (Klartextname abgewiesen)" if ok_guard else f"   FEHLER: {g}")

    print("5) Wissensschicht ...")
    k = svc.kontext("NFAL")
    print(f"   Registry-PK {k['registry'].get('pk')}, Schema-Cache {len(k['schema_cache'])} "
          f"Spalten, {len(svc.wissen_suchen('RKT Reklamation'))} Treffer 'RKT Reklamation'")
    return 0 if ok_guard else 1


if __name__ == "__main__":
    sys.exit(main())
