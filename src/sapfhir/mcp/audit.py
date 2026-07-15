# -*- coding: utf-8 -*-
"""Append-only-Audit-Log fuer MCP-Zugriffe (JSONL).

Protokolliert je Tool-Aufruf: Zeit, Tool, Parameter-Hash (nicht Klarparameter, um
keine Klarnamen ins Log zu schreiben), Trefferzahl, Dauer. Fuer Nachweisbarkeit der
Sekundaernutzung (Art. 30/32 DSGVO).
"""
from __future__ import annotations
import hashlib
import json
import os
import time


class Audit:
    def __init__(self, path: str = "data/audit/mcp.jsonl"):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.path = path

    def log(self, tool: str, params: dict, rows: int, duration: float,
            ok: bool = True, err: str | None = None):
        phash = hashlib.sha256(
            json.dumps(params, sort_keys=True, default=str).encode()).hexdigest()[:16]
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "tool": tool,
               "param_hash": phash, "rows": rows, "dur_s": round(duration, 3),
               "ok": ok}
        if err:
            rec["err"] = err[:200]
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
