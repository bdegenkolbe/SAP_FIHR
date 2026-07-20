# -*- coding: utf-8 -*-
"""Auth-Service: verbindet die reine Resolver-Logik mit einem Daten-Backend.

Deny-by-default: ohne Nutzer/Rolle keine Patienten. Vollrollen (Medizincontrolling/IT/
Admin) sehen alle; Abteilungspersonal nur Patienten mit Fall-Kostenstelle in der eigenen
Department-Kostenstellenmenge (SETNODE-Rollup).

Backends kapseln die Datenherkunft:
- `InMemoryBackend` — fuer Tests/Demo (synthetische Strukturen).
- `DuckDBBackend`   — liest das im Warehouse materialisierte `auth`-Schema (sql.build).
Fehlt eine Auth-Tabelle, liefert das Backend leere Mengen → Abteilungsnutzer sehen nichts
(fail-closed), Vollrollen bleiben nutzbar.
"""
from __future__ import annotations
from . import resolver


class InMemoryBackend:
    def __init__(self, *, login_pernr=None, pernr_kostl=None, setnode=None,
                 setleaf=None, fall_kostl=None):
        # login (UPPER) -> [PERNR]
        self._login_pernr = {str(k).upper(): list(v) for k, v in (login_pernr or {}).items()}
        # PERNR -> [KOSTL]
        self._pernr_kostl = {str(k): list(v) for k, v in (pernr_kostl or {}).items()}
        self._setnode = list(setnode or [])       # [(parent_set, child_set)]
        self._setleaf = list(setleaf or [])        # [(set_id, kostl)]
        self._fall_kostl = list(fall_kostl or [])  # [(patnr, falnr, kostl)]

    def employee_kostl(self, login: str) -> set[str]:
        out: set[str] = set()
        for pernr in self._login_pernr.get(str(login).upper(), []):
            out.update(self._pernr_kostl.get(str(pernr), []))
        return out

    def setnode_edges(self):
        return self._setnode

    def setleaf(self):
        return self._setleaf

    def patient_kostl(self, patnr: str) -> set[str]:
        return {k for (p, f, k) in self._fall_kostl if p == patnr}


class DuckDBBackend:
    def __init__(self, warehouse_path: str):
        self.path = warehouse_path

    def _q(self, sql, params=None):
        import duckdb
        con = duckdb.connect(self.path, read_only=True)
        try:
            return con.execute(sql, params or []).fetchall()
        except duckdb.Error:
            return []
        finally:
            con.close()

    def employee_kostl(self, login: str) -> set[str]:
        rows = self._q(
            "SELECT DISTINCT k.kostl FROM auth.login_pernr l "
            "JOIN auth.pernr_kostl k USING (PERNR) WHERE l.login = ?",
            [str(login).upper()])
        return {r[0] for r in rows if r[0]}

    def setnode_edges(self):
        return [(r[0], r[1]) for r in self._q("SELECT parent_set, child_set FROM auth.setnode")]

    def setleaf(self):
        return [(r[0], r[1]) for r in self._q("SELECT set_id, kostl FROM auth.setleaf")]

    def patient_kostl(self, patnr: str) -> set[str]:
        rows = self._q("SELECT DISTINCT kostl FROM auth.fall_kostl WHERE PATNR = ?", [patnr])
        return {r[0] for r in rows if r[0]}


class Authz:
    """Zentrale Zugriffsentscheidung. `roles` bildet Login (UPPER) -> Rolle ab."""

    def __init__(self, backend, roles: dict[str, str] | None = None, *, expand: bool = True):
        self.backend = backend
        self.roles = {str(k).upper(): str(v) for k, v in (roles or {}).items()}
        self.expand = expand

    def role_of(self, login: str | None) -> str | None:
        if not login:
            return None
        return self.roles.get(str(login).upper())

    def scope(self, login: str | None) -> str:
        return resolver.role_scope(self.role_of(login))

    def visible_kostl(self, login: str) -> set[str]:
        """Kostenstellenmenge des Nutzers (nur fuer DEPT relevant)."""
        emp = self.backend.employee_kostl(login)
        return resolver.department_kostl(self.backend.setnode_edges(), self.backend.setleaf(),
                                         emp, expand=self.expand)

    def may_see_patient(self, login: str | None, patnr: str) -> bool:
        sc = self.scope(login)
        if sc == "ALL":
            return True
        if sc == "NONE":
            return False
        pk = self.backend.patient_kostl(patnr)
        return bool(pk & self.visible_kostl(login))

    def filter_patnr(self, login: str | None, patnrs):
        sc = self.scope(login)
        if sc == "ALL":
            return list(patnrs)
        if sc == "NONE":
            return []
        vis = self.visible_kostl(login)
        return [p for p in patnrs if self.backend.patient_kostl(p) & vis]

    def whoami(self, login: str | None) -> dict:
        sc = self.scope(login)
        return {"login": login, "rolle": self.role_of(login), "scope": sc,
                "sieht_alle": sc == "ALL"}
