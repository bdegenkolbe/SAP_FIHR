# -*- coding: utf-8 -*-
"""Reine Berechtigungslogik — ohne DB, voll testbar.

Kern ist der Rollup der SAP-Set-Kostenstellenhierarchie (SETNODE = Kanten,
SETLEAF = Kostenstellen-Blaetter) plus die Rollenauswertung.
"""
from __future__ import annotations
from typing import Iterable

# Rollen, die ALLE Patienten sehen duerfen (kein Abteilungsfilter).
FULL_ROLES = {"medizincontrolling", "it", "admin"}


def build_adjacency(setnode_edges: Iterable[tuple[str, str]]) -> dict[str, set[str]]:
    """SETNODE-Kanten (parent_set, child_set) -> Adjazenz parent -> {children}."""
    adj: dict[str, set[str]] = {}
    for parent, child in setnode_edges:
        if parent is None or child is None:
            continue
        adj.setdefault(str(parent), set()).add(str(child))
    return adj


def descendant_sets(adj: dict[str, set[str]], roots: Iterable[str]) -> set[str]:
    """Alle Sets unterhalb (und inkl.) der roots — zyklensicher per Besuchsmenge."""
    seen: set[str] = set()
    stack = [str(r) for r in roots]
    while stack:
        s = stack.pop()
        if s in seen:
            continue
        seen.add(s)
        stack.extend(adj.get(s, ()))
    return seen


def sets_containing(setleaf: Iterable[tuple[str, str]], kostl: Iterable[str]) -> set[str]:
    """Sets, die (mindestens) eine der Kostenstellen als Blatt enthalten.

    setleaf: (setname, kostl_value). kostl: gesuchte Kostenstellen.
    """
    want = {str(k) for k in kostl}
    return {str(sn) for sn, k in setleaf if str(k) in want}


def leaves_of(setleaf: Iterable[tuple[str, str]], sets: Iterable[str]) -> set[str]:
    """Alle Kostenstellen-Blaetter der angegebenen Sets."""
    want = {str(s) for s in sets}
    return {str(k) for sn, k in setleaf if str(sn) in want}


def department_kostl(setnode_edges, setleaf, employee_kostl, *, expand: bool = True) -> set[str]:
    """Kostenstellenmenge, die ein Mitarbeiter sehen darf.

    1. Sets bestimmen, die die Mitarbeiter-Kostenstelle(n) direkt enthalten (= sein
       Department/seine Gruppe(n)).
    2. Wenn expand: alle Unter-Sets dazunehmen (Leitung erbt Unter-OEs), sonst nur die
       direkten Gruppen.
    3. Alle Kostenstellen-Blaetter dieser Sets zurueckgeben (immer inkl. der eigenen).
    """
    setleaf = list(setleaf)
    emp = {str(k) for k in employee_kostl if k}
    if not emp:
        return set()
    groups = sets_containing(setleaf, emp)
    if not groups:
        return set(emp)  # Kostenstelle ohne Set -> nur sie selbst (fail-closed eng)
    if expand:
        adj = build_adjacency(setnode_edges)
        groups = descendant_sets(adj, groups)
    return leaves_of(setleaf, groups) | emp


def role_scope(role: str | None) -> str:
    """'ALL' fuer Vollrollen, 'DEPT' fuer Abteilungsregel, 'NONE' sonst (deny-by-default)."""
    if not role:
        return "NONE"
    return "ALL" if str(role).strip().lower() in FULL_ROLES else "DEPT"
