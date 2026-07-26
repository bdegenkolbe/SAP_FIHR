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


# Obergrenze fuer die Blattzahl eines Sets, das noch als "Abteilung" zaehlt.
# R29-Befund: SETLEAF enthaelt neben Organisationsgruppen auch Auswertungs-/Sammel-
# und Testgruppen (z.B. TEST_PFL mit 1.964 Kostenstellen, persoenliche Berichtssets).
# Wer in so einem Set steckt, ist NICHT fuer alle darin enthaltenen OEs zustaendig.
MAX_DEPT_SET_LEAVES = 60


def department_kostl(setnode_edges, setleaf, employee_kostl, *, expand: bool = True,
                     max_set_leaves: int = MAX_DEPT_SET_LEAVES) -> set[str]:
    """Kostenstellenmenge, die ein Mitarbeiter sehen darf (fail-closed).

    1. Je Mitarbeiter-Kostenstelle die **spezifischste** Gruppe waehlen: das kleinste
       Set, das sie enthaelt. Grosse Sammel-/Auswertungsgruppen (> max_set_leaves
       Blaetter) werden verworfen — sie sind keine Organisationseinheit (R29).
    2. Wenn expand: Unter-Sets dazunehmen (Leitung erbt Unter-OEs) — aber nur unterhalb
       der spezifischen Gruppe, und Unter-Sets ueber der Groessengrenze bleiben aussen.
    3. Blaetter dieser Sets zurueckgeben, immer inkl. der eigenen Kostenstellen.
    """
    setleaf = list(setleaf)
    emp = {str(k) for k in employee_kostl if k}
    if not emp:
        return set()

    # Blaetter je Set einmal aufbauen (statt je Kandidat neu zu filtern)
    leaves_by_set: dict[str, set[str]] = {}
    for sn, k in setleaf:
        if sn is None or k is None:
            continue
        leaves_by_set.setdefault(str(sn), set()).add(str(k))

    def _ok(s: str) -> bool:
        return len(leaves_by_set.get(s, ())) <= max_set_leaves

    # (1) spezifischste Gruppe je eigener Kostenstelle
    groups: set[str] = set()
    for k in emp:
        cand = [s for s, lv in leaves_by_set.items() if k in lv and _ok(s)]
        if not cand:
            continue
        kleinste = min(len(leaves_by_set[s]) for s in cand)
        groups.update(s for s in cand if len(leaves_by_set[s]) == kleinste)
    if not groups:
        return set(emp)  # keine geeignete Gruppe -> nur eigene Kostenstellen

    # (2) Rollup nach unten, Groessengrenze bleibt wirksam
    if expand:
        adj = build_adjacency(setnode_edges)
        groups = {s for s in descendant_sets(adj, groups) if _ok(s)}

    # (3) Blaetter der zugelassenen Sets
    out: set[str] = set(emp)
    for s in groups:
        out |= leaves_by_set.get(s, set())
    return out


def role_scope(role: str | None) -> str:
    """'ALL' fuer Vollrollen, 'DEPT' fuer Abteilungsregel, 'NONE' sonst (deny-by-default)."""
    if not role:
        return "NONE"
    return "ALL" if str(role).strip().lower() in FULL_ROLES else "DEPT"
