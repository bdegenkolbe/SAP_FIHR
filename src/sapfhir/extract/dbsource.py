# -*- coding: utf-8 -*-
"""Quell-DB-Anbindung (MSSQL IS-H Replika, read-only).

Muster uebernommen aus Schwesterprojekt Ingolf (agent/dbsource.py), angepasst an
IS-H/i.s.h.med + Qlik-Replikat:
  - pyodbc bevorzugt, Fallback pytds (pure Python, kein ODBC-Treiber -> No-Admin)
  - Zeilen als dict, Datumswerte ISO-8601
  - Rechte-Check (db_datareader genuegt)
  - CDC-Helfer ueber Qlik-__ct-Change-Sequenz statt SQL-rowversion

CLI:  python -m sapfhir.extract.dbsource --check --config config/connection.yaml
"""
from __future__ import annotations
import argparse
import datetime as _dt
import os
from typing import Any, Iterable, Iterator

try:
    import pyodbc  # type: ignore
    _HAVE_PYODBC = True
except Exception:
    _HAVE_PYODBC = False
try:
    import pytds  # type: ignore
    _HAVE_PYTDS = True
except Exception:
    _HAVE_PYTDS = False


def to_iso(v: Any) -> Any:
    """datetime/date/time -> ISO-8601 String; Decimal -> float; sonst unveraendert."""
    if isinstance(v, (_dt.datetime, _dt.date, _dt.time)):
        return v.isoformat()
    try:
        import decimal
        if isinstance(v, decimal.Decimal):
            return float(v)
    except Exception:
        pass
    return v


class Source:
    """Read-only-Verbindung zur IS-H-Replika."""

    def __init__(self, cfg: dict):
        # cfg ist der 'source'-Block der connection.yaml, angereichert um 'scope'
        self.cfg = cfg
        self._conn = None
        pw = cfg.get("password") or ""
        if not pw:
            env = os.environ.get("SAPFHIR_DB_PW")
            if env:
                self.cfg = {**cfg, "password": env}

    # -- Verbindung ---------------------------------------------------------
    def connect(self) -> "Source":
        c = self.cfg
        if _HAVE_PYODBC and c.get("prefer") != "pytds":
            drv = c.get("driver", "ODBC Driver 18 for SQL Server")
            enc = "yes" if c.get("encrypt", True) else "no"
            tsc = "yes" if c.get("trust_server_certificate", False) else "no"
            intent = "ReadOnly" if c.get("read_only_intent", True) else "ReadWrite"
            if c.get("auth") == "ntlm":
                auth = "Trusted_Connection=yes;"
            else:
                auth = f"UID={c['username']};PWD={c['password']};"
            cs = (f"DRIVER={{{drv}}};SERVER={c['host']},{c.get('port',1433)};"
                  f"DATABASE={c['database']};{auth}"
                  f"Encrypt={enc};TrustServerCertificate={tsc};ApplicationIntent={intent}")
            self._conn = pyodbc.connect(cs, readonly=True)
        elif _HAVE_PYTDS:
            kw = dict(
                server=c["host"], port=int(c.get("port", 1433)),
                database=c["database"], as_dict=False,
                cafile=c.get("cafile"),
                validate_host=(c.get("trust_server_certificate", False) is False),
            )
            if c.get("auth") == "ntlm":
                # Windows-Auth ueber pytds; Domain\User im username, sonst NTLM-Login
                kw.update(user=c.get("username"), password=c.get("password"))
            else:
                kw.update(user=c["username"], password=c.get("password", ""))
            self._conn = pytds.connect(**kw)
        else:
            raise RuntimeError("Weder pyodbc noch pytds verfuegbar. "
                               "pip install python-tds")
        return self

    def close(self) -> None:
        if self._conn:
            self._conn.close()
            self._conn = None

    def __enter__(self): return self.connect()
    def __exit__(self, *a): self.close()

    # -- Abfragen -----------------------------------------------------------
    def query(self, sql: str, params: Iterable[Any] = ()) -> list[dict]:
        cur = self._conn.cursor()
        cur.execute(sql, tuple(params))
        cols = [d[0] for d in cur.description]
        out = [{c: to_iso(v) for c, v in zip(cols, row)} for row in cur.fetchall()]
        cur.close()
        return out

    def iter_query(self, sql: str, params: Iterable[Any] = (),
                   arraysize: int = 5000) -> Iterator[dict]:
        """Streamt grosse Resultsets ohne alles in den Speicher zu ziehen."""
        cur = self._conn.cursor()
        cur.arraysize = arraysize
        cur.execute(sql, tuple(params))
        cols = [d[0] for d in cur.description]
        while True:
            rows = cur.fetchmany(arraysize)
            if not rows:
                break
            for row in rows:
                yield {c: to_iso(v) for c, v in zip(cols, row)}
        cur.close()

    def scalar(self, sql: str, params: Iterable[Any] = ()):
        cur = self._conn.cursor()
        cur.execute(sql, tuple(params))
        r = cur.fetchone()
        cur.close()
        return r[0] if r else None

    # -- Rechte-/Verbindungscheck ------------------------------------------
    def check(self) -> dict:
        """Prueft Verbindung, Read-only-Rechte und Sichtbarkeit der Kern-Tabellen."""
        info = {"connected": True}
        info["version"] = self.scalar("SELECT @@VERSION")
        info["db"] = self.scalar("SELECT DB_NAME()")
        # ist der Login nur Leser?
        info["is_datawriter"] = bool(self.scalar(
            "SELECT IS_ROLEMEMBER('db_datawriter')") or 0)
        # Kern-Tabellen sichtbar?
        core = ["NPAT", "NFAL", "NBEW", "NDIA", "NICP"]
        seen = {}
        for t in core:
            try:
                seen[t] = self.scalar(
                    f"SELECT COUNT(*) FROM sap.{t} WHERE 1=0") is not None
            except Exception as e:
                seen[t] = f"ERR: {e}"
        info["core_tables"] = seen
        return info

    def check_registry(self, registry: dict) -> dict:
        """Validiert die tables.yaml-Registry gegen die Live-DB:
        - existieren alle registrierten PK-Spalten? (faengt Fehler wie ein
          faelschlich angenommenes EINRI in NPAT ab, ANALYSE A6)
        - existieren die projizierten Spalten aus config/columns/?
        - weicht der registrierte PK vom echten PRIMARY KEY ab?
        Liefert je Tabelle {'pk_ok', 'missing_pk_cols', 'db_pk', 'missing_proj_cols'}."""
        out = {}
        for tname, reg in registry.items():
            schema = reg.get("schema", "sap")
            info: dict = {}
            cols = {r["COLUMN_NAME"].upper() for r in self.query(
                "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS "
                "WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?", (schema, tname))}
            if not cols:
                out[tname] = {"exists": False}
                continue
            info["exists"] = True
            missing = [c for c in reg.get("pk", []) if c.upper() not in cols]
            info["missing_pk_cols"] = missing
            db_pk = [r["COLUMN_NAME"] for r in self.query(
                "SELECT kcu.COLUMN_NAME "
                "FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc "
                "JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu "
                "  ON kcu.CONSTRAINT_NAME = tc.CONSTRAINT_NAME "
                " AND kcu.TABLE_SCHEMA = tc.TABLE_SCHEMA "
                "WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY' "
                "  AND tc.TABLE_SCHEMA = ? AND tc.TABLE_NAME = ? "
                "ORDER BY kcu.ORDINAL_POSITION", (schema, tname))]
            info["db_pk"] = db_pk
            info["pk_ok"] = (not missing) and (
                not db_pk or [c.upper() for c in reg.get("pk", [])] ==
                [c.upper() for c in db_pk])
            proj = _projection_for(tname)
            info["missing_proj_cols"] = [c for c in (proj or [])
                                         if c.upper() not in cols]
            out[tname] = info
        return out

    # -- CDC-Helfer (Qlik __ct) --------------------------------------------
    def max_change_seq(self, schema: str, table: str) -> str | None:
        """Hoechste change_seq der Qlik-Change-Table <table>__ct."""
        sql = (f"SELECT MAX([header__change_seq]) "
               f"FROM {schema}.[{table}__ct]")
        try:
            return self.scalar(sql)
        except Exception:
            return None

    def min_change_seq(self, schema: str, table: str) -> str | None:
        """Aelteste noch verfuegbare change_seq — fuer die Retention-
        Lueckenerkennung (CONCEPT §14): ist die eigene Watermark aelter,
        wurden Aenderungen von Qlik bereits abgeraeumt."""
        sql = (f"SELECT MIN([header__change_seq]) "
               f"FROM {schema}.[{table}__ct]")
        try:
            return self.scalar(sql)
        except Exception:
            return None

    def changed_rows(self, schema: str, table: str, since_seq: str | None,
                     arraysize: int = 5000) -> Iterator[dict]:
        """Geaenderte Zeilen (I/U/D) aus der Qlik-Change-Table seit change_seq.
        Enthaelt header__change_oper (INSERT/UPDATE/DELETE) + Nutzspalten."""
        if since_seq is None:
            return iter(())  # Backfill laeuft ueber keyset, nicht ueber ct
        sql = (f"SELECT * FROM {schema}.[{table}__ct] "
               f"WHERE [header__change_seq] > ? "
               f"ORDER BY [header__change_seq]")
        return self.iter_query(sql, (since_seq,), arraysize=arraysize)


# --- CLI ---------------------------------------------------------------------
def _load_cfg(path: str) -> dict:
    import yaml  # PyYAML
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _projection_for(table: str) -> list[str] | None:
    p = os.path.join("config", "columns", f"{table}.yaml")
    if os.path.exists(p):
        return _load_cfg(p).get("select")
    return None


def main(argv=None):
    ap = argparse.ArgumentParser(description="IS-H Quell-DB Check")
    ap.add_argument("--config", required=True)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--registry", default="config/tables.yaml",
                    help="tables.yaml fuer den PK-/Spalten-Abgleich")
    args = ap.parse_args(argv)
    cfg = _load_cfg(args.config)
    src = Source(cfg["source"]).connect()
    try:
        if args.check:
            import json
            info = src.check()
            if os.path.exists(args.registry):
                reg = _load_cfg(args.registry).get("tables", {})
                info["registry"] = src.check_registry(reg)
                bad = [t for t, r in info["registry"].items()
                       if r.get("exists") and not r.get("pk_ok")]
                info["registry_ok"] = not bad
                if bad:
                    info["registry_fix_needed"] = bad
            print(json.dumps(info, indent=2, ensure_ascii=False, default=str))
            if not info.get("registry_ok", True):
                raise SystemExit(2)
    finally:
        src.close()


if __name__ == "__main__":
    main()
