# -*- coding: utf-8 -*-
"""Schutzschicht fuer die MCP-Tools (CONCEPT §17): nur lesende Abfragen,
nur die mcp.*-Schicht, keine Dateisystem-Funktionen, Zeilen-Limits.

Defense-in-Depth: Die eigentliche Sandbox ist die DuckDB-Verbindung mit
enable_external_access=false (server.py). Der Guard blockt zusaetzlich auf
Text-Ebene, damit Fehlversuche frueh und mit klarer Meldung scheitern.
"""
from __future__ import annotations
import re

_FORBIDDEN = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|MERGE|GRANT|REVOKE|"
    r"ATTACH|DETACH|COPY|INSTALL|LOAD|PRAGMA|CALL|EXPORT|IMPORT|SET|RESET|"
    r"CHECKPOINT|VACUUM)\b", re.IGNORECASE)

# DuckDB-Tabellen-/Dateifunktionen: erlauben beliebige Dateilesezugriffe
# (ANALYSE S1) — in der Sandbox ohnehin tot, hier klar abgewiesen.
_FORBIDDEN_FUNCS = re.compile(
    r"\b(read_parquet|read_csv|read_csv_auto|read_json|read_json_auto|read_text|"
    r"read_blob|parquet_scan|glob|sniff_csv|getenv|delta_scan|iceberg_scan)\s*\(",
    re.IGNORECASE)

# Schema-qualifizierte Referenzen: nur mcp.* ist fuer cohort_sql erlaubt.
_SCHEMA_REF = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*[A-Za-z_\"]")


class GuardError(ValueError):
    pass


def _strip_literals(s: str) -> str:
    """Entfernt String-Literale, damit Schema-/Funktionspruefung keine
    Falschtreffer auf Suchtexte ('...') produziert."""
    return re.sub(r"'(?:[^']|'')*'", "''", s)


def check_sql(sql: str, allowed_schemas: tuple[str, ...] = ("mcp",)) -> str:
    s = sql.strip().rstrip(";").strip()
    if ";" in s:
        raise GuardError("Nur ein Statement pro Aufruf erlaubt.")
    head = s.split(None, 1)[0].upper() if s else ""
    if head not in ("SELECT", "WITH"):
        raise GuardError("Nur SELECT/WITH erlaubt.")
    bare = _strip_literals(s)
    if _FORBIDDEN.search(bare):
        raise GuardError("Verbotenes Schluesselwort in der Abfrage.")
    if _FORBIDDEN_FUNCS.search(bare):
        raise GuardError("Datei-/Systemfunktionen sind im MCP nicht erlaubt — "
                         "bitte nur mcp.*-Tabellen abfragen.")
    if allowed_schemas:
        for m in _SCHEMA_REF.finditer(bare):
            schema = m.group(1).lower()
            if schema not in allowed_schemas:
                raise GuardError(
                    f"Schema '{schema}' ist im MCP nicht zugreifbar — "
                    f"erlaubt: {', '.join(allowed_schemas)}.*")
    return s


def check_cypher(cypher: str) -> str:
    s = cypher.strip().rstrip(";").strip()
    up = _strip_literals(s).upper()
    for bad in ("CREATE", "MERGE", "DELETE", "SET", "DROP", "REMOVE", "COPY",
                "ALTER", "DETACH", "LOAD", "IMPORT", "EXPORT", "ATTACH", "CALL"):
        if re.search(rf"\b{bad}\b", up):
            raise GuardError(f"Verbotenes Cypher-Keyword: {bad}")
    if not up.startswith("MATCH") and not up.startswith("RETURN"):
        raise GuardError("Cypher muss mit MATCH oder RETURN beginnen.")
    return s


def enforce_limit(sql: str, limit: int) -> str:
    if re.search(r"\bLIMIT\b", sql, re.IGNORECASE):
        return sql
    return f"{sql}\nLIMIT {int(limit)}"
