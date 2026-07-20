# Verifikationsrunde 3 (NDIA-Diagnosetypen vertieft) — CliniBots Patient Insight

> **STATUS: ARCHIV** — historisches Protokoll. Fortlaufendes Log ab R8: `VERIFY_LOG_R8-R13.md`.

Stand 15.07.2026, `replicate` read-only. Vertieft die NDIA-Diagnoseverwendung und
korrigiert zwei Mapper-Fehler.

## 1. Diagnosetyp-Flags (Live-Verteilung, ohne Storno; Basis 22.868.813 Diagnosen)

| Flag | Bedeutung | Anzahl | Anteil |
|---|---|---:|---:|
| BHDIA | Behandlungsdiagnose | 21.974.784 | 96,1 % |
| ENDIA | Entlassdiagnose | 5.736.285 | 25,1 % |
| FHDIA | Fachabteilungshauptdiagnose | 1.869.835 | 8,2 % |
| OPDIA | OP-Diagnose | 1.846.032 | 8,1 % |
| AFDIA | Aufnahmediagnose | 1.703.157 | 7,4 % |
| KHDIA | Krankenhaushauptdiagnose | 1.576.127 | 6,9 % |
| EWDIA | Einweisungsdiagnose | 894.027 | 3,9 % |
| ARDIA | Arbeitsunfalldiagnose | 111.013 | 0,5 % |
| PODIA | postoperative Diagnose | 38.303 | 0,2 % |
| TUDIA | Tumordiagnose | 9.736 | 0,04 % |

## 2. Kernbefund: Flags sind NICHT exklusiv

Eine Diagnose trägt regelmäßig **mehrere** Verwendungsrollen gleichzeitig. Live-Muster
für KH-Hauptdiagnosen (KHDIA='X'): fast immer zusätzlich **FHDIA + BHDIA**, häufig auch
AFDIA. Beispiel Fall 0020942167 (N98.1 Überstimulationssyndrom): KHDIA+FHDIA+AFDIA+BHDIA
gleichzeitig.

**Korrektur Mapper `map_condition`:** Die bisherige Einzelkategorie-Logik
(`_dia_kategorie`, "KHDIA schlägt alles" → genau eine Kategorie) war falsch. Jetzt
`_dia_kategorien` → gibt **alle** zutreffenden Flags als `Condition.category[]` aus.
Damit bleibt die volle Diagnosesemantik erhalten (eine Diagnose kann gleichzeitig
KH-Haupt-, Fachabt.- und Behandlungsdiagnose sein).

## 3. Kernbefund: DKEY2 ist meist KEINE Kreuz-Stern-Sekundärdiagnose

DKEY1/DKEY2 mit zugehörigem Katalog DKAT1/DKAT2 verhalten sich so:
- DKAT1 = '56' (aktuelle ICD-10-GM-Version), DKAT2 = '49/51/53/54/55' (ältere Jahrgänge).
- In **14.403.124 von 15.380.141** Fällen mit DKEY2 gilt **DKEY1 = DKEY2** — es ist
  derselbe ICD-Kode in einer anderen Katalogversion (Umschlüsselungs-Historie),
  KEINE zweite Diagnose.
- Nur **977.017** Fälle haben DKEY1 ≠ DKEY2 (echte Zweitkodierung / Kreuz-Stern).

**Korrektur Mapper `map_condition`:** DKEY2 wird nur noch dann als zweites `coding`
ausgegeben, wenn `DKEY1 ≠ DKEY2`. Vorher hätte der Mapper ~14,4 Mio Kode-Dubletten
erzeugt. Katalog-Kennungen: DKAT '56' = aktuelle ICD-10-GM; '49'–'55' = ältere ICD-10-GM-
Jahresversionen (alle → System `icd-10-gm`).

## 4. DIASI (Diagnosesicherheit) — im Haus nicht gepflegt

Alle 22,87 Mio Diagnosen haben DIASI = leer. Die ICD-Diagnosesicherheit
(V=Verdacht / G=gesichert / A=ausgeschlossen / Z=Zustand nach) wird in diesem Haus
NICHT in NDIA.DIASI geführt. Der Mapper behält die Extension generisch (füllt sie nur,
wenn belegt), erzeugt hier aber faktisch keine Diagnosesicherheit. Falls Sicherheit
benötigt wird: ggf. als ICD-Zusatzkennzeichen an anderer Stelle suchen (offen).

## 5. Umgesetzte Änderungen

- `fhir/mappers/core.py`: `_dia_kategorie` → `_dia_kategorien` (Liste, alle Flags);
  DKEY2 nur bei echtem Kode-Unterschied als zweites Coding.
- `config/columns/NDIA.yaml`: schmale Projektion um alle Diagnosetyp-Flags erweitert.
- Tests: `test_map_condition_hardened` (Mehrfachkategorien),
  `test_map_condition_dkey2_katalog_redundanz`, `test_map_condition_echter_zweitkode`.

## 6. Diagnosekatalog-Kennungen (DKAT), verifiziert

| DKAT | Bedeutung |
|---|---|
| 56 | ICD-10-GM, aktuelle Version (Primärkode) |
| 49, 51, 53, 54, 55 | ICD-10-GM, ältere Jahresversionen (Umschlüsselung) |

Alle → FHIR-System `http://fhir.de/CodeSystem/bfarm/icd-10-gm`. Für DRG-relevante
Auswertungen zählt der Primärkode (DKAT1='56').
