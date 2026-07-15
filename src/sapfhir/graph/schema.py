# -*- coding: utf-8 -*-
"""Kuzu-Graphschema (CONCEPT §7).

Knoten: Patient, Fall, Bewegung, Diagnose, Prozedur, OE
Kanten: HAT_FALL, HAT_BEWEGUNG, IN_OE, HAT_DIAGNOSE, HAT_PROZEDUR,
        FOLGT_AUF (Bewegungskette), WIEDERAUFNAHME (abgeleitet: Folgefall
        < N Tage UND gleiche ICD-Dreisteller-Gruppe der Hauptdiagnose).
"""

NODES = [
    "CREATE NODE TABLE IF NOT EXISTS Patient(patnr STRING, gender STRING, "
    "PRIMARY KEY(patnr))",
    "CREATE NODE TABLE IF NOT EXISTS Fall(falnr STRING, fallart STRING, "
    "beg DATE, ende DATE, PRIMARY KEY(falnr))",
    "CREATE NODE TABLE IF NOT EXISTS Bewegung(bewid STRING, bewtyp STRING, "
    "beg DATE, ende DATE, PRIMARY KEY(bewid))",
    "CREATE NODE TABLE IF NOT EXISTS Diagnose(icd STRING, PRIMARY KEY(icd))",
    "CREATE NODE TABLE IF NOT EXISTS Prozedur(ops STRING, PRIMARY KEY(ops))",
    "CREATE NODE TABLE IF NOT EXISTS OE(oeid STRING, PRIMARY KEY(oeid))",
]

RELS = [
    "CREATE REL TABLE IF NOT EXISTS HAT_FALL(FROM Patient TO Fall)",
    "CREATE REL TABLE IF NOT EXISTS HAT_BEWEGUNG(FROM Fall TO Bewegung)",
    "CREATE REL TABLE IF NOT EXISTS IN_OE(FROM Bewegung TO OE)",
    "CREATE REL TABLE IF NOT EXISTS HAT_DIAGNOSE(FROM Fall TO Diagnose)",
    "CREATE REL TABLE IF NOT EXISTS HAT_PROZEDUR(FROM Fall TO Prozedur)",
    "CREATE REL TABLE IF NOT EXISTS FOLGT_AUF(FROM Bewegung TO Bewegung)",
    # heuristische Kante — nur Ergaenzung fuer Faelle OHNE formale Zusammenfuehrung
    "CREATE REL TABLE IF NOT EXISTS WIEDERAUFNAHME(FROM Fall TO Fall, tage INT64)",
    # echte, GKV-rechtliche Fallzusammenfuehrung aus NAPX_FAL (FPV/KFPV):
    # fuehrender Fall (LEAD='X') -> untergeordneter Fall, mit Grund-Kode+Klartext
    "CREATE REL TABLE IF NOT EXISTS FUEHRT_ZUSAMMEN(FROM Fall TO Fall, "
    "reason STRING, reason_text STRING)",
]

DDL = NODES + RELS
