# -*- coding: utf-8 -*-
"""Maskierte, materialisierte mcp.*-Schicht — einzige Datenoberflaeche des
MCP-Servers (CONCEPT §17.2, schliesst ANALYSE A3).

Warum materialisiert (Tabellen statt Views)? Die MCP-Verbindung laeuft mit
enable_external_access=false (Sandbox, §17.1) und darf kein read_parquet
ausfuehren. Der Gold-Build kopiert deshalb die benoetigten Spalten aus
bronze_current in die Warehouse-Datei — inklusive zentral durchgesetzter
Maskierung (Klarnamen/Adressen/exaktes Geburtsdatum), wenn pseudonymize aktiv.

Tabellen: mcp.patient, mcp.fall, mcp.bewegung, mcp.diagnose, mcp.prozedur,
          mcp.labor, mcp.dokument (je nach entladenen Quelltabellen).
"""
from __future__ import annotations
import duckdb

# Quelle -> (mcp-Name, Spalten [maskierbare mit '~' Praefix])
# '~'-Spalten werden bei pseudonymize=True durch '***' bzw. Jahr ersetzt.
_SPEC = {
    "npat": ("patient",
             ["MANDT", "PATNR", "GSCHL", "~GBDAT", "~NNAME", "~VNAME",
              "TODKZ", "STORN"]),
    "nfal": ("fall",
             ["MANDT", "EINRI", "FALNR", "PATNR", "FALAR", "BEGDT", "ENDDT",
              "FACHR", "STATU", "ABRKZ", "STORN"]),
    "nbew": ("bewegung",
             ["MANDT", "EINRI", "FALNR", "LFDNR", "BEWTY", "BWART", "BWGR1",
              "BWIDT", "BWEDT", "ORGFA", "ORGPF", "STORN"]),
    "ndia": ("diagnose",
             # DKAT1/DKAT2 = Diagnosekatalog je Kode (ICD-10-GM-Version, '90'=ICD-O
             # Topographie u.a.) — ohne ihn ist eine Textauflösung nicht eindeutig (R30)
             ["MANDT", "EINRI", "FALNR", "LFDNR", "DKAT1", "DKAT2", "DKEY1", "DKEY2", "DITXT",
              "DIAGW", "DIADT", "KHDIA", "FHDIA", "AFDIA", "ENDIA", "BHDIA",
              "OPDIA", "STORN"]),
    "nicp": ("prozedur",
             ["MANDT", "EINRI", "FALNR", "LNRIC", "ICPML", "ICPMK",
              "BTEXT", "BGDOP", "ENDOP", "ORGFA", "STORN"]),
    "ndoc": ("dokument",
             ["MANDT", "EINRI", "DOKAR", "DOKNR", "DOKVR", "DOKTL", "LFDDOK",
              "PATNR", "FALNR", "DTID", "MEDOK", "DODAT", "STORN"]),
    # DRG-Ergebnis je Fall (NDRG: ENGLISCHE Spalten, PATCASEID==FALNR, R9/R27)
    "ndrg": ("drg",
             ["CLIENT", "INSTITUTION", "PATCASEID", "DRG_SEQNO", "DRG_CODE",
              "MDC_CODE", "COST_WEIGHT", "CANCEL_FLAG", "DRG_CREAT_DATE"]),
    # DRG-Textkatalog (UKL-Referenzdaten, kein Personenbezug)
    "leistungen_drgs": ("drg_katalog",
             ["DRG", "DRG_Bezeichnung", "DRG_BWR",
              "DRG_gueltig_von", "DRG_gueltig_bis"]),
}


def _select_list(avail: set[str], cols: list[str], pseudonymize: bool) -> list[str]:
    out = []
    for c in cols:
        masked = c.startswith("~")
        name = c.lstrip("~")
        # avail ist UPPER-normalisiert; Spec-Namen koennen gemischtgeschrieben
        # sein (Nicht-SAP-Referenztabellen wie Leistungen_DRGs.DRG_Bezeichnung,
        # R27) — sonst fallen genau diese Spalten stumm aus der mcp-Schicht.
        if name.upper() not in avail:
            continue
        if masked and pseudonymize:
            if name == "GBDAT":   # nur Geburtsjahr
                out.append(f"substr(CAST(\"{name}\" AS VARCHAR), 1, 4) AS \"{name}\"")
            else:
                out.append(f"'***' AS \"{name}\"")
        else:
            out.append(f'"{name}"')
    return out


def build(con: duckdb.DuckDBPyConnection, pseudonymize: bool = True) -> list[str]:
    con.execute("CREATE SCHEMA IF NOT EXISTS mcp")
    made = []
    for src, (name, cols) in _SPEC.items():
        if not con.execute(
                "SELECT 1 FROM information_schema.tables "
                "WHERE table_schema='bronze_current' AND table_name=?",
                [src]).fetchone():
            continue
        avail = {r[0].upper() for r in
                 con.execute(f'DESCRIBE bronze_current."{src}"').fetchall()}
        sel = _select_list(avail, cols, pseudonymize)
        if not sel:
            continue
        # Statistiksperre (NFAL.STASP, Altbestand): gesperrte Faelle erreichen
        # weder Analytik noch MCP.
        where = ("WHERE COALESCE(STASP, '') <> 'X'"
                 if src == "nfal" and "STASP" in avail else "")
        con.execute(f'CREATE OR REPLACE TABLE mcp."{name}" AS '
                    f'SELECT {", ".join(sel)} FROM bronze_current."{src}" {where}')
        made.append(name)
    # Labor: Kopf (N2LABOR) + Werte (N2LABOR001) ueber DVS-Schluessel joinen (R8)
    have = lambda t: bool(con.execute(
        "SELECT 1 FROM information_schema.tables WHERE table_schema='bronze_current' "
        "AND table_name=?", [t]).fetchone())
    if have("n2labor") and have("n2labor001"):
        con.execute("""
            CREATE OR REPLACE TABLE mcp.labor AS
            SELECT h."N2LAPATNR" AS PATNR, h."N2LAFALNR" AS FALNR,
                   h."N2LAEINRI" AS EINRI,
                   t."N2LEISTID" AS LEISTID, t."N2KATTEXT" AS KATTEXT,
                   t."N2VALUE" AS WERT, t."N2UNIT" AS EINH,
                   t."N2NORMAL" AS REFBER, t."N2ABNORMAL" AS ABNORMAL,
                   COALESCE(t."N2DATE", h."N2LADATUM") AS BEFDT
            FROM bronze_current.n2labor001 t
            LEFT JOIN bronze_current.n2labor h
              USING ("DOKAR","DOKNR","DOKVR","DOKTL")""")
        made.append("labor")

    # Merkzettel fuer den Server: mit welcher Maskierung wurde gebaut?
    con.execute("CREATE OR REPLACE TABLE mcp._built AS SELECT ? AS pseudonymize, "
                "now() AS ts", [pseudonymize])
    return made
