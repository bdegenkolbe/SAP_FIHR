# -*- coding: utf-8 -*-
"""ISO-8601-Normalisierung fuer fertige FHIR-Ressourcen (Pipeline-Schritt, R13).

PROBLEM (offen seit R7): Die Mapper und die Datums-Helfer (_dt, period) reichen SAP-
Rohformate durch — DATS '20240115', TIMS '081500', kombiniert '20240115T081500'.
FHIR R4 verlangt date '2024-01-15' bzw. dateTime '2024-01-15T08:15:00+01:00'
(dateTime MIT Uhrzeit MUSS einen Zeitzonen-Offset tragen).

ENTWURFSENTSCHEIDUNG (bewusst, R7/R13): Die Normalisierung passiert NICHT in den
Mappern, sondern als eigener Pipeline-Schritt NACH dem Privacy-Date-Shift — der Shift
rechnet auf rohem DATS und darf nicht brechen. Reihenfolge in der Pipeline:

    Bronze-Zeile -> Mapper (rohe Datumswerte) -> priv.shift (roh) -> normalize_resource()

Verhalten:
- Rekursiver Walk ueber die fertige Ressource (dict/list).
- Normalisiert werden NUR Werte in bekannten Datums-Schluesseln (DATE_KEYS) bzw. deren
  period/{start,end}-Kinder — niemals identifier.value, code.code o.ae. (dort koennen
  8-stellige Ziffernfolgen legitime Codes sein).
- Zeitzone: Europe/Berlin, DST-korrekt (+01:00/+02:00) via zoneinfo; Fallback ohne
  zoneinfo: fixer Offset +01:00 (konservativ, logs Warnung).
- Unplausibles bleibt UNANGETASTET (kein Datenverlust): '00000000', '0000-00-00',
  leere Strings, Jahr ausserhalb 1880-2099, kaputte Werte -> Original zurueck.
- Bereits ISO-konforme Werte (inkl. Teilpraezision '1957', '2024-01') bleiben stehen.
- 240000/24:00:00 (SAP-Konvention 'Tagesende') -> 23:59:59 desselben Tages.

Nutzung:
    from .normalize import normalize_resource
    res = normalize_resource(res)          # in-place + Rueckgabe
"""
from __future__ import annotations
import re

try:
    from zoneinfo import ZoneInfo
    _TZ = ZoneInfo("Europe/Berlin")
except Exception:            # pragma: no cover — sehr alte Umgebungen
    _TZ = None

from datetime import datetime

# FHIR-Elementnamen, deren Stringwerte Datums-/Zeitwerte sind (R4-Kern + unsere Mapper).
DATE_KEYS = {
    "birthDate", "deceasedDateTime", "recordedDate", "effectiveDateTime", "issued",
    "date", "authoredOn", "onsetDateTime", "abatementDateTime", "recordedOn",
    "start", "end",              # innerhalb von period/validityPeriod/performedPeriod
    "timestamp", "lastUpdated",
}
# Eltern, deren start/end sicher Zeitraeume sind (start/end NUR dort normalisieren)
PERIOD_PARENTS = {"period", "performedPeriod", "validityPeriod", "servicePeriod"}

_RE_DATS = re.compile(r"^(\d{4})(\d{2})(\d{2})$")                      # 20240115
_RE_DATS_T = re.compile(r"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$")  # 20240115T081500
_RE_ISO_D = re.compile(r"^\d{4}(-\d{2}(-\d{2})?)?$")                   # 1957 / 2024-01 / 2024-01-15
_RE_ISO_DT_NOTZ = re.compile(
    r"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?$")       # ISO ohne Offset
_RE_HAS_TZ = re.compile(r"(Z|[+-]\d{2}:\d{2})$")


def _offset(y, m, d, hh, mm, ss):
    """Europe-Berlin-Offset fuer den Zeitpunkt (DST-korrekt)."""
    if _TZ is None:
        return "+01:00"
    try:
        dt = datetime(y, m, d, hh, mm, ss, tzinfo=_TZ)
        off = dt.utcoffset()
        total = int(off.total_seconds())
        sign = "+" if total >= 0 else "-"
        total = abs(total)
        return f"{sign}{total // 3600:02d}:{(total % 3600) // 60:02d}"
    except Exception:
        return "+01:00"


def _plausibel(y, m, d):
    if not (1880 <= y <= 2099 and 1 <= m <= 12 and 1 <= d <= 31):
        return False
    try:
        datetime(y, m, d)
        return True
    except ValueError:
        return False


def norm_value(v):
    """Einzelwert -> ISO-8601 (oder Original, wenn nicht normalisierbar).

    '20240115'           -> '2024-01-15'
    '20240115T081500'    -> '2024-01-15T08:15:00+01:00' (DST-korrekt +02:00 im Sommer)
    '20240115T240000'    -> '2024-01-15T23:59:59+01:00' (SAP-Tagesende)
    '2024-01-15T08:15:00'-> '+Offset ergaenzt'
    '1957'/'2024-01'     -> unveraendert (FHIR-Teilpraezision, aus Pseudonymisierung)
    '00000000'/''        -> unveraendert (kein Datenverlust)
    """
    if not isinstance(v, str):
        return v
    s = v.strip()
    if not s or s in ("00000000", "0000-00-00", "99991231", "9999-12-31"):
        return v
    # bereits ISO-Datum/Teilpraezision -> stehen lassen
    if _RE_ISO_D.fullmatch(s):
        return s
    # bereits dateTime MIT Offset -> stehen lassen
    if _RE_HAS_TZ.search(s):
        return s
    m = _RE_DATS.fullmatch(s)
    if m:
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        return f"{y:04d}-{mo:02d}-{d:02d}" if _plausibel(y, mo, d) else v
    m = _RE_DATS_T.fullmatch(s)
    if m:
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        hh, mi, ss = int(m.group(4)), int(m.group(5)), int(m.group(6))
        if not _plausibel(y, mo, d):
            return v
        if hh == 24:                       # SAP-Konvention Tagesende
            hh, mi, ss = 23, 59, 59
        if not (0 <= hh <= 23 and 0 <= mi <= 59 and 0 <= ss <= 59):
            return v
        return (f"{y:04d}-{mo:02d}-{d:02d}T{hh:02d}:{mi:02d}:{ss:02d}"
                f"{_offset(y, mo, d, hh, mi, ss)}")
    m = _RE_ISO_DT_NOTZ.fullmatch(s)
    if m:
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        hh, mi = int(m.group(4)), int(m.group(5))
        ss = int(m.group(6) or 0)
        if not _plausibel(y, mo, d) or not (0 <= hh <= 23):
            return v
        return (f"{y:04d}-{mo:02d}-{d:02d}T{hh:02d}:{mi:02d}:{ss:02d}"
                f"{_offset(y, mo, d, hh, mi, ss)}")
    return v


def normalize_resource(obj, _parent_key=None):
    """Rekursive Normalisierung aller Datums-Schluessel einer FHIR-Ressource (in-place)."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str):
                if k in ("start", "end"):
                    if _parent_key in PERIOD_PARENTS:
                        obj[k] = norm_value(v)
                elif k in DATE_KEYS:
                    obj[k] = norm_value(v)
            else:
                normalize_resource(v, _parent_key=k)
    elif isinstance(obj, list):
        for item in obj:
            normalize_resource(item, _parent_key=_parent_key)
    return obj
