# MD-Management (Medizincontrolling / MDK-Fallsteuerung) — Domänenanalyse & App-Konzept

> **STATUS: UMGESETZT als „CliniBots MDM"** (eigenständiges Repo `C:\ai\MD_Management`,
> Stufen 1–3 + Erlös-/Kassen-/Downcoding-Analytik, Audit-Hashkette, Credential-Store,
> Deployment; siehe dortige `docs/VALIDIERUNG.md` + `docs/DEPLOYMENT.md`). Dieses
> Dokument bleibt als **Domänenmodell-Referenz** (ZNRKT-Familie, DIAS-Tripel) und für
> die Verbund-Schnittstelle (MD-Badge → MDM-Fall-Akte, `ROADMAP.md` P2.5/P4.3) gültig.
> §5-Architekturoptionen/§6-Schritte sind historisch (Entscheidung: eigenständige App).

**Stand:** R17-Anschluss (19.07.2026), Analyse live gegen `higl-main` (read-only).
**Auslöser:** „Schau dir die Aufbereitung von RKT im DIAS-Cube an — das ist das
MD-Management, hier müssen wir eine eigene Anwendung bauen." (Björn)

Dieses Dokument beschreibt (1) was das RKT-Modul in i.s.h.med fachlich ist, (2) wie DIAS
es heute auswertet, (3) das verifizierte Datenmodell und die Mengengerüste, (4) einen
Architekturvorschlag für die eigene Anwendung. Es ist die Grundlage für die
Scope-Entscheidung — noch KEINE Implementierung.

---

## 1. Was ist „RKT"? (fachliche Einordnung)

`RKT` = **Rechnungskürzung / MDK- bzw. MD-Prüfverfahren** — das i.s.h.med-Zusatzmodul
zur Steuerung von Krankenkassen-Rechnungsprüfungen nach **§ 275c SGB V** (MD-Prüfung)
und **§ 17c KHG** (Erörterungsverfahren). Fachlich das Arbeitsgebiet des
**Medizincontrollings / MD-Managements**: Die Kasse (bzw. der Medizinische Dienst, MD,
früher MDK) beanstandet eine Krankenhausrechnung; das Haus muss innerhalb gesetzlicher
Fristen Unterlagen liefern, das Ergebnis prüfen, ggf. widersprechen, ein
Erörterungsverfahren führen und am Ende Erlösdifferenzen und Aufwandspauschalen
verbuchen. RKT ist der operative Workflow dafür; der DIAS-Cube ist die retrospektive
Auswertung.

Die physischen Tabellen liegen im **kundeneigenen Z-Namensraum** (`sap.ZNRKT_*`) — kein
SAP-Standard, sondern eine Hauslösung (oder Add-on eines Dienstleisters). Deshalb gibt
es dafür keine sapdatasheet.org-Referenz; der Dreiklang stützt sich hier auf
Schema + Daten + DIAS-Feldsemantik.

---

## 2. Wie DIAS RKT aufbereitet (der eigentliche „Cube")

Der DIAS-Objektbaum `D_1 DIAS ANALYTICS` enthält **236 Felder** rund um das
MD-Management. Kernstruktur ist ein **Vergleichs-Tripel je Streitdimension**:

| DIAS-Feldsuffix | Bedeutung |
|---|---|
| `_ISH` / (Ausgangswert) | Was das Haus abgerechnet hat (i.s.h.med-Ausgangsrechnung) |
| `_Forderung_Kasse` | Was die Krankenkasse fordert |
| `_Forderung_MD` | Was der Medizinische Dienst gutachterlich fordert |
| `_Ergebnisvereinbarung` | Das verhandelte Endergebnis (Erörterung/Vergleich) |

…und das über **jede strittige Dimension**: `DRG_Code`, `Bewertungsrelation`,
`DRG_Entgelt`, `DRG_Grundpreis`, `Operationscode` (OPS), `Diagnoseschluessel` (ICD),
`Beatmungsdauer`, `Pflegeentgelt`/`Pflege_VWD`, `ToB`/`MDToB` (Tage ohne Berechnung),
`ZuAbschlag`, `Leistungsentgelt`/`-menge`/`-identifikation`. Dazu Workflow-/Ergebnis-
Felder: `MDK_Beauftragung_am`, `Gutachten_vom/_eingegangen_am/_Ergebnis`, `Prueffrist_
Beginn/Ende`, `Kürzung_akzeptiert/_abgelehnt`, `Streitwert*`, `Klageprüfung_*`,
`Rechnung_hat_MD_Verfahren`, `Rechnung_mit_negativem_MD_Leistungsentscheid`,
`Aufwandspauschale`, `Reklamationsgrund1-4`, `Reklamationsphase`.

**Wichtige Erkenntnis:** Das DIAS-Vergleichstripel wird NICHT aus `ZNRKT_MDK.CW_*`
gespeist (die Spalten sind im Haus leer / Alt-Workflow, s. §3), sondern aus den
**6 Parallelsichten von `ZNRKT_DRG`** (`_ISH/_KK/_MDK/_MDE/_ANF/_RKT` =
i.s.h.med / Krankenkasse / MD-Prüfung / MD-Entscheid / Anforderung / Rechnung) plus
`ZNRKT_REKL` (Workflow, Fristen, Gründe, OPS/ICD-Streit) plus `ZNRKT_KOPF` (Streitwert,
Fristen, Fallklammer).

---

## 3. Verifiziertes Datenmodell (live R17)

Alle `ZNRKT_*` teilen die **Fallklammer-PK-Wurzel** `[MANDT, EINRI, FALNR, KOSTR, LFDNR]`
(Fall + Kostenträger + laufende Nummer des Prüfvorgangs) und hängen damit direkt an
`NFAL`/`NKTR`. Storno durchgängig über `*_STORN='X'` (+ `STUSR/STDAT`) — kompatibel zur
`entered-in-error`-Logik.

| Tabelle | Spalten | Zeilen | PK (live 100 % eindeutig) | Rolle |
|---|---|---|---|---|
| `ZNRKT_KOPF` | 127 | 244.715 | `[…,FALNR,KOSTR,LFDNR]` | **Vorgangskopf**: Typ, Fristen, Streitwert, MD-Arzt, Fallklammer WIKE/XXXX |
| `ZNRKT_REKL` | 138 | 1.339.366 | `[…,LFDNR,REKL_POS,REKL_ST_POS]` | **Reklamations-/Statuszeilen** (operatives Herz, aktuell bis 2026) |
| `ZNRKT_DRG` | 147 | 193.243 | `[…,LFDNR,DRG_LFDNR_RKT,DRG_LFDNR_NDRG]` | **Erlös-Nachrechnung** je Sicht (6× ISH/KK/MDK/MDE/ANF/RKT); Root allein nur 178.425 → mehrere DRG-Zeilen je Vorgang |
| `ZNRKT_MDK` | 47 | 18.153 | `[…,LFDNR,MDKPOS]` | MDK-**Begehungstermine** (Alt-Workflow, Gutachtendaten ≤2013) |
| `ZNRKT_BER` | — | 957.295 | `[…,BER_LFDNR]` | Berichte/Unterlagen-Positionen |
| `ZNRKT_AUF` | 28 | 944.353 | `[…,AUF_LFDNR]` | **Aufgaben/Wiedervorlagen** (97 Typen) — Kern Stufe 2 |
| `ZNRKT_FAK` | 32 | 552.286 | `[…,FAK_MODUL,REKL_POS,KLA_LFDNR,FAK_LFDNR]` | Fakturabezug/Rechnungen |
| `ZNRKT_ICD` | 45 | 275.544 | `[…,ICD_LFDNR_RKT,ICD_LFDNR_NDIA]` | ICD-Streit (6 Sichten, → NDIA) |
| `ZNRKT_KG` | 34 | 238.146 | `[…,KGSNR,KGPOS]` | Akten-/Unterlagenanforderung (NICHT Katalog!) |
| `ZNRKT_MCS` | — | 216.089 | `[…,MCS_LFDNR]` | MD-Comm-Server / elektr. §301-Kommunikation |
| `ZNRKT_Z75` | — | 163.355 | `[…,Z75_LFDNR_RKT,Z75_LFDNR_NLEI]` | Zusatzentgelte-Streit (→ NLEI) |
| `ZNRKT_TOB` | — | 76.795 | `[…,TOB_LFDNR]` | Tage ohne Berechnung |
| `ZNRKT_OPS` | — | 48.335 | `[…,OPS_LFDNR_RKT,OPS_LFDNR_NICP]` | OPS-Streit (→ NICP) |
| `ZNRKT_BEA` | — | 15.234 | `[…,BEA_LFDNR_RKT,BEA_LFDNR_NFAL]` | Beatmungsstunden-Streit (→ NFAL) |
| `ZNRKT_KLA` | 77 | 4.442 | `[…,KLA_LFDNR]` | Klageverfahren (SG→LSG→BSG) |
| `ZNRKT_KG_TXT` | 10 | 1.749 | `[…,OBJNR,OBUNR,TXT_LFDNR]` | Langtexte zu KG-Anforderungen |

Alle PKs live verifiziert (R18, 100 % eindeutig). Muster: Streitzeilen tragen einen
Doppelschlüssel RKT-Position + Quelltabellen-Position und brücken so zum medizinischen
Kern (OPS→NICP, ICD→NDIA, Z75→NLEI, BEA→NFAL) — der saubere Join-Pfad für den
Kodier-Feedback-Loop.

**Mengengerüst & fachliche Kennzahlen (live, storniert ausgefiltert):**
- **229.047 Fälle** mit MD-Prüfvorgang, **244.715 Vorgänge** (KOPF), nur 1.175 storniert.
- Vorgangstypen (`RKTTYP`): `0_DRG` (DRG-Prüfung) 110.568 · `FORMRABW` (formale
  Rechnungsabweisung) 54.829 · `INTPRUE` (interne Prüfung) 19.644 · `0_PSYCH` 1.758 ·
  `0_SONST`/`0_AMBU` Rest.
- Reklamationsvolumen (Rechnung-Netto unter Prüfung, `ZNRKT_REKL.REK_NETWR`, je Jahr):
  2019 **1,22 Mrd €**, 2020 552 Mio, 2021 823 Mio, 2022 700 Mio, 2023 729 Mio,
  2024 672 Mio, 2025 731 Mio, 2026 (ytd) 295 Mio.
- Workflow-Phasen (`RKT_PHASE`): `RKZ` (Rechnungskürzung/formale Prüfung) → `MDK`
  (medizinische Prüfung). Stände (`REKL_STAND`, denormalisierter Klartext, ~30 Stufen):
  „Beginn Reklamationsvorgang" → „Übergabe an Med. Co." → „Prüfung durch Med. Co." →
  „Berichte angefordert (MDK)" → „Unterlagen an Kasse / MDK" → „Med. Co. Prüfung beendet"
  → „Eingang LE (positiv/negativ)" [Leistungsentscheid] → „Rechnungskorrektur" →
  „Aufwandspauschale berechnet" → „Vorgang erledigt".

**Datenschutz:** `ZNRKT_KOPF`/`_REKL` enthalten personenidentifizierende Freitext-/
Namensfelder (`ARZT_MDK`, `RKT_STWRT_TXT`, `MAHNSP`, `*_BEM`, Sachbearbeiter-Kürzel).
Diese unterliegen der Verkryptungsregel (Analyse_Datenbank.md §4) — in Auswertungen nie
im Klartext. Fall-/Kostenträger-IDs sind Pseudonym-IDs (roh zulässig, in FHIR-Ausleitung
über `privacy.py`).

---

## 4. Warum eine eigene Anwendung? (Lücke heute)

- **DIAS = retrospektiv, nicht steuernd.** Der Cube wertet abgeschlossene Vorgänge aus;
  er unterstützt nicht die *laufende* Fristensteuerung (§275c: 4-/8-Wochen-Fristen,
  Quartalsbezug, Aufwandspauschale-Automatik).
- **i.s.h.med RKT = Erfassung, keine Analytik/kein Frühwarnsystem.** Kein modernes
  Dashboard, keine Erfolgsquoten-Prognose, kein Kodier-Feedback-Loop.
- **Erlösrelevanz ist hoch** (dreistelliger Mio-€-Streitwert p.a.) → jede
  Prozentverbesserung der Erfolgs-/Fristenquote ist unmittelbar erlöswirksam.

**Zielbild MD-Management-App (Vorschlag):**
1. **Fristen-Cockpit** (§275c): offene Vorgänge nach Restfrist, Eskalation, Wiedervorlage.
2. **Erlössicherungs-Analytik:** Streitwert-Pipeline, Erfolgsquote (akzeptiert/abgelehnt/
   Vergleich), CW-/Erlösdifferenz ISH↔MD↔Ergebnis je DRG/Abteilung/Kasse/Prüfgrund.
3. **Kodier-Feedback-Loop:** Welche ICD/OPS/DRG werden systematisch beanstandet? →
   Rückkopplung an Kodierung/Fachabteilungen (Prävention statt Reaktion).
4. **Kassen-/MD-Benchmarking:** Prüfquote & Erfolg je Kasse, Aufwandspauschalen-Bilanz.
5. (Optional) **FHIR-Anschluss:** RKT-Vorgang als `ClaimResponse`/`Task`-Ressource für
   MII/Sekundärnutzung — nur wenn gewünscht, medizinisch vs. abrechnung sauber getrennt.

---

## 5. Architektur-Optionen (zu entscheiden)

Die App kann auf der **bestehenden sapfhir-Bronze-Schicht** aufsetzen (RKT-Tabellen via
Backfill/CDC → `bronze_current` → Gold-Mart `md_management` → maskierte `mcp.*`-Sicht),
konsistent mit dem Analytik-Pfad (`fhir: null`, Tier 2/3) aus CONCEPT §… Damit wäre die
MD-App ein weiterer Gold-Mart + Dashboard-Tab, kein Fremdkörper.

**Offene Entscheidungen (Scope):**
- **A) Zweck:** reines Analytik-/Reporting-Dashboard (read-only) — ODER operatives
  Steuerungstool mit Fristen-Workflow (Wiedervorlagen, Aufgaben) — ODER beides gestuft.
- **B) Verortung:** Modul im bestehenden sapfhir-Repo/Dashboard — ODER eigenständige App.
- **C) Datenstand:** Live-Analytik nur über `__ct`-Echtzeitstrang — ODER historisiert
  (SCD2) für Verlaufsauswertung (Fristenhistorie, Standwechsel).
- **D) FHIR:** MD-Vorgänge als FHIR-Ressourcen ausleiten (ja/nein/später).

---

## 6. Nächste Schritte (nach Scope-Freigabe)
1. Voller Dreiklang der restlichen 11 `ZNRKT_*`-Tabellen (PK-Uniqueness + Fill-Audit),
   insb. Katalog `ZNRKT_KG(_TXT)` (Prüfgründe) und `ZNRKT_DRG`-Sichtenlogik.
2. Prüfgrund-/Phasen-/Stand-Kataloge kuratieren (REKL_GRUND, RKT_PHASE, REKL_STAND,
   RKTTYP) — teils denormalisiert als Klartext vorhanden, teils Code → Katalog.
3. Gold-Mart-Modell `md_management` entwerfen (Vorgang-Faktentabelle + Streit-Dimensionen).
4. Dashboard-/App-Prototyp gemäß gewähltem Scope.
