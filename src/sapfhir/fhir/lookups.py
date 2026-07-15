# -*- coding: utf-8 -*-
"""Katalog-Lookup-Schicht (CONCEPT §20.14, ALTBESTAND_ANALYSE §3).

Loest Rohcodes ueber die hausindividuellen IS-H-Kataloge in Klartext auf.
Die Kataloge (TN14T, TN14U, TN24T, NKDI, NORG, NKTR) kommen als normale
Bronze-Tabellen (cdc: full) und werden hier aus bronze_current in kleine
In-Memory-Dicts geladen. Fehlt ein Katalog (noch nicht entladen), greift der
Aufrufer auf seine Fallback-Enums zurueck — die Pipeline laeuft immer.

Spaltennamen der Kataloge sind teilweise noch # VERIFY (gegen Live-DB pruefen);
die Definitionen sind deshalb konfigurierbar gehalten: pro Katalog werden
mehrere Kandidaten-Textspalten probiert.
"""
from __future__ import annotations

import duckdb

# Katalog -> (bronze_current-Tabelle, Schluesselspalten, Kandidaten-Textspalten)
_CATALOGS = {
    "bewegungstyp": ("tn14t", ["BEWTY"],
                     ["BEWTX", "BEWTXT", "KTEXT", "BTEXT", "TEXT"]),   # VERIFY Spalte
    "bewegungsart": ("tn14u", ["BEWTY", "BWART"],
                     ["BWATX", "KTEXT", "BTEXT", "TEXT"]),             # VERIFY
    "behandlungskategorie": ("tn24t", ["BEKAT"],
                             ["BLTXT", "KTEXT", "TEXT"]),              # BLTXT lt. Altbestand
    "icd": ("nkdi", ["DKAT", "DKEY"],
            ["DTEXT", "DTEXT1", "KTEXT"]),                             # NKDI: DTEXT1-4
    "oe": ("norg", ["ORGID"],
           ["ORGNA", "ORGKT", "KTEXT"]),                               # VERIFY
    "kostentraeger": ("nktr", ["KOSTR"],
                      ["KSSNM", "KTEXT"]),                             # KSSNM verifiziert
}


class Lookups:
    """Laedt vorhandene Kataloge einmalig; text() liefert None bei Unbekanntem."""

    def __init__(self, con: duckdb.DuckDBPyConnection | None = None):
        self._maps: dict[str, dict[tuple, str]] = {}
        self.loaded: list[str] = []
        if con is not None:
            self._load(con)

    def _load(self, con) -> None:
        for name, (table, keys, text_candidates) in _CATALOGS.items():
            if not con.execute(
                    "SELECT 1 FROM information_schema.tables WHERE "
                    "table_schema='bronze_current' AND table_name=?",
                    [table]).fetchone():
                continue
            avail = {r[0].upper() for r in
                     con.execute(f'DESCRIBE bronze_current."{table}"').fetchall()}
            if not all(k in avail for k in keys):
                continue
            text_col = next((t for t in text_candidates if t in avail), None)
            if text_col is None:
                # NKDI-Sonderfall: DTEXT1..4 konkatenieren
                if name == "icd" and "DTEXT1" in avail:
                    parts = [c for c in ("DTEXT1", "DTEXT2", "DTEXT3", "DTEXT4")
                             if c in avail]
                    text_expr = "concat(" + ", ".join(
                        f'COALESCE("{c}", \'\')' for c in parts) + ")"
                else:
                    continue
            else:
                text_expr = f'"{text_col}"'
            key_sql = ", ".join(f'CAST("{k}" AS VARCHAR)' for k in keys)
            rows = con.execute(
                f"SELECT {key_sql}, {text_expr} FROM bronze_current.\"{table}\" "
                f"WHERE {text_expr} IS NOT NULL").fetchall()
            self._maps[name] = {tuple(str(v).strip() for v in r[:-1]):
                                str(r[-1]).strip() for r in rows if r[-1]}
            self.loaded.append(name)

    def text(self, catalog: str, *key) -> str | None:
        m = self._maps.get(catalog)
        if not m:
            return None
        return m.get(tuple(str(k).strip() for k in key))

    # Bequeme Kurzformen fuer die Mapper
    def bewegungstyp(self, bewty) -> str | None:
        return self.text("bewegungstyp", bewty)

    def icd_text(self, dkat, dkey) -> str | None:
        return self.text("icd", dkat, dkey)

    def oe_name(self, orgid) -> str | None:
        return self.text("oe", orgid)


def from_warehouse(warehouse: str = "data/warehouse.duckdb") -> Lookups:
    try:
        con = duckdb.connect(warehouse, read_only=True)
    except duckdb.Error:
        return Lookups(None)
    try:
        return Lookups(con)
    finally:
        con.close()
