# -*- coding: utf-8 -*-
"""Materialisierung der Auth-Marts aus den Quelltabellen (live verifiziert R19c).

Diese SQL erzeugen im Warehouse ein `auth`-Schema aus der maskierten/bronze-Schicht.
Sie sind bewusst quelltreu gehalten (Spaltennamen wie in IS-H/HR). Personenidentifizierende
HR-Felder (USRID/Name) bleiben in `auth.*` und fliessen NIE in Analytik/Export.
Alle Joins zeitscheibenbasiert (BEGDA/ENDDA bzw. BEGDT/ENDDT).
"""
from __future__ import annotations

# Quelle je Deployment konfigurierbar (bronze_current-Views bzw. mcp.*). Platzhalter {src}.
DDL = {
    # AD-Login -> PERNR  (PA0105, Subtyp 90AD = Windows/AD-Benutzer)
    "auth.login_pernr": """
        CREATE OR REPLACE TABLE auth.login_pernr AS
        SELECT UPPER(TRIM(USRID)) AS login, PERNR,
               TRY_CAST(BEGDA AS DATE) AS begda, TRY_CAST(ENDDA AS DATE) AS endda
        FROM {src}.PA0105
        WHERE SUBTY = '90AD' AND COALESCE(TRIM(USRID),'') <> ''
    """,
    # PERNR -> Kostenstelle  (PA0001 Organisatorische Zuordnung)
    "auth.pernr_kostl": """
        CREATE OR REPLACE TABLE auth.pernr_kostl AS
        SELECT PERNR, TRIM(KOSTL) AS kostl, TRIM(ORGEH) AS orgeh,
               TRY_CAST(BEGDA AS DATE) AS begda, TRY_CAST(ENDDA AS DATE) AS endda
        FROM {src}.PA0001 WHERE COALESCE(TRIM(KOSTL),'') <> ''
    """,
    # SETNODE-Kanten (Kostenstellen-Gruppen-Hierarchie). Knoten-ID = Klasse|Subkl|Setname.
    "auth.setnode": """
        CREATE OR REPLACE TABLE auth.setnode AS
        SELECT SETCLASS||'|'||SUBCLASS||'|'||SETNAME AS parent_set,
               SUBSETCLS||'|'||SUBSETSCLS||'|'||SUBSETNAME AS child_set
        FROM {src}.SETNODE
        WHERE SETCLASS IN ('0101','0102','0103') AND COALESCE(SUBSETNAME,'') <> ''
    """,
    # SETLEAF-Blaetter: Kostenstellen je Set (nur Einzelwerte EQ; Bereiche BT s. Hinweis).
    "auth.setleaf": """
        CREATE OR REPLACE TABLE auth.setleaf AS
        SELECT SETCLASS||'|'||SUBCLASS||'|'||SETNAME AS set_id, TRIM(VALFROM) AS kostl
        FROM {src}.SETLEAF
        WHERE SETCLASS IN ('0101','0102','0103') AND VALSIGN='I' AND VALOPTION='EQ'
          AND COALESCE(TRIM(VALFROM),'') <> ''
    """,
    # IS-H-OE -> Kostenstelle (NOEK), zeitscheibenbasiert.
    "auth.oe_kostl": """
        CREATE OR REPLACE TABLE auth.oe_kostl AS
        SELECT TRIM(ORGFA) AS orgfa, TRIM(ORGPF) AS orgpf, TRIM(KOSTL) AS kostl,
               TRY_CAST(BEGDT AS DATE) AS begdt, TRY_CAST(ENDDT AS DATE) AS enddt
        FROM {src}.NOEK WHERE COALESCE(TRIM(KOSTL),'') <> ''
    """,
}

# Patient-seitige Kostenstellen je Fall (aus den Bewegungen ueber NOEK).
PATIENT_KOSTL_VIEW = """
    CREATE OR REPLACE VIEW auth.fall_kostl AS
    SELECT DISTINCT f.PATNR, b.FALNR, k.kostl
    FROM mcp.bewegung b
    JOIN mcp.fall f USING (FALNR)
    JOIN auth.oe_kostl k
      ON (b.ORGFA = k.orgfa AND (k.orgpf = '' OR b.ORGPF = k.orgpf))
    WHERE COALESCE(TRIM(b.ORGFA),'') <> ''
"""


def build(con, src: str = "bronze_current") -> None:
    """Erzeugt das auth-Schema im Warehouse. `src` = Quellschema/-Praefix der Rohtabellen."""
    con.execute("CREATE SCHEMA IF NOT EXISTS auth")
    for name, ddl in DDL.items():
        con.execute(ddl.format(src=src))
    con.execute(PATIENT_KOSTL_VIEW)
