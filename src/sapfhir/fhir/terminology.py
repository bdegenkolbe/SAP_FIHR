# -*- coding: utf-8 -*-
"""Terminologie-Schicht (CONCEPT §18): CodeSystem-URIs, LOINC-/UCUM-Mapping,
ICD-Hilfsfunktionen. Kataloge liegen lokal (kein Terminologieserver, kein Egress).
"""
from __future__ import annotations
import csv
import os
import re

# Offizielle CodeSystem-URIs (DE-Basisprofile / ISiK)
ICD10GM = "http://fhir.de/CodeSystem/bfarm/icd-10-gm"
OPS = "http://fhir.de/CodeSystem/bfarm/ops"
LOINC = "http://loinc.org"
UCUM = "http://unitsofmeasure.org"
V3_ACTCODE = "http://terminology.hl7.org/CodeSystem/v3-ActCode"
OBS_CATEGORY = "http://terminology.hl7.org/CodeSystem/observation-category"
COND_VERSTATUS = "http://terminology.hl7.org/CodeSystem/condition-ver-status"


def icd_group(icd: str | None) -> str | None:
    """ICD-10-Dreisteller (z.B. 'I50.14' -> 'I50') — fuer Wiederaufnahme-Kante
    und Diagnose-Rollups."""
    if not icd:
        return None
    m = re.match(r"([A-Z]\d{2})", str(icd).upper())
    return m.group(1) if m else None


# UCUM-Normalisierung gaengiger Klinik-Schreibweisen; unkartierte Einheiten
# bleiben als unit-Text OHNE code (nie raten).
_UCUM = {
    "mg/dl": "mg/dL", "mg/dL": "mg/dL", "g/dl": "g/dL", "g/l": "g/L",
    "mmol/l": "mmol/L", "µmol/l": "umol/L", "umol/l": "umol/L",
    "u/l": "U/L", "iu/l": "[IU]/L", "%": "%", "mmhg": "mm[Hg]",
    "/nl": "/nL", "g/mol": "g/mol", "ng/ml": "ng/mL", "pg/ml": "pg/mL",
    "mval/l": "meq/L", "sek": "s", "min": "min",
}


def ucum(unit: str | None) -> str | None:
    if not unit:
        return None
    return _UCUM.get(str(unit).strip().lower()) or _UCUM.get(str(unit).strip())


class LoincMap:
    """Hauseigener Laborparameter-Code -> LOINC (config/loinc_map.csv,
    Spalten: local_code, loinc). Abdeckungsquote fuer das DQ-Dashboard."""

    def __init__(self, path: str | None = None):
        self.map: dict[str, str] = {}
        self.hits = 0
        self.misses = 0
        if path and os.path.exists(path):
            with open(path, newline="", encoding="utf-8") as f:
                for r in csv.DictReader(f):
                    lc, lo = r.get("local_code"), r.get("loinc")
                    if lc and lo:
                        self.map[lc.strip()] = lo.strip()

    def lookup(self, local_code: str | None) -> str | None:
        if not local_code:
            return None
        code = self.map.get(str(local_code).strip())
        if code:
            self.hits += 1
        else:
            self.misses += 1
        return code

    @property
    def coverage(self) -> float:
        total = self.hits + self.misses
        return self.hits / total if total else 0.0
