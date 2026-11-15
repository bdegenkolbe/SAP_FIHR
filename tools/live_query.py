# -*- coding: utf-8 -*-
"""sapfhir-live im Terminal: dieselben Werkzeuge wie der MCP (Guard, Verkryptung,
Lernen, Audit) ohne Claude-Client.

Beispiele (im Repo-Root):
  .venv\\Scripts\\python tools\\live_query.py sql "SELECT FALAR, COUNT(*) n FROM sap.NFAL GROUP BY FALAR" --zweck "Fallarten"
  .venv\\Scripts\\python tools\\live_query.py werteverteilung NFAL FALAR
  .venv\\Scripts\\python tools\\live_query.py beschreiben ZNRKT_KOPF
  .venv\\Scripts\\python tools\\live_query.py stichprobe NPAT --n 5
  .venv\\Scripts\\python tools\\live_query.py tabellen "ZNRKT%"
  .venv\\Scripts\\python tools\\live_query.py kontext NFAL
  .venv\\Scripts\\python tools\\live_query.py suchen "Entlassart"
  .venv\\Scripts\\python tools\\live_query.py beispiel
"""
from __future__ import annotations
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from sapfhir.live.server import build_service  # noqa: E402

BEISPIEL_SQL = """
SELECT LEFT(CONVERT(varchar(8), f.BEGDT, 112), 4) AS jahr,
       f.FALAR                                    AS fallart,
       COUNT(*)                                   AS faelle
FROM sap.NFAL f
WHERE f.MANDT = '100' AND f.EINRI = '0001'
  AND (f.STORN IS NULL OR f.STORN = '')
  AND f.BEGDT >= '20220101'
GROUP BY LEFT(CONVERT(varchar(8), f.BEGDT, 112), 4), f.FALAR
ORDER BY jahr, fallart
"""


def _table(out) -> None:
    rows = out.get("zeilen") if isinstance(out, dict) else None
    if not rows:
        print(json.dumps(out, indent=2, ensure_ascii=False, default=str))
        return
    cols = out.get("spalten") or list(rows[0])
    w = {c: max(len(str(c)), *(len(str(r.get(c, ""))) for r in rows)) for c in cols}
    print("  ".join(str(c).ljust(w[c]) for c in cols))
    print("  ".join("-" * w[c] for c in cols))
    for r in rows:
        print("  ".join(str(r.get(c, "")).ljust(w[c]) for c in cols))
    extra = {k: v for k, v in out.items() if k not in ("zeilen", "spalten")}
    print(f"\n{json.dumps(extra, ensure_ascii=False, default=str)}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="sapfhir-live im Terminal")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sql"); s.add_argument("sql"); s.add_argument("--zweck", default="")
    s.add_argument("--max", type=int, default=0)
    s = sub.add_parser("werteverteilung"); s.add_argument("tabelle"); s.add_argument("feld")
    s.add_argument("--top", type=int, default=20)
    s = sub.add_parser("beschreiben"); s.add_argument("tabelle")
    s = sub.add_parser("fuellgrade"); s.add_argument("tabelle"); s.add_argument("felder", nargs="*")
    s = sub.add_parser("pk"); s.add_argument("tabelle"); s.add_argument("felder", nargs="*")
    s = sub.add_parser("stichprobe"); s.add_argument("tabelle"); s.add_argument("felder", nargs="*")
    s.add_argument("--n", type=int, default=10); s.add_argument("--where", default="")
    s = sub.add_parser("tabellen"); s.add_argument("muster", nargs="?", default="%")
    s = sub.add_parser("kontext"); s.add_argument("tabelle")
    s = sub.add_parser("suchen"); s.add_argument("frage")
    s = sub.add_parser("merken"); s.add_argument("aussage"); s.add_argument("--tabelle", default="")
    s.add_argument("--feld", default=""); s.add_argument("--status", default="hypothese")
    sub.add_parser("export")
    sub.add_parser("beispiel")
    a = ap.parse_args(argv)

    svc = build_service(".")
    c = a.cmd
    if c == "beispiel":
        print("Beispielabfrage: Faelle je Jahr und Fallart (ab 2022, ohne Stornos)\n")
        print(BEISPIEL_SQL.strip(), "\n")
        out = svc.sql_lesen(BEISPIEL_SQL, "Beispiel: Faelle je Jahr und Fallart", 200)
    elif c == "sql":
        out = svc.sql_lesen(a.sql, a.zweck, a.max)
    elif c == "werteverteilung":
        out = svc.werteverteilung(a.tabelle, a.feld, a.top)
    elif c == "beschreiben":
        out = svc.tabelle_beschreiben(a.tabelle)
        if "spalten" in out:
            out = {**out, "zeilen_tab": [{k: s[k] for k in ("spalte", "typ", "laenge", "pk", "verkryptet")}
                                         for s in out.pop("spalten")]}
            print(json.dumps({k: v for k, v in out.items() if k != "zeilen_tab"},
                             indent=2, ensure_ascii=False, default=str))
            out = {"zeilen": out["zeilen_tab"]}
    elif c == "fuellgrade":
        out = svc.fuellgrade(a.tabelle, a.felder or None)
    elif c == "pk":
        out = svc.pk_pruefen(a.tabelle, a.felder or None)
    elif c == "stichprobe":
        out = svc.stichprobe(a.tabelle, a.felder or None, a.n, a.where)
    elif c == "tabellen":
        out = svc.tabellen_suchen(a.muster)
    elif c == "kontext":
        out = svc.kontext(a.tabelle)
    elif c == "suchen":
        out = {"zeilen": svc.wissen_suchen(a.frage)}
    elif c == "merken":
        out = svc.merken(a.aussage, a.tabelle, a.feld, a.status)
    else:
        out = svc.wissen_export()
        out = {"datei": out["datei"]}
    _table(out)
    return 1 if isinstance(out, dict) and "fehler" in out else 0


if __name__ == "__main__":
    sys.exit(main())
