# -*- coding: utf-8 -*-
"""Berechtigungs-/Zugriffsschicht (CliniBots Patient Insight).

Setzt das Konzept aus docs/BERECHTIGUNGSKONZEPT.md um: deny-by-default,
Rollen (Medizincontrolling/IT/Einzel-Login = alle) und die Abteilungsregel ueber die
Kostenstellen-Strecke

    AD-Login -> PA0105/90AD -> PERNR -> PA0001.KOSTL
             -> SETNODE/SETLEAF-Rollup (Kostenstellen des Departments)
    Patient  -> NBEW.ORGFA/ORGPF -> NOEK -> Kostenstelle(n)
    sichtbar <=> Fall-Kostenstelle in Department-Kostenstellenmenge

`resolver` ist reine, DB-freie Logik (Graph-Rollup + Rollen); `service` verbindet sie mit
dem DuckDB-Warehouse. Personenidentifizierende HR-Felder bleiben in der Auth-Schicht.
"""
from .resolver import (FULL_ROLES, build_adjacency, descendant_sets,
                       sets_containing, department_kostl, role_scope)

__all__ = ["FULL_ROLES", "build_adjacency", "descendant_sets", "sets_containing",
           "department_kostl", "role_scope"]
