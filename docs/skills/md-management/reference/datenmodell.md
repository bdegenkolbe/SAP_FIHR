# Datenmodell und Fallen (geprüft live gegen die Replika)

Quellen: SAP_FIHR `docs/VERIFY_LOG_R8-R13.md` R17/R18/R34, `config/tables.yaml`
(RKT-Block); MD_Management `docs/VALIDIERUNG.md` R33–R40, `docs/QLIK_RKT_ABGLEICH.md`.
Mandant 100, Einrichtung 0001. Stand 15.11.2026.

## Mengengerüst

| Tabelle | Zeilen | Rolle |
|---|---:|---|
| ZNRKT_KOPF | 248.958 | Vorgang; PK `[MANDT,EINRI,FALNR,KOSTR,LFDNR]` |
| ZNRKT_REKL | 1.364.981 Statuszeilen / 295.179 Reklamationen | Workflow, Gründe, Ergebnis, Rechnung |
| ZNRKT_BER | ~968.000 | Unterlagenanforderungen (Fristenquelle) |
| ZNRKT_BERMAHN | 22.744 | Mahnungen zu Unterlagen — **nur bis 2015**, ab 2023 keine Zeilen (MDM R45) |
| ZNRKT_AUF | ~968.000 | Aufgaben/Wiedervorlagen |
| ZNRKT_DRG | 196.359 | DRG-Streit, 6 Sichten |
| ZNRKT_ICD / OPS / Z75 / BEA / TOB | 279k / 49k / 165k / 15k / 78k | Streit je Gegenstand |
| ZNRKT_FAK | 564.567 | Fakturabezug |
| ZNRKT_MCS | 219.494 | Ergebnisklassifikation je Vorgang (Fehlerursache) |
| ZNRKT_KG | 238.271 | Papierakten-Logistik |
| ZNRKT_MDK | 18.507 | MD-Begehungstermine (aktiv) |
| ZNRKT_KLA | 4.455 | Klageverfahren (75–110 neue/Jahr) |
| ZNRKT_C_* | 59 Tabellen | Customizing/Kataloge |

## Fallen

1. **Statuszeilen-Ebene.** `ZNRKT_REKL` hat im Mittel 4,6 (max. 32) Statuszeilen je
   Reklamation; `REK_NETWR` steht auf jeder. Naive Summe = rund 7-fach (9,46 Mrd € statt
   1,28 Mrd € über die Gesamtlaufzeit). Richtig je Jahr (REK_REDAT): 2019 142,4 Mio,
   2022 90,8 Mio, 2025 102,5 Mio €.
2. **LFDNR = Vorgangsart**, kein Zähler (001–003 / 400–409 / 410–419).
3. **`PRF_BEG/PRF_END`** sind bei Rechnungsabweisung und interner Prüfung leer
   (prozessbedingt) → keine Fristenbasis.
4. **Sentinels:** `0101-01-01` (SAP-Leerdatum via Qlik), `0001-01-01`, `9999-12-31`.
   Leere Flags sind ein Leerzeichen `' '`, nicht NULL.
5. **`ZNRKT_DRG._MDE` leer**; Endergebnis steht in `_RKT`.
6. **Vorgangstyp `RKTTYP`** ist erst ab 02/2015 gepflegt (`RKT_VERSION` = Release-
   Stempel des Add-ons; Strukturbrüche an den Release-Grenzen).
7. **`RKT_PHASE`** hat drei Werte: RKZ (formal), MDK (medizinisch), VVF
   (Vorverfahren/Erörterung); Altbestand `' '`.
8. **`'-'` in ICD/OPS-Sichten** ist ein Aktionskennzeichen, kein Kode.
9. **NFAL.BEGDT/ENDDT** sind bei stationären Fällen Sentinel — Fallzeitraum aus NBEW
   (SAP_FIHR `gold.fall_zeitraum`).
10. **Kostenträger `KOSTR`** → `NGPA.GPART` (99,6 %, mit IK 99,4 %); Kassengruppen aus
    `ZHC_RKT_KTRGR` / `ZHC_KTR_KTRGR`.
11. Offene Reklamationen ohne Bewegung > 12 Monate: 8.131 von 12.206 → Altlasten,
    getrennt ausweisen.
12. **Storno vor Status:** 20.322 stornierte Aufgaben (`ZNRKT_AUF`) stehen noch auf
    NEU/INAR/WAST. Immer `AUF_STORN` filtern, dann erst den Status lesen.
13. **`ZNRKT_MCS` ist die Ergebnisklassifikation je Vorgang** (1 Zeile/Vorgang,
    `MCS_ERG` → `C_MCSERG`: kein Fehler, Fehlbelegung, Dokumentation …), kein
    Datenaustausch.
14. **`ZNRKT_FAK`:** V = Rechnung vorher, N = nachher; `FAK_STREIT`/`FAK_ERGEBNIS` tot;
    Platzhalterbelege („RECHNUNG01“, „RESTBTR“, leere VBELN) nie gegen SD joinen.
15. **ICD-Sicht mit `ICD_LFDNR_NDIA` ≥ 800** = von MD/Kasse eingebrachter Kode ohne
    Hauszeile in NDIA.
16. **`ZNRKT_MDK` ist aktiv** (Begehungstermine bis in die Zukunft), nur Gutachten-/CW-
    Felder sind tot. **`ZNRKT_KLA`:** 34 Felder tot (Instanzweg, Gutachten, Beträge).
17. **Katalogschlüssel sind Text mit Zeitscheiben** (`C_KLAERLGR`, `C_REKLERL` …) —
    Duplikate je Schlüssel möglich.
18. **TOB-Tage** stehen als Text (`nvarchar`) → vor dem Rechnen casten.

## Ergebnisklassen (ZNRKT_C_REKLERL.GRUPPE)

| GRUPPE | Erledigungsgründe |
|---|---|
| gewonnen | Ohne Änderung · Aufwandspauschale · Konsens ohne Rechnungskorrektur |
| verloren | Rechnungsänderung · Konsens mit Rechnungskorrektur |
| Kompromiss | Beendigung nach DTA · Beendigung nach Datenkorrektur (VVF) |
| MDK | Beauftragung des MDK · Dissens · Vorverfahren abgelehnt |
| (leer) | Vorgang erledigt (ab 02/2020) · RAW-/INP-Gründe |

Achtung: Der Katalog hat Gültigkeitsscheiben; je Schlüssel `MAX(GRUPPE)` oder
zeitscharf joinen.
