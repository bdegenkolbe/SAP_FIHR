# -*- coding: utf-8 -*-
"""Lastfenster-Durchsetzung fuer Backfill-Laeufe (CONCEPT §5).

Das Fenster (extract.window in connection.yaml) wird nicht nur konfiguriert, sondern
erzwungen: ausserhalb pausiert der Lauf und setzt am Keyset-Cursor wieder auf.
Fenster ueber Mitternacht (z.B. 22:00-05:00) werden unterstuetzt.
"""
from __future__ import annotations
import datetime as _dt
import time as _time


def _parse(hhmm: str) -> _dt.time:
    h, m = hhmm.strip().split(":")
    return _dt.time(int(h), int(m))


def in_window(now: _dt.time, start: str, end: str) -> bool:
    s, e = _parse(start), _parse(end)
    if s <= e:
        return s <= now < e
    return now >= s or now < e   # Fenster ueber Mitternacht


def seconds_until_window(now: _dt.datetime, start: str) -> float:
    s = _parse(start)
    target = now.replace(hour=s.hour, minute=s.minute, second=0, microsecond=0)
    if target <= now:
        target += _dt.timedelta(days=1)
    return (target - now).total_seconds()


class Window:
    """wait() blockiert bis zum naechsten Fensterbeginn, wenn ein Fenster
    konfiguriert ist und der aktuelle Zeitpunkt ausserhalb liegt."""

    def __init__(self, cfg: dict | None, enforce: bool = True,
                 sleep_fn=_time.sleep, now_fn=_dt.datetime.now):
        cfg = cfg or {}
        self.start = cfg.get("start")
        self.end = cfg.get("end")
        self.enforce = enforce and bool(self.start and self.end)
        self._sleep = sleep_fn
        self._now = now_fn

    def wait(self) -> float:
        """Liefert die gewartete Zeit in Sekunden (0, wenn im Fenster)."""
        if not self.enforce:
            return 0.0
        now = self._now()
        if in_window(now.time(), self.start, self.end):
            return 0.0
        secs = seconds_until_window(now, self.start)
        print(f"  [window] ausserhalb {self.start}-{self.end} — pausiere "
              f"{int(secs/60)} min bis Fensterbeginn (Cursor bleibt erhalten)")
        self._sleep(secs)
        return secs
