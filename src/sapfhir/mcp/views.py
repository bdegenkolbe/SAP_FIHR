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
             ["MANDT", "EINRI", "FALNR", "PATNR", "FALAR", "BEGDT", "ENDAT",
              "FACHR", "STATU", "ABRKZ", "STORN"]),
    "nbew": ("bewegung",
             ["MANDT", "EINRI", "FALNR", "LFDNR", "BEWTY", "BWART", "BWGR1",
              "BWIDT", "BWEDT", "ORGFA", "ORGPF", "STORN"]),
    "ndia": ("diagnose",
             ["MANDT", "EINRI", "FALNR", "LFDNR", "DKEY1", "DKEY2", "DITXT",
              "DIAGW", "DIADT", "KHDIA", "FHDIA", "AFDIA", "ENDIA", "BHDIA",
              "OPDIA", "STORN"]),
    "nicp": ("prozedur",
             ["MANDT", "EINRI", "FALNR", "LNRIC", "LFDNR", "ICPML", "ICPK1",
              "BTEXT", "BGDOP", "ENDOP", "ORGFA", "ICDAT", "STORN"]),
    "n2labor": ("labor",
                ["MANDT", "EINRI", "FALNR", "LFDNR", "PARCD", "PARTX", "WERT",
                 "EINH", "REFBER", "BEFDT", "STORN"]),
    "ndoc": ("dokument",
             ["MANDT", "EINRI", "DOCID", "FALNR", "PATNR", "DOCTY", "DOCKA",
              "DOCDT", "STORN"]),
}


def _select_list(avail: set[str], cols: list[str], pseudonymize: bool) -> list[str]:
    out = []
    for c in cols:
        masked = c.startswith("~")
        name = c.lstrip("~")
        if name not in avail:
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
    # Merkzettel fuer den Server: mit welcher Maskierung wurde gebaut?
    con.execute("CREATE OR REPLACE TABLE mcp._built AS SELECT ? AS pseudonymize, "
                "now() AS ts", [pseudonymize])
    return made
