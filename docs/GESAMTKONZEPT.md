# GESAMTKONZEPT — CliniBots Klinikdaten-Suite
## CliniBots Patient Insight (CPI) + CliniBots MDM — ein Plan, zwei Produkte

**Stand:** 20.07.2026 · **Rolle: OBERSTES LEITDOKUMENT** (siehe `INDEX.md`).
Use-Case-getrieben neu aufgebaut: Deep-Research (11 verifizierte Befunde, Primärquellen
§275c/KHSFV/GKV-SV/PubMed) **+ hausintern live gemessene Zahlen** (R17–R19 gegen die
Replika) → Use-Case-Katalog → Capabilities → Module → Gesamtplan.
Fachliche Tiefe bleibt in den Unterkonzepten: Zielbild (`CONCEPT_P360_VOLLAUSBAU.md`),
Architektur (`CONCEPT.md`), MDM-Domäne (`MD_MANAGEMENT_KONZEPT.md`), Zugriff
(`BERECHTIGUNGSKONZEPT.md`), Daten (`PATIENT_DATENKATALOG.md`), Plan (`ROADMAP.md`).

---

## 1. Die Suite in einem Bild

```
                    ┌──────────── CliniBots Klinikdaten-Suite ────────────┐
                    │                                                      │
  IS-H/i.s.h.med    │  GEMEINSAME PLATTFORM (ein Fundament)                │
  MSSQL-Replika ────┼─▶ Datenpumpe (read-only, Backfill+CDC) ─▶ Bronze     │
  (read-only,       │   Privacy (Pseudonym/Shift/Hash) · FHIR-NDJSON       │
   977 Tabellen,    │   Gold-Marts (DuckDB) · mcp.*-Maskierung             │
   77 patienten-    │   Authz (AD→PERNR→KOSTL→SETNODE ⇄ NOEK→NBEW)         │
   bezogen)         │   Audit-Hash-Kette · CliniBots-Design · No-Admin     │
                    │        │                          │                  │
                    │  ┌─────▼──────────┐   ┌───────────▼───────────┐      │
                    │  │ CPI            │   │ CPI MDM               │      │
                    │  │ Patient 360    │◀─▶│ MD-/Prüfverfahren     │      │
                    │  │ Klinik-Analytik│   │ Fristen-Cockpit       │      │
                    │  │ Kohorten/DIZ   │   │ Erlössicherung        │      │
                    │  │ MCP/KI-Zugang  │   │ Kodier-Feedback       │      │
                    │  └────────────────┘   └───────────────────────┘      │
                    │   Verbund: MD-Badge am Fall ⇄ Fall-Akte;             │
                    │   Kodier-Feedback MDM→CPI; eine Authz; ein Login     │
                    └──────────────────────────────────────────────────────┘
```

**Positionierung:** die einzige uns bekannte Kombination aus *FHIR-nativer
Sekundärnutzung* **und** *operativem Medizincontrolling* in **einem on-prem Stack ohne
Cloud/Egress** — KHZG-konform per Bauart (§19 Abs. 2 KHSFV schreibt FHIR/IHE vor, wo
kein MIO existiert; verifiziert). Wettbewerber (TIP HCe, Tiplu MOMO, ORBIS BI …) sind
BI-zentriert; deren FHIR-Fähigkeit ist eine offene Recherchefrage (→ §8 N4).

---

## 2. Personas

| Persona | Produkt-Schwerpunkt | Kernfrage |
|---|---|---|
| **MD-Manager/in, Medizincontrolling** | MDM | „Welche Verfahren laufen, welche Fristen drohen, was ist der Streitwert?" |
| **Kodierfachkraft / DRG-Beauftragte** | MDM→CPI | „Was wird systematisch beanstandet — und wie verhindern wir es beim nächsten Fall?" |
| **Stations-/Klinikarzt, Pflege** | CPI | „Was ist die Geschichte dieses Patienten?" (nur eigene OE — Berechtigungsregel) |
| **ZNA-/Betten-/OP-Koordination** | CPI | „Wo stauen sich Patienten, wo ist Kapazität?" |
| **Forschung / DIZ / Study Nurse** | CPI | „Wie viele Patienten erfüllen die Kriterien — und wer davon liegt gerade hier?" |
| **Geschäftsführung / QM** | beide | „CMI, Erlöse, Prüfquote, Benchmarks — auf einen Blick, drillbar bis zum Fall." |
| **IT / Datenschutz** | Plattform | „Read-only? Maskiert? Auditierbar? Wer sieht wen?" |

---

## 3. Use-Case-Katalog (Evidenz-klassifiziert)

Legende Evidenz: **[A]** extern verifiziert (Primärquelle) · **[B]** hausintern live
gemessen (R17–R19, Replika) · **[C]** Hypothese/Nachrecherche (§8). Status: ✅ umgesetzt
· 🔶 teilweise · ⬜ offen (AP = Arbeitspaket in ROADMAP/MDM).

### 3.1 Medizincontrolling (Produkt: CPI MDM)

**UC-M1 — Prüfquoten-Steuerung nach §275c [A] 🔶**
Die zulässige MD-Prüfquote ist quartalsweise gestaffelt (5/10/15 % je nach Anteil
unbeanstandeter Rechnungen im vorvergangenen Quartal; Sanktion erst <60 %; **ab
1.1.2027 verschärft: 5/15/25 % bei Schwellen 80/60 %**). Gute Abrechnungsqualität senkt
die Prüflast *mechanisch* — das ist der zentrale Business-Hebel des MDM.
→ Capability: Quartals-Cockpit „eigene Quote & Abstand zur nächsten Staffelschwelle",
Simulation 2025- vs. 2027-Regime. *(neu: AP-M1)*

**UC-M2 — Verfahrensführung & Fristen-Cockpit [B] ✅**
Hausintern: **229.047 Fälle mit MD-Verfahren, 1,34 Mio Reklamationszeilen**, ~30
Workflow-Stände, Ø ~110 Tage Durchlauf. Umgesetzt: Fristen-Ampel, Arbeitskorb
(944k Aufgaben, 97 Typen), Aging/Eskalation, Fall-Akte mit SCD2-Verlauf.

**UC-M3 — Erlössicherung & Widerspruch [B] ✅**
Hausintern: Netto-Entgeltdifferenz ISH→Ergebnis **~50,2 Mio €** (Brutto-Minderung
77,7 Mio), Rechnungsvolumen unter Prüfung 0,3–1,2 Mrd €/Jahr. Umgesetzt:
Erlös-Tab (Diff je Fachabteilung/Kasse/DRG), Kassen-Benchmark, Klageweg-Daten (ZNRKT_KLA).

**UC-M4 — Aufwandspauschalen-Bilanz [A+B] ✅**
300 €/bestätigter Prüfung (gesetzlich; hausintern 42.884 Pauschalen-Erledigungen ≈
**12,9 Mio € Einnahmen**); seit KHVVG 12/2024 zudem 400-€-Aufschlag je beanstandetem
Fall bei Güte <60 % (Risiko-Seite). Beide Größen im MDM sichtbar.

**UC-M5 — Downcoding-Prävention / Kodier-Feedback-Loop [B] 🔶**
Hausintern: **ICD-Änderungsquote ISH≠Ergebnis 43,4 %**, DRG 29,8 % — je Kode und
Fachabteilung messbar (6-Sichten-Tabellen). Umgesetzt: Downcoding-Analytik im MDM.
→ Fehlend: der **Loop zurück** in die klinische Welt (CPI-Fall-Akte zeigt „bei dieser
Konstellation wurde zuletzt X beanstandet"). *(AP: ROADMAP P4.3)*

**UC-M6 — Prüfquoten-Benchmarking gegen alle deutschen Häuser [A] ⬜**
GKV-SV publiziert **maschinenlesbare Standort-Statistiken (CSV/XLSX, Q1/2020–Q1/2026)**
nach §275c Abs. 4 — kostenlose Benchmarking-Datenquelle (ein Monitoring-Skill für genau
diese Quelle existiert bereits im Haus). → MDM-Benchmark-Kachel „wir vs. Bund/Land/
Größenklasse". *(neu: AP-M6 — zugleich Produkt-Demonstrator, §8 N1)*

### 3.2 Klinische Steuerung & Versorgung (Produkt: CPI)

**UC-K1 — Patient 360 am Arbeitsplatz [B] 🔶**
77 patientenbezogene Tabellen, 16 gemappte FHIR-Ressourcentypen; Akte zeigt heute nur
4–5. → Vollausbau nach Zielbild (alle Sektionen, Timeline, Verlegungskette,
Facettensuche, IPS-Export). *(ROADMAP P1/P2)* — Zugriff nach Behandlungsbezug
(Berechtigungskette live verifiziert).

**UC-K2 — ZNA-Steuerung [A] ⬜**
Peer-reviewed: Steuerung ambulanter ED-Fälle in Notfallpraxis senkte ambulante
ZNA-Fälle am UKE um **−37,3 %** (851→537/Monat); Augsburger Routinedaten (42.391 Fälle):
**~76 % Triage-Stufen 3–5** = quantifiziertes Steuerungspotenzial. Hausdaten vorhanden
(ZNAA-OE 820k Bewegungen, NDOC_ZNA 1,28 Mio Dokumente). *(ROADMAP P3.3)*

**UC-K3 — Entlassmanagement-Transparenz [A] ⬜ — Nutzenversprechen bewusst eng**
Evidenz differenziert: Implementierung günstig (Ø 43 €/Patient, TU München), aber
**VWD-Effekt in der besten Studie NICHT belegt** → wir versprechen keine
Verweildauersenkung, sondern schließen die dokumentierte **Mess-Lücke**: KPI
„>75 % der VWD-Überschreiter wurden erst >48 h nach Aufnahme gemeldet" ist direkt
operationalisierbar (48h-Melde-Frist als Dashboard-KPI). *(neu: AP-K3, P4)*

**UC-K4 — Belegung/Betten, OP-Auslastung, Wiederaufnahmen [B intern, C extern] ⬜**
Publizierte Effekte blieben unverifiziert (§8 N3) — wir bauen sie als *interne*
Steuerungssichten (Daten: NBEW 28 Mio, NICP-OP-Zeiten, WIEDERAUFNAHME-Graphkante),
ohne externe Effektversprechen. *(ROADMAP P4.2)*

### 3.3 Forschung & DIZ (Produkt: CPI)

**UC-F1 — Machbarkeitsanfragen / Feasibility [A] ⬜**
Das MII/FDPG-Muster ist national validiert (verteilte Anfragen über **33 Unikliniken**,
CQL + FHIR Search, nur aggregierte Zählwerte). CPI repliziert das Muster **on-prem auf
Hausebene** (Kohorten-Builder mit Live-Count) und macht das Haus FDPG-anschlussfähig.
*(ROADMAP P5.1/P5.2)*

**UC-F2 — Studienrekrutierungs-Screening [A] ⬜**
FHIR-R4-Screening erreichte an der LMU **~95 % Sensitivität** (52/55 Patienten, 4
DZHK-Studien); **10 MIRACUM-Unikliniken** haben Rekrutierungsunterstützung auf
Routinedaten ausgerollt. → Kohorte + „liegt aktuell hier"-Filter (offene Bewegung).
*(P5.1 + Stationsboard-Join)*

**UC-F3 — MII-KDS-Anschlussfähigkeit [A] ⬜**
6 Basismodule (Person/Fall/Diagnose/Prozedur/Labor/Medikation) sind mit unserem
Bestand abbildbar (UMM-Referenz belegt IS-H-Machbarkeit); Fall = 3-Ebenen-Encounter =
NFAL/NBEW. → Profil-Layer `meta.profile`. *(P5.3; Medikation via COPRA P3.1)*

### 3.4 Querschnitt (beide Produkte)

**UC-Q1 — Zugriff nach Behandlungsbezug [B] 🔶** — Berechtigungskette live verifiziert
(PA0105/90AD→PERNR→KOSTL→SETNODE ⇄ NOEK→NBEW); `authz`-Modul + P360-Gate umgesetzt;
fehlt: Login-Fluss + Materialisierung im Nightly. *(ROADMAP Q4)*
**UC-Q2 — KI-/MCP-Zugang [B] 🔶** — 9 gehärtete MCP-Tools (Sandbox, Audit-Kette); FHIR-Tools laufen im Default-Ladeweg leer (FHIR-Export übersprungen, G6).
**UC-Q3 — KHZG-/Interop-Konformität [A] ✅ (per Bauart)** — FHIR-Profile/IHE explizit
in §19 Abs. 2 KHSFV; Caveat: Antragsfristen vorbei, Argument = Umsetzungspflicht/Sanktion.
**UC-Q4 — QM / Pflegecontrolling / GF-Reporting [C] ⬜** — plausibel, extern unbelegt
(§8 N2/N3); als Hypothesen-Backlog geführt, nicht versprochen.

---

## 4. Capability-Map (UC → Fähigkeit → Modul)

| Capability | UCs | Modul | Status |
|---|---|---|---|
| Datenpumpe read-only (Backfill+CDC, Lastfenster) | alle | Plattform | 🔶 Backfill/Kohorte live; CDC nur als CLI, nicht im Ladeweg (G7) |
| Privacy/Pseudonymisierung + Verkryptung | alle | Plattform | ✅ |
| FHIR-NDJSON 16→22 Ressourcentypen | K1,F1–F3 | Plattform | 🔶 |
| Authz-Kette + Row-Level + Audit | Q1 | Plattform | 🔶 |
| Facettensuche + Drilldown-Kontrakt | K1,M5,alle Dashboards | CPI | ⬜ P1 |
| P360-Akte voll (Timeline, Verlegungskette, IPS) | K1 | CPI | ⬜ P1/P2 |
| COPRA-Medikation/Vitalwerte | K1,F3 | Plattform | ⬜ P3.1 |
| Stationsboard/ZNA/OP-Sichten | K2,K4,F2 | CPI | ⬜ P3.3 |
| MC-Dashboards (CMI/Erlös/GVD/Heatmap) + Drillthrough | K4,GF | CPI | ⬜ P4 |
| Kohorten-Builder + Charakterisierung + NL→Kohorte | F1,F2 | CPI | ⬜ P5 |
| MII/ISiK-Profil-Layer + IPS | F3,Q3 | CPI | ⬜ P5.3/5.4 |
| Verfahrens-Workflow/Fristen/Arbeitskorb | M2 | MDM | ✅ |
| Erlös-/Kassen-/Downcoding-Analytik | M3–M5 | MDM | ✅ |
| §275c-Quoten-Cockpit + 2027-Simulation | M1 | MDM | ⬜ AP-M1 |
| GKV-SV-Benchmark-Import | M6 | MDM | ⬜ AP-M6 |
| Kodier-Feedback-Loop MDM→CPI | M5 | Verbund | ⬜ P4.3 |
| MD-Badge/Deep-Link CPI⇄MDM | M2,K1 | Verbund | ⬜ P2.5 |
| Entlass-48h-KPI | K3 | CPI | ⬜ AP-K3 |

---

## 5. Verzahnung der Produkte (der Suite-Mehrwert)

1. **Eine Datenbasis:** beide lesen dieselbe Replika read-only; MDM nutzt die
   ZNRKT-Familie, CPI den klinischen Kern — gemeinsame Schlüssel (FALNR/PATNR/OE).
2. **Ein Berechtigungsmodell:** dieselbe Kette (AD→…→NBEW) gilt für beide; MDM-Rollen
   (Medizincontrolling) sind Vollrollen der Plattform.
3. **Der Fall als Scharnier:** CPI-Fall-Akte zeigt MD-Badge ⚖ → MDM-Verfahrensakte;
   MDM-Fall verlinkt zurück in die klinische 360°-Akte (Kontext fürs Gutachten).
4. **Der Loop:** MDM-Erkenntnis (beanstandete Kodes je Konstellation) wird CPI-Hinweis
   in Kodier-/Fallkontext — Prävention statt Reaktion. **Das kann kein getrenntes
   BI-Tool**, weil es Fall-Ebene + Verfahrens-Ebene in einem Modell braucht.
5. **Ein Betrieb:** gleiches Deployment-Muster (No-Admin, ops.ps1, Nightly), gleiches
   Design-System, gleiche Audit-Philosophie (Hash-Ketten).

---

## 6. Nutzenrechnung (konservativ, mit Regime-Wechsel 2027)

Für ein Haus dieser Größe (hausintern gemessen):
- **Verteidigtes Volumen:** 0,3–1,2 Mrd €/Jahr Rechnungsvolumen unter Prüfung; jede
  Prozentpunkt-Verbesserung der Erfolgsquote ≈ einstelliger Mio-Betrag (bei 77,7 Mio
  Brutto-Minderung über die Historie).
- **Aufwandspauschalen:** 300 €/gewonnene Prüfung sind direkt kassenwirksam (belegt:
  12,9 Mio € kumuliert); Fristen-/Unterlagen-Versäumnisse kosten genau diese Position.
- **Prüfquoten-Mechanik:** Güte ≥60 % (ab 2027: ≥80 %!) senkt die Quote der *nächsten*
  Quartale mechanisch → weniger Verfahren → weniger Personalbindung. Das 2027-Regime
  (5/15/25 %) macht das Quoten-Cockpit (AP-M1) zur Pflicht, nicht zur Kür.
- **Forschung:** Feasibility/Rekrutierung heute manuell je Anfrage; FDPG-/MIRACUM-Muster
  zeigen den Self-Service-Weg (Zahlen zur Ersparnis: Nachrecherche §8 N2).
- **Nicht versprochen** (Evidenz fehlt): VWD-Senkung durch Entlassmanagement,
  Personal-Einsparquoten im MD-Management, OP-/Belegungseffekte.

---

## 7. Gesamtplan (Meilensteine über beide Produkte)

| Meilenstein | Inhalt | Quelle |
|---|---|---|
| **M0 „Live-Daten"** | Q1 Live-Backfill + Nightly + Authz-Materialisierung (Q4) | ROADMAP Q |
| **M1 „Akte komplett"** | CPI P1+P2 (Sichtbarkeit, Suche, Drilldown, Timeline, Fall-Detail mit MD-Badge→MDM) | ROADMAP P1/P2 |
| **M2 „MDM 2027-ready"** | AP-M1 Quoten-Cockpit + Simulation; AP-M6 GKV-SV-Benchmark; Kodier-Loop (P4.3) | MDM-Repo + ROADMAP |
| **M3 „Steuern"** | CPI P3+P4 (COPRA, ZNA/Stationsboard, MC-Dashboards, AP-K3 Entlass-KPI) | ROADMAP P3/P4 |
| **M4 „Forschen & Standards"** | CPI P5 (Kohorten, MII/ISiK-Profile, IPS) → DIZ-/FDPG-Anschluss | ROADMAP P5 |
| **M5 „Vertrauen"** | P6 (Login/TOTP, Dok-Intelligence, Graph, SCD2/CDPOS) | ROADMAP P6 |
| **N „Nachrecherchen"** | §8 N1–N4 (parallel, N1 als Demonstrator priorisiert) | hier |

Reihenfolge-Logik: M0 entsperrt echte Zahlen für alles; M1 ist der sichtbarste
Nutzer-Mehrwert; M2 hat eine **harte externe Deadline (1.1.2027)**.

## 8. Offene Fragen / Nachrecherchen (aus der Verifikation)
- **N1** Erlösverluste je geprüftem Fall + MD-Erfolgsquoten je Kassenart: **aus den
  GKV-SV-CSVs selbst auswerten** (Rohdaten liegen offen; zugleich MDM-Demonstrator).
- **N2** Personalaufwand MD-Management (VK/1.000 Fälle), Fristenversäumnis-Anteile —
  DGfM/FoKA-Erhebungen suchen; ggf. eigene Messung aus ZNRKT_AUF-Durchlaufzeiten.
- **N3** Publizierte Effekte Belegungs-/OP-Steuerung, Wiederaufnahme-Vermeidung, QM/
  Pflegecontrolling (PPR 2.0/Pflegebudget) — eigene Recherche-Runde.
- **N4** Wettbewerbs-Funktionsvergleich (TIP HCe, Tiplu MOMO, ORBIS BI, MetaKIS,
  LOGEX): FHIR-Fähigkeit + On-prem + MDM-Integration — eigene Recherche-Runde.

## 9. Quellen (verifizierte Kernbelege dieser Runde)
§275c-Mechanik/Staffel/Pauschalen: gesetze-im-internet.de/sgb_5/__275c.html;
gkv-spitzenverband.de (Prüfquoten-Statistik + Erklär-PDF 2024); md-bund.de. ·
KHVVG-Änderungen (400 €, 2027-Staffel): ebd. · ZNA: UKE-Studie (−37,3 %,
PMC/peer-reviewed); LMU-Diss. Augsburg (42.391 Fälle, MTS-Verteilung). ·
Entlassmanagement: TU-München-Kostenstudie (43 €/Pat., VWD-Nulleffekt); DKI-Studie 2008
(0,7 T., Einzelhaus). · Forschung: FDPG/MII (33 Standorte, CQL/FHIR); LMU-Kardiologie
(95 % Sensitivität); MIRACUM (10 Standorte). · KHZG: §19 Abs. 2 KHSFV (FHIR/IHE).
Hausinterne Zahlen: R17–R19-Verifikation gegen `higl-main` (VERIFY_LOG, MDM-VALIDIERUNG).
