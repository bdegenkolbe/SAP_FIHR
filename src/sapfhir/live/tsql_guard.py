# -*- coding: utf-8 -*-
"""T-SQL-Guard fuer den Live-Analyse-MCP (MSSQL-Replika, read-only).

Defense-in-Depth — die harte Grenze bleibt der Login mit db_datareader. Der Guard
setzt zusaetzlich die Verbindliche Methode durch (Analyse_Datenbank.md §4):

1. Nur EIN SELECT/WITH-Statement, keine Kommentare, keine Variablen (@),
   keine DML/DDL/EXEC/INTO/OPENROWSET/xp_/sp_/Lock-Hints.
2. Nur erlaubte Schemas (Standard: sap, sys, INFORMATION_SCHEMA) und nur die
   erlaubte Datenbank bei dreiteiligen Namen; keine Linked-Server (4-teilig).
3. VERKRYPTUNG: verkryptungspflichtige Felder der referenzierten Tabellen duerfen
   NUR gekapselt vorkommen:
       PSEUDO(f)          -> serverseitig HASHBYTES-SHA256 mit geheimem Salt
       LEN(f) / DATALENGTH(f) / LEFT(f,1) / COUNT([DISTINCT] f)
       f IS [NOT] NULL
       YEAR(f)            (nur Datumsfelder, z.B. GBDAT)
   Klartext-Selects, WHERE-Vergleiche (Orakel!) und SELECT * auf solche Tabellen
   werden abgewiesen.
4. Massentabellen (>50 Mio Zeilen, NLEI/N2LABOR001 …) nur mit WHERE.

check() liefert ein Checked-Objekt mit der ausfuehrbaren SQL (PSEUDO bereits
umgeschrieben auf @__salt) plus Metadaten (Tabellen, Aliase, Join-Paare) fuer die
Wissensschicht.
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field

MAX_SQL_CHARS = 20000

_LIT = re.compile(r"N?'(?:[^']|'')*'")
_BRACKET = re.compile(r"\[([^\]]+)\]")
_DQUOTE = re.compile(r'"([^"]+)"')

_FORBIDDEN = re.compile(
    r"\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|DENY|"
    r"EXEC|EXECUTE|INTO|DECLARE|SET|WAITFOR|BULK|OPENROWSET|OPENQUERY|"
    r"OPENDATASOURCE|OPENXML|DBCC|KILL|SHUTDOWN|BACKUP|RESTORE|RECONFIGURE|USE|GO|"
    r"BEGIN|COMMIT|ROLLBACK|SAVE|TRANSACTION|UPDLOCK|XLOCK|TABLOCK|TABLOCKX|"
    r"HOLDLOCK|PAGLOCK|ROWLOCK|SERIALIZABLE|REPEATABLEREAD)\b", re.IGNORECASE)
_FORBIDDEN_PREFIX = re.compile(r"\b(xp_\w+|sp_\w+)\b", re.IGNORECASE)

_SQL_KEYWORDS = {
    "ON", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS",
    "APPLY", "GROUP", "ORDER", "HAVING", "UNION", "EXCEPT", "INTERSECT", "WITH",
    "AS", "SELECT", "FROM", "AND", "OR", "NOT", "TOP", "DISTINCT", "OPTION",
    "PIVOT", "UNPIVOT", "TABLESAMPLE", "FOR", "OFFSET", "FETCH", "WHEN", "THEN",
    "ELSE", "END", "CASE", "IS", "NULL", "IN", "EXISTS", "BETWEEN", "LIKE",
}

_CHAIN = re.compile(r"(?<![\w.@#])([A-Za-z_][\w$#]*(?:\s*\.\s*[A-Za-z_][\w$#]*){1,3})")
_FROMJOIN = re.compile(r"\b(?:FROM|JOIN|APPLY)\s+([A-Za-z_][\w$#]*(?:\s*\.\s*[A-Za-z_][\w$#]*)*)"
                       r"(?:\s+(?:AS\s+)?([A-Za-z_]\w*))?", re.IGNORECASE)
_CTE = re.compile(r"(?:\bWITH|,)\s*([A-Za-z_]\w*)\s*(?:\([^)]*\))?\s+AS\s*\(", re.IGNORECASE)
_EQ = re.compile(r"\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\.([A-Za-z_]\w*)\b")
_STAR = re.compile(
    r"(?:\bSELECT\s+(?:DISTINCT\s+)?(?:TOP\s*\(?\s*\d+\s*\)?\s*(?:PERCENT\s+)?)?|,\s*)"
    r"(?:[A-Za-z_]\w*\.)?\*", re.IGNORECASE)


class GuardError(ValueError):
    pass


@dataclass
class Policy:
    allowed_schemas: tuple = ("sap", "sys", "information_schema")
    allowed_databases: tuple = ("replicate",)
    pii: dict = field(default_factory=dict)        # TABELLE -> {FELD, ...}
    pii_dates: set = field(default_factory=set)    # Felder, fuer die YEAR() erlaubt ist
    mass_tables: set = field(default_factory=set)  # TABELLE (UPPER)

    def pii_for(self, tables) -> set:
        out = set()
        for t in tables:
            out |= {c.upper() for c in self.pii.get(t.upper(), ())}
        return out


@dataclass
class Checked:
    sql: str                        # ausfuehrbar (PSEUDO -> HASHBYTES mit @__salt)
    tables: list                    # ['NPAT', 'NFAL'] (UPPER, ohne Schema)
    aliases: dict                   # alias(UPPER) -> TABELLE
    join_pairs: list                # [(T1, F1, T2, F2)]
    uses_salt: bool
    pii_columns: set                # verkryptungspflichtige Felder der Abfrage


def strip_literals(s: str) -> str:
    return _LIT.sub("''", s)


def _norm_idents(s: str) -> str:
    return _DQUOTE.sub(r"\1", _BRACKET.sub(r"\1", s))


def _split_chain(chain: str) -> list[str]:
    return [p.strip() for p in chain.split(".")]


def _rewrite_pseudo(sql: str) -> tuple[str, bool]:
    """PSEUDO(expr) -> CONVERT(varchar(16), HASHBYTES('SHA2_256', CONCAT(@__salt, expr)), 2).
    Klammern werden balanciert gescannt; String-Literale werden uebersprungen."""
    out, i, used = [], 0, False
    pat = re.compile(r"\bPSEUDO\s*\(", re.IGNORECASE)
    while True:
        m = pat.search(sql, i)
        if not m:
            out.append(sql[i:])
            break
        # liegt der Treffer in einem Literal? -> unveraendert uebernehmen
        if any(a <= m.start() < b for a, b in ((x.start(), x.end()) for x in _LIT.finditer(sql))):
            out.append(sql[i:m.end()])
            i = m.end()
            continue
        depth, j, in_lit = 1, m.end(), False
        while j < len(sql) and depth:
            ch = sql[j]
            if ch == "'":
                in_lit = not in_lit
            elif not in_lit:
                depth += ch == "("
                depth -= ch == ")"
            j += 1
        if depth:
            raise GuardError("PSEUDO( ohne schliessende Klammer.")
        inner = sql[m.end():j - 1]
        out.append(sql[i:m.start()])
        out.append(f"CONVERT(varchar(16), HASHBYTES('SHA2_256', "
                   f"CONCAT(@__salt, {inner})), 2)")
        used = True
        i = j
    return "".join(out), used


def _pii_occurrence_ok(bare: str, start: int, end: int, col: str, policy: Policy) -> bool:
    before = bare[:start]
    after = bare[end:]
    # optionaler Alias-Praefix "p." gehoert zum Treffer
    before = re.sub(r"[A-Za-z_]\w*\s*\.\s*$", "", before)
    if re.search(r"\b(PSEUDO|LEN|DATALENGTH)\s*\(\s*$", before, re.IGNORECASE):
        return True
    if re.search(r"\bCOUNT\s*\(\s*(DISTINCT\s+)?$", before, re.IGNORECASE):
        return True
    if re.search(r"\bLEFT\s*\(\s*$", before, re.IGNORECASE) and \
            re.match(r"\s*,\s*1\s*\)", after):
        return True
    if col in policy.pii_dates and re.search(r"\bYEAR\s*\(\s*$", before, re.IGNORECASE):
        return True
    if re.match(r"\s+IS\s+(NOT\s+)?NULL\b", after, re.IGNORECASE):
        return True
    return False


def check(sql: str, policy: Policy) -> Checked:
    if not sql or not sql.strip():
        raise GuardError("Leere Abfrage.")
    if len(sql) > MAX_SQL_CHARS:
        raise GuardError(f"Abfrage zu lang (>{MAX_SQL_CHARS} Zeichen).")
    s = sql.strip().rstrip(";").strip()
    bare = _norm_idents(strip_literals(s))

    if "--" in bare or "/*" in bare:
        raise GuardError("Kommentare sind nicht erlaubt.")
    if ";" in bare:
        raise GuardError("Nur ein Statement pro Aufruf erlaubt.")
    if "@" in bare:
        raise GuardError("Variablen/@@-Funktionen sind nicht erlaubt.")
    head = bare.split(None, 1)[0].upper()
    if head not in ("SELECT", "WITH"):
        raise GuardError("Nur SELECT/WITH erlaubt.")
    m = _FORBIDDEN.search(bare)
    if m:
        raise GuardError(f"Verbotenes Schluesselwort: {m.group(1).upper()}")
    m = _FORBIDDEN_PREFIX.search(bare)
    if m:
        raise GuardError(f"System-Prozeduren sind nicht erlaubt: {m.group(1)}")

    # -- Objekt-Referenzen -------------------------------------------------
    ctes = {c.upper() for c in _CTE.findall(bare)}
    schemas = {x.lower() for x in policy.allowed_schemas}
    known_schemas = schemas | {"dbo", "hrp", "sap", "sys", "information_schema"}
    dbs = {x.lower() for x in policy.allowed_databases}
    tables: list[str] = []
    for ch in _CHAIN.findall(bare):
        parts = _split_chain(ch)
        if len(parts) == 4:
            raise GuardError("Linked-Server-Zugriffe (4-teilige Namen) sind nicht erlaubt.")
        if len(parts) == 3:
            if parts[0].lower() in known_schemas:
                continue  # schema.table.column — Spaltenreferenz
            if parts[0].lower() not in dbs:
                raise GuardError(f"Datenbank '{parts[0]}' ist nicht freigegeben "
                                 f"(erlaubt: {', '.join(sorted(dbs))}).")
            sch, tab = parts[1], parts[2]
        else:
            sch, tab = parts[0], parts[1]
            if sch.lower() not in known_schemas:
                continue  # alias.spalte
        if sch.lower() not in schemas:
            raise GuardError(f"Schema '{sch}' ist nicht freigegeben "
                             f"(erlaubt: {', '.join(sorted(schemas))}).")
        if sch.lower() == "sap" and tab.upper() not in tables:
            tables.append(tab.upper())

    aliases: dict[str, str] = {}
    for target, alias in _FROMJOIN.findall(bare):
        parts = _split_chain(target)
        if len(parts) == 1:
            if parts[0].upper() not in ctes:
                raise GuardError(f"Tabelle '{parts[0]}' bitte schema-qualifiziert "
                                 f"angeben (z.B. sap.{parts[0].upper()}).")
            continue
        tab = parts[-1].upper()
        if alias and alias.upper() not in _SQL_KEYWORDS:
            aliases[alias.upper()] = tab
        aliases.setdefault(tab, tab)

    # -- Massentabellen ------------------------------------------------------
    mass = [t for t in tables if t in {x.upper() for x in policy.mass_tables}]
    if mass and not re.search(r"\bWHERE\b", bare, re.IGNORECASE):
        raise GuardError(f"Massentabelle {', '.join(mass)} nur mit WHERE-Filter "
                         f"(Schluesselfilter) — Voll-Scans timeouten (Analyse_Datenbank §4). "
                         f"Zeilenzahl: Werkzeug tabelle_beschreiben.")

    # -- Verkryptung ----------------------------------------------------------
    pii = policy.pii_for(tables)
    if pii:
        if _STAR.search(bare):
            raise GuardError("SELECT * auf Tabellen mit verkryptungspflichtigen Feldern "
                             "ist nicht erlaubt — Spalten explizit waehlen oder "
                             "Werkzeug stichprobe nutzen (maskiert automatisch).")
        for col in sorted(pii):
            for mm in re.finditer(rf"(?<![\w$#]){re.escape(col)}(?![\w$#])", bare,
                                  re.IGNORECASE):
                if not _pii_occurrence_ok(bare, mm.start(), mm.end(), col, policy):
                    raise GuardError(
                        f"Feld {col} ist verkryptungspflichtig — nur als PSEUDO({col}), "
                        f"LEN({col}), LEFT({col},1), COUNT({col}) oder IS [NOT] NULL"
                        + (f", YEAR({col})" if col in policy.pii_dates else "")
                        + " zulaessig (Analyse_Datenbank.md §4).")

    # -- Join-Paare fuer die Wissensschicht ------------------------------------
    pairs = []
    for a1, f1, a2, f2 in _EQ.findall(bare):
        t1, t2 = aliases.get(a1.upper()), aliases.get(a2.upper())
        if t1 and t2 and t1 != t2:
            pairs.append((t1, f1.upper(), t2, f2.upper()))

    exe, used = _rewrite_pseudo(s)
    return Checked(sql=exe, tables=tables, aliases=aliases, join_pairs=pairs,
                   uses_salt=used, pii_columns=pii)


def mask_row(row: dict, pii_columns: set) -> dict:
    """Zweite Linie: Ergebnisspalten, die exakt wie ein PII-Feld heissen und
    Text enthalten, der nicht nach PSEUDO-Hash aussieht, werden geschwaerzt."""
    if not pii_columns:
        return row
    out = {}
    for k, v in row.items():
        if (k or "").upper() in pii_columns and isinstance(v, str) \
                and not re.fullmatch(r"[0-9A-F]{16}", v):
            out[k] = "<maskiert>"
        else:
            out[k] = v
    return out


def literal_free(sql: str) -> str:
    """SQL ohne Literalinhalte (fuer Logs/Wissensspeicher)."""
    return re.sub(r"\s+", " ", _LIT.sub("'?'", sql)).strip()
