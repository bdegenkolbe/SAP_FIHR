# -*- coding: utf-8 -*-
"""Append-only-Audit-Log fuer MCP-Zugriffe (JSONL) mit Hash-Kette (CONCEPT §17.4).

Protokolliert je Tool-Aufruf: Zeit, Tool, Parameter-Hash (nie Klarparameter — keine
Patientennamen ins Log), Trefferzahl, Dauer. Jede Zeile traegt
    entry_hash = sha256(prev_hash + kanonisches JSON der Zeile)
— nachtraegliche Manipulation oder geloeschte Zeilen brechen die Kette.
Fuer Nachweisbarkeit der Sekundaernutzung (Art. 30/32 DSGVO).

Pruefung:  python -m sapfhir.mcp.audit --verify data/audit/mcp.jsonl
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import time

_GENESIS = "0" * 64


def _entry_hash(prev: str, rec: dict) -> str:
    payload = json.dumps(rec, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256((prev + payload).encode("utf-8")).hexdigest()


class Audit:
    def __init__(self, path: str = "data/audit/mcp.jsonl"):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.path = path
        self._prev = self._last_hash()

    def _last_hash(self) -> str:
        if not os.path.exists(self.path):
            return _GENESIS
        last = None
        with open(self.path, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    last = line
        if not last:
            return _GENESIS
        try:
            return json.loads(last).get("entry_hash", _GENESIS)
        except json.JSONDecodeError:
            return _GENESIS

    def log(self, tool: str, params: dict, rows: int, duration: float,
            ok: bool = True, err: str | None = None):
        phash = hashlib.sha256(
            json.dumps(params, sort_keys=True, default=str).encode()).hexdigest()[:16]
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "tool": tool,
               "param_hash": phash, "rows": rows, "dur_s": round(duration, 3),
               "ok": ok}
        if err:
            rec["err"] = err[:200]
        rec["entry_hash"] = _entry_hash(self._prev, rec)
        self._prev = rec["entry_hash"]
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def verify(path: str) -> tuple[bool, int]:
    """Prueft die Hash-Kette. Liefert (ok, gepruefte Zeilen)."""
    prev = _GENESIS
    n = 0
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            rec = json.loads(line)
            want = rec.pop("entry_hash", None)
            if _entry_hash(prev, rec) != want:
                return False, n
            prev = want
            n += 1
    return True, n


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", metavar="DATEI", required=True)
    args = ap.parse_args(argv)
    ok, n = verify(args.verify)
    print(f"Hash-Kette {'OK' if ok else 'GEBROCHEN'} ({n} Eintraege geprueft)")
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
