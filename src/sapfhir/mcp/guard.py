# -*- coding: utf-8 -*-
"""Schutzschicht fuer die MCP-Tools: nur lesende Abfragen, Zeilen-/Timeout-Limits.

Verhindert DDL/DML in cohort_sql und graph_query. Konservativ: Whitelist der
erlaubten Anfangs-Keywords, Blacklist verbotener Tokens, ein Statement pro Aufruf.
"""
from __future__ import annotations
import re

_FORBIDDEN = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|MERGE|GRANT|REVOKE|"
    r"ATTACH|COPY|INSTALL|LOAD|PRAGMA|CALL|EXPORT|IMPORT|SET)\b", re.IGNORECASE)


class GuardError(ValueError):
    pass


def check_sql(sql: str) -> str:
    s = sql.strip().rstrip(";").strip()
    if ";" in s:
        raise GuardError("Nur ein Statement pro Aufruf erlaubt.")
    head = s.split(None, 1)[0].upper() if s else ""
    if head not in ("SELECT", "WITH"):
        raise GuardError("Nur SELECT/WITH erlaubt.")
    if _FORBIDDEN.search(s):
        raise GuardError("Verbotenes Schluesselwort in der Abfrage.")
    return s


def check_cypher(cypher: str) -> str:
    s = cypher.strip().rstrip(";").strip()
    up = s.upper()
    for bad in ("CREATE", "MERGE", "DELETE", "SET", "DROP", "REMOVE", "COPY",
                "ALTER", "DETACH"):
        if re.search(rf"\b{bad}\b", up):
            raise GuardError(f"Verbotenes Cypher-Keyword: {bad}")
    if not up.startswith("MATCH") and not up.startswith("RETURN"):
        raise GuardError("Cypher muss mit MATCH oder RETURN beginnen.")
    return s


def enforce_limit(sql: str, limit: int) -> str:
    if re.search(r"\bLIMIT\b", sql, re.IGNORECASE):
        return sql
    return f"{sql}\nLIMIT {int(limit)}"
