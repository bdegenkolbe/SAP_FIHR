# Verifikationsrunde 4 (offizielle Doku, Konfliktauflösung) — CliniBots Patient Insight

> **STATUS: ARCHIV** — historisches Protokoll. Fortlaufendes Log ab R8: `VERIFY_LOG_R8-R13.md`.

Stand 15.07.2026 · Quelle: sapdatasheet.org (SAP-Data-Dictionary-Spiegel), ohne DB-Zugriff.
Löst die in `docs/ALTBESTAND_ANALYSE.md §2` offen markierten Deutungskonflikte auf.

## 1. NDIA-Flags — Konflikte entschieden (Tabelle NDIA, offizielles DDIC)

| Feld | Offizielle Bedeutung | Runde 3 sagte | Altbestand sagte | Ergebnis |
|---|---|---|---|---|
| **PODIA** | „**Preoperative** Diagnosis Indicator" | postoperativ ✗ | präoperativ ✓ | **präoperative Diagnose** |
| **ARDIA** | „**Working Diagnosis** Indicator" | Arbeitsunfalldiagnose ✗ | Arbeitsdiagnose ✓ | **Arbeitsdiagnose** (Verdachts-/Arbeitshypothese) |
| **TUDIA** | „IS-H: **Cause of Death** Indicator" | Tumordiagnose ✗ | Todesursache ✓ | **Todesursache** |
| **DIAGW** | „Diagnostic Certainty" | — | Diagnosesicherheit ✓ | **DIAGW = Diagnosesicherheit** (primär) |
| **DIASI** | „IS-H: Diagnostic Certainty" | im Haus leer ✓ | — | Fallback, generisch behalten |
| DIAPR | „Medical Secondary Diagnosis Indicator" | — | med. Nebendiagnose ✓ | bestätigt |
| DIALO | „IS-H: Localization of Diagnosis" | — | Lokalisation ✓ | bestätigt |
| DITXT | „IS-H: Free-Text Diagnosis" | ✓ | ✓ | bestätigt |
| KZTXT | „IS-H: Comment on Diagnosis" | — | Bemerkung ✓ | bestätigt |

Fazit: In allen drei Konflikten lag der **produktive Altbestand richtig** und die
Raterunde falsch — bestätigt die Regel „Katalog/Doku schlägt Vermutung".

## 2. NBEW.BEWTY — offiziell bestätigt (Datenelement/Domäne BEWTY)

Festwerte laut SAP-DDIC: **1=admission, 2=discharge, 3=transfer, 4=outpatient
visit, 6=absence start date, 7=absence end date.**

Damit ist die Altbestand-Korrektur amtlich: **2=Entlassung, 3=Verlegung** (v0.1 und
Verifikationsrunde 3 hatten es vertauscht). 6/7 sind Beginn/Ende einer Abwesenheit
(Beurlaubung) — die exakt gleichen Live-Zählwerte (je 240.862) passen dazu.

## 3. Umgesetzt

- `fhir/mappers/core.py`: VERIFY-KONFLIKT-Marker bei PODIA/ARDIA entfernt,
  Klartexte fixiert; BEWTY-Kommentar auf „offiziell bestätigt".
- `config/columns/NDIA.yaml`: Kommentare final.
- `docs/ALTBESTAND_ANALYSE.md §2/§8`: Konflikte als aufgelöst markiert.
- CONCEPT §20.13 erledigt.

Quellen: sapdatasheet.org — Tabelle NDIA (`/abap/tabl/ndia.html`),
Datenelement BEWTY (`/abap/dtel/bewty.html`).
