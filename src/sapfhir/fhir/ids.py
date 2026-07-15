# -*- coding: utf-8 -*-
"""Stabile, idempotente FHIR-Ressourcen-IDs via uuid5.

Gleicher Quellschluessel -> gleiche FHIR-ID, damit Re-Exporte upserten statt duplizieren
(Muster aus Ingolf). Namensraum wird aus config (fhir.id_namespace) gesalzt.
"""
from __future__ import annotations
import uuid

_BASE = uuid.UUID("6f1b4d2a-0000-5000-a000-534150464948")  # feste App-Namespace-Basis


def make_ns(salt: str = "sapfhir") -> uuid.UUID:
    return uuid.uuid5(_BASE, salt)


def rid(ns: uuid.UUID, resource_type: str, *key_parts) -> str:
    """Deterministische ID aus Ressourcentyp + Quellschluesselteilen."""
    key = resource_type + "|" + "|".join(str(p) for p in key_parts if p is not None)
    return str(uuid.uuid5(ns, key))
