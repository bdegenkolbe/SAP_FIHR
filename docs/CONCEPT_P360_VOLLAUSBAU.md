# CliniBots Patient Insight 2.0 — Zielbild „Echte 360°" (Vollausbau)

**Stand:** 20.07.2026 · Ergebnis aus Deep-Research (24 verifizierte Befunde, 24 Quellen,
adversarial geprüft) + internem Konzept-vs.-Ist-Delta-Review. Bewusst **target-first**
entworfen — was die Plattform sein soll, unabhängig davon, was heute gebaut ist.
Der Abgleich mit dem Ist folgt in §8 (Roadmap).

**Diagnose in einem Satz:** Die Pipeline erzeugt bereits 16 FHIR-Ressourcentypen aus
21 Tabellen — aber nur 4–5 erreichen die Oberfläche, es gibt keine Suche vor der Akte,
keinen Kohorten-Pfad, und 37 patientenbezogene Tabellen (u. a. Medikation via COPRA,
84 Mio Erlöszeilen, ZNA-Dokumente) liegen brach. Das Zielbild schließt das.

---

## 1. Leitidee: Eine Plattform, drei Blickwinkel, ein Drilldown-Kontrakt

Die Forschung zeigt: Einzelpatienten-Sicht und Kohorten-/Populationssicht sind **zwei
verschiedene Visualisierungsdisziplinen** (seit ~2010 getrennte Forschungsstränge,
JAMIA-Review PMC4394966). Eine „coole" Plattform trennt sie sauber und verbindet sie
über einen einzigen, überall gleichen Mechanismus:

> **Der Drilldown-Kontrakt:** *Jede* Zahl, *jeder* Balken, *jedes* Kachel-KPI in
> *jedem* Dashboard ist klickbar und führt über genau drei Stufen:
> **Aggregat → Fallliste → Fall-Akte → Patient 360.**
> Rückweg über Breadcrumbs; Zustand in der URL (teilbare Links); die letzte Stufe
> (Patient) läuft durch das Berechtigungs-Gate (deny-by-default, `authz`).

Drei Blickwinkel auf dieselben Gold-Daten:
| Lens | Nutzer | Startpunkt |
|---|---|---|
| **Steuern** (Medizincontrolling) | MC, Verwaltung | KPI-Dashboards (§5) |
| **Verstehen** (Klinik) | Ärzte, Pflege, QM | Suche/Station → Patient 360 (§3/§4) |
| **Forschen** (DIZ/Studien) | Forschung | Kohorten-Builder (§6) |

---

## 2. FHIR-Ressourcen-Vollmodell (das „Was")

### 2.1 Normativer Rahmen (verifiziert)
- **MII-Kerndatensatz** (FHIR R4 seit 04/2019, konsortienübergreifend): **6 Basismodule**
  — Person, **Fall**, Diagnose, Prozedur, Laborbefund, Medikation — plus Erweiterungs-
  module (Onkologie, Intensiv, Biobank, Mikrobiologie, Bildgebung, Symptom/Phänotyp,
  Strukturdaten …). [Bundesgesundheitsblatt 2024; medizininformatik-initiative.de]
- **MII KDS Modul Fall V2025**: Encounter auf **drei Kontaktebenen** —
  Einrichtungskontakt / Abteilungskontakt / Versorgungsstellenkontakt, verkettet über
  `Encounter.partOf`; der Encounter ist die **zentrale Verknüpfungsressource** (Condition/
  Procedure/Medication/Labor referenzieren ihn). → **Exakt unsere NFAL/NBEW-Struktur!**
- **ISiK Stufe 3** (gesetzlich, §373 SGB V; verbindlich seit 01.07.2025): Module Basis,
  Dokumentenaustausch, **Medikation**, **Terminplanung**, **Vitalparameter und
  Körpermaße**, Sicherheit. (Stufe 4 eingestellt.) [gematik Fachportal]
- **IPS / International Patient Summary** (EN 17269/ISO 27269): FHIR-Document
  (Composition + Sektions-Narrative) als standardisierte Kurzakte; HAPI FHIR generiert
  sie on-prem automatisch via `$summary`. [hapifhir.io]
- **Referenzbeweis IS-H→FHIR**: Das DIZ der UMM (Heidelberg/Mannheim) hat seinen
  kompletten SAP-i.s.h.-Bestand (Demografie, Fall inkl. Verlegungskette/Fachabteilungen/
  Beatmung, Diagnosen, Prozeduren) vollständig FHIR-harmonisiert — unser Ansatz ist
  Standardpraxis an Unikliniken. [UMM-DIZ-Datenkatalog]

### 2.2 Ziel-Ressourcenkatalog (vollständig, mit Quelltabellen)

**Stufe A — Kern (MII-Basismodule; heute schon gemappt, muss sichtbar werden):**
| FHIR | Quelle | MII-Modul | UI-Sektion |
|---|---|---|---|
| Patient (+link) | NPAT, NPAE, **NPIX** (MPI) | Person | Kopfleiste |
| Encounter ×3 Ebenen | NFAL (Einrichtung) → NBEW/ORGFA (Abteilung) → NBEW Station/Zimmer (Versorgungsstelle), `partOf` | Fall | Fälle & Verlegungskette |
| Condition | NDIA (+NKDI), **N2OPDIAGNOSEN** (OP-Diagnosen) | Diagnose | Diagnosen |
| Procedure (+OP-Team) | NICP (+N1LSTEAM) | Prozedur | Prozeduren/OPs |
| Observation (laboratory) + DiagnosticReport | N2LABOR/001 | Laborbefund | Labor-Verläufe |
| MedicationRequest/Statement | **ZCOPRA_01 + ZISH_COPRA_FALNR** (COPRA; N1MEORDER ist leer!) | Medikation | Medikation |

**Stufe B — Versorgungskontext (ISiK-3-relevant; teils gemappt, teils neu):**
| FHIR | Quelle | UI-Sektion |
|---|---|---|
| Appointment | NAPP + **NTMN** (11,5 Mio; Registry deklariert, Mapper fehlt) | Termine |
| DocumentReference | NDOC + **NDOC_ZNA** + **NDOCSTORNO** (status entered-in-error) + N2TEXT-Volltext | Dokumente |
| Observation (vital-signs) | COPRA-Schiene + NGEB (Perinatal) | Vitalwerte |
| AllergyIntolerance / Flag | NRSF | Risiken & Allergien |
| Coverage | NKSK (+NVVP hash) | Versicherung |
| ServiceRequest | N1CORDER (+N1ANF) | Aufträge/Anforderungen |
| Location / Organization / Practitioner | NBAU/NORG/TN01/NGPA+NPER | überall verlinkt |
| Encounter (ambulant) / Mitbehandlung | NAMB, NMBG | Fälle-Sektion |

**Stufe C — Abrechnung & Steuerung (Analytik-Pfad, im UI als eigene Sektion):**
| FHIR/Analytik | Quelle | UI |
|---|---|---|
| Account (+Zusammenführung) | NAPX(+_FAL) | Fall-Klammer |
| DRG/Erlös (fhir:null-Mart) | NDRG, **NLEI/NLKZ/NLLZ** (294 Mio), TNDRG (LBFW) | Erlös je Fall; CMI-Drill |
| MD-Verfahren | ZNRKT_* → **Deep-Link zu CliniBots MDM** (Fall-Akte dort) | „MD-Prüfung"-Badge am Fall |
| ChargeItem/Claim (später) | NLEI-Familie | — |

**Stufe D — Forschung & Governance:**
| FHIR | Quelle | UI |
|---|---|---|
| ResearchSubject/Studie | /UKL/PAT_STUDIE, /UKU/3CT*, ZBIO_T201/202 (Biobank) | Forschungs-Sektion |
| Consent | (Quelle klären; MII-Einordnung derzeit uneindeutig — Caveat der Recherche) | Governance |
| Provenance | je Ausleitungslauf (CONCEPT §16.3) | Meta/Trust-Badge |
| Task | N2DWSWL_TASK (Worklist), ZNRKT_AUF | Arbeitslisten |

**Prinzip Verlustfreiheit bleibt:** unbekannte Kodes als `urn:ish:*`-Rohcode, nie raten.

---

## 3. Patient 360 — die Akte (das Herzstück)

### 3.1 Aufbau (IPS-Muster + Timeline-Dominanz)
Forschungsbefund: **Timeline-/Temporaldarstellung dominiert** die Einzelpatienten-Sicht
(15/18 Studien; LifeLines-Linie als Kanon). Und: führende Aggregatoren bieten **zwei
Abrufmuster** — Dokumentenindex zum Stöbern und die normalisierte Longitudinalakte in
einem Zug (Health-Gorilla-$p360-Muster). Beides übernehmen wir:

```
┌────────────────────────────────────────────────────────────────────────┐
│ KOPF (immer sichtbar): Pseudonym-ID · Alter/Geschlecht · ⚑Risiken      │
│  aktueller Status (stationär auf <Station>?) · Kennzahlen · IPS-Export │
├──────────────┬─────────────────────────────────────────────────────────┤
│ NAVIGATION   │  A) SUMMARY („Kurzakte", IPS-Sektionen, 1 Screen)       │
│  Summary     │  B) TIMELINE (interaktiv, LifeLines-Stil):              │
│  Timeline    │     Swimlanes je Domäne (Fälle▬, Bewegungen▪, Diagnosen│
│  Fälle       │     ◆, OPs⬟, Labor∿, Medikation━, Doku▤, Termine○, MD-  │
│  Diagnosen   │     Verfahren⚖) · Zoom/Brush · Domänen-Toggle · Klick   │
│  Prozeduren  │     auf Element → Detail-Panel → ggf. Fall-Kontext      │
│  Labor       │  C) SEKTIONEN (je Ressource eine Karte, §2-Katalog):    │
│  Medikation  │     leere Sektionen zeigen „keine Daten (Quelle: X)" —  │
│  Vitalwerte  │     ehrlich statt unsichtbar                            │
│  Dokumente   │  D) FALL-DETAIL: 3-Ebenen-Encounter (Einrichtung→       │
│  Termine     │     Abteilung→Station) als Verlegungsketten-Grafik,     │
│  Risiken     │     DRG/Erlös, MD-Prüfstatus (→MDM), Doku des Falls     │
│  Versicherung│                                                        │
│  Abrechnung  │                                                        │
│  Forschung   │                                                        │
└──────────────┴─────────────────────────────────────────────────────────┘
```

### 3.2 Konkrete Interaktionen
- **Labor:** je Analyt Sparkline mit Referenzband (heute schon da) + „alle Werte"-Tabelle,
  Abnormal-Filter, LOINC-Badge; Klick auf Punkt → DiagnosticReport-Kontext.
- **Medikation (neu, COPRA):** Verordnungs-Gantt (Wirkstoff-Zeilen, Zeitbalken je
  Verordnung), Filter aktiv/beendet.
- **Verlegungskette (neu):** horizontale Kette Einrichtungskontakt→Abteilungskontakte→
  Stationskontakte (MII-3-Ebenen), Dauer je Segment, Klick → Bewegungsdetail.
- **Dokumente:** Index zuerst (Bundle-of-DocumentReference-Muster), Volltext-Preview via
  FTS (N2TEXT), ZNA-Dokumente als eigener Filter; stornierte sichtbar ausgegraut.
- **IPS-Export:** Button „Kurzakte (IPS)" erzeugt das Composition-Dokument aus den
  vorhandenen NDJSON-Ressourcen (eigener kleiner Generator; optional später HAPI-
  `$summary`-Sidecar, §7).
- **MD-Verfahren-Badge:** Fälle mit ZNRKT-Vorgang tragen ⚖-Badge → Deep-Link in die
  CliniBots-MDM-Fall-Akte (Produkt-Verbund).

### 3.3 Der Weg ZUR Akte: Suche & Facetten (größte heutige UX-Lücke)
Vor der Akte steht eine **Facettensuche** (i2b2-Erkenntnis: iterative Kriterien mit
Live-Trefferzahl): Suchfeld (PATNR/FALNR/Name-Hash) + Facetten Alter/Geschlecht/
Fachabteilung/ICD/OPS/Laborwert-Bereich/Zeitraum/Fallart → Trefferliste (maskiert,
`n<5`-Schutz) → Akte. Jede Facettenkombination ist speicherbar → wird Kohorte (§6).

---

## 4. Stations-/Klinik-Sicht (der mittlere Blick)
Zwischen Haus-Dashboard und Einzelakte fehlt heute die **operative Mittelebene**:
- **Stationsboard:** aktuelle Belegung je Station (aus offenen NBEW), Zeile je Patient:
  Liegedauer, Fachabteilung, letzte Labor-Auffälligkeit, geplante Termine, MD-⚖.
  Klick → Akte. (Deny-by-default: nur eigene OE via `authz`.)
- **ZNA-Sicht:** NDOC_ZNA + ZNAA-Bewegungen: Zugänge heute/Woche, Verweildauer in ZNA,
  Weiterverlegungsziele — Drill bis Fall.
- **OP-Sicht:** NICP mit BZTOP/EZTOP + N1LSTEAM: OP-Zahlen je Tag/Saal/Team, Schnitt-Naht-
  Zeiten — Drill bis Fall/Akte.

---

## 5. Medizincontrolling-Dashboards (Steuern) — KPI-Set mit Fall-Drillthrough
Referenzrahmen: deutsches DRG-Berichtswesen-Konsenspapier + marktübliche MC-Cockpits
(TIP HCe „MCO-Cockpit": DRG-Belegung, Fälle, errechnete Erlöse, VWD zur GVD, Live-KIS-
Belegung). KPI-Katalog (alle mit Drilldown-Kontrakt):

| Dashboard | KPIs | Drill-Pfad |
|---|---|---|
| **Erlös & CMI** | Casemix, CMI je FA/Monat, eff. BWR, Erlös (NLEI/NLKZ/NDRG), LBFW-Effekt (TNDRG) | FA → DRG → Fallliste → Akte |
| **Verweildauer** | VWD vs. UGV/MGV/OGV (Grenzverweildauern!), Langlieger, Kurzlieger-Abschläge | Ausreißerliste → Fall |
| **Belegung/Kapazität** | Mitternachtsstatistik, Auslastung je Station, Belegungs-Heatmap (Tag×Station) | Zelle → Patientenliste |
| **Wiederaufnahmen** | 30-Tage-Quote je FA/DRG (Graph-Kante WIEDERAUFNAHME existiert) | Paar-Liste → beide Fälle |
| **ZNA-Steuerung** | Zugänge/h, door-to-doc (soweit Zeitstempel), Aufnahmequote | Tag → Fälle |
| **OP-Auslastung** | Eingriffe je Saal/Tag, Auslastung, Top-OPS | Saal/Tag → Eingriffe → Fall |
| **Kodierqualität** | Diagnosen je Fall, DKR-Auffälligkeiten, Downcoding-Feedback (aus MDM-Erkenntnissen) | Kode → Fallliste |
| **MD-Risiko** | Prüfquote je Kasse/DRG, Erlösrisiko offener Verfahren (MDM-Daten) | → CliniBots MDM |
Alle Aggregat-Endpoints mit `mask(n<5)`-Kleinzellen-Schutz.

---

## 6. Kohorten-Builder (Forschen) — i2b2/ATLAS-Muster
Verifizierte Vorbilder: **i2b2** (grafische Ein-/Ausschlusskriterien, iterative
Kohortengrößen-Schätzung ohne SQL — entlastete ~44 % der Analystenanfragen) und
**OHDSI ATLAS** (~100 Preset-Charakterisierungsanalysen über Indexdatum-verankerte
Zeitfenster: any-prior/365/180/30 Tage).

- **Builder:** Kriterienbaum (UND/ODER) über Diagnose/Prozedur/Labor/Medikation/
  Demografie/Fallart/OE mit **Live-Count** je Schritt; Kriterien-JSON speicher-/teilbar.
- **Charakterisierung:** automatische Baseline-Tabelle der Kohorte (Alter, Geschlecht,
  Top-Diagnosen/-Prozeduren/-Labore) in ATLAS-Zeitfenstern relativ zum Indexereignis.
- **Vergleich:** Kohorte A vs. B nebeneinander (VBridge-Befund: Kliniker brauchen
  **Kohorten-Evidenz als Kontext** für Einzelfall-Entscheidungen).
- **Drill:** Kohorte → Fallliste → Akte (Kontrakt). Export CSV/FHIR-Group.
- **NL→Kohorte:** MCP-Tool übersetzt natürliche Sprache in Kriterien-JSON (Review-Schritt
  davor, nie Direkt-SQL).

---

## 7. Architektur (on-prem, ohne Cloud — bestätigt machbar)
Die Recherche validiert den eingeschlagenen Stack ausdrücklich:
- **FHIRBoard** (MIT) materialisiert **SQL-on-FHIR-v2-ViewDefinitions in DuckDB** und
  dashboardet mit Superset — exakt unser Muster; wir übernehmen die Idee
  **ViewDefinition-als-Konfig** für neue Marts statt handgeschriebener SQL.
- **Pathling** (CSIRO) als FHIR-Analytik-Referenz; **HAPI FHIR JPA** (Apache-2.0) als
  optionaler Sidecar für echtes FHIR-REST + `$summary`/IPS (on-prem bewiesen).
- Eigenes leichtes Frontend bleibt (self-contained SVG, kein CDN — Egress-Verbot),
  ergänzt um: URL-State-Routing, Drilldown-Komponente (ein generischer
  `drill(aggregat)->fallliste->akte`-Mechanismus), Timeline-Komponente mit Brush/Zoom.

```
Replika ──Pumpe──▶ Bronze(Parquet+CDC) ──▶ bronze_current ──▶ FHIR-NDJSON(+Profile)
                                                    │                │
                                        ViewDefinitions/Gold   optional: HAPI-Sidecar
                                                    │            ($summary/IPS, ISiK-REST)
                                              mcp.* (maskiert)
                                                    │
                              API (+authz Row-Level, mask n<5, Audit)
                                                    │
              UI: Suche/Facetten · P360 · Stationsboard · MC-Dashboards · Kohorten
```
Governance quer darüber: Login (AD/lokal), Rollen, `authz`-Kette (fertig verifiziert),
Zugriffs-Audit, Mode-Badge (Pseudonym/Klartext) im Header.

---

## 8. Roadmap: Ziel → Ist (ehrlicher Abgleich)

**Fundament liegt:** 16 Ressourcentypen gemappt, mcp.*-Schicht, MCP-Server gehärtet,
Authz-Kette verifiziert, Pumpe deployt. Es fehlt Sichtbarkeit + Breite + Drilldown.

| Phase | Inhalt | Aufwand |
|---|---|---|
| **P1 „Sichtbar machen"** | P360-Sektionen für ALLE bereits gemappten Ressourcen (Prozeduren, Risiken, Coverage, Account, ServiceRequest, Organization/Practitioner-Links); Facettensuche; Drilldown-Kontrakt v1 (Analytik-Charts → Fallliste → Akte); mask(n<5); Mode-Badge; CDC-Lag-Kachel | 2–3 SE |
| **P2 „Fall & Timeline"** | 3-Ebenen-Encounter-Verlegungskette; interaktive Timeline (Swimlanes, Brush); Fall-Detail mit DRG/Erlös + MD-Badge→MDM; Appointment-Mapper (NAPP/NTMN); N2OPDIAGNOSEN→Condition | 2–3 SE |
| **P3 „Medikation & ZNA"** | COPRA-Adapter (ZCOPRA_01/ZISH_COPRA_FALNR-Dreiklang → MedicationStatement/Observation vital-signs); NDOC_ZNA/NDOCSTORNO; Stationsboard + ZNA-/OP-Sicht | 3–4 SE |
| **P4 „Steuern"** | MC-Dashboards komplett (Erlös/CMI aus NLEI/NLKZ/NDRG + GVD aus ZNRKT/TNDRG-Wissen, Wiederaufnahmen, Belegungs-Heatmap) — alles mit Drillthrough | 3 SE |
| **P5 „Forschen & Standards"** | Kohorten-Builder + Charakterisierung; MII-KDS/ISiK-Profil-Layer (`meta.profile`); IPS-Export; Studien/Biobank-Sektion | 3–4 SE |
| **P6 „Vertrauen"** | Governance-Vollausbau (Login/TOTP/Session), Dokument-Intelligence, Graph-Vervollständigung (Labor/Doku/Practitioner-Knoten, Pathway-Mining), Provenance-Ressourcen | 3+ SE |

Quick-Wins aus P1 sind in Tagen lieferbar (Daten liegen alle schon in `mcp.*`).

## 9. Offene Punkte (aus der Recherche, ehrlich)
- Epic/Oracle/Medplum/Aidbox-Innenansichten: keine belastbaren Quellen überlebten die
  Verifikation — kein Blocker, unsere Referenzen (IPS, MII, i2b2/ATLAS, FHIRBoard) tragen.
- Consent-Modul-Einordnung im MII schwankt (Basis vs. daneben) → bei P5 aktuell prüfen.
- MC-Drilldown-Patterns: nur Sekundärquellen (TIP HCe, DRG-Konsenspapier) → unser
  KPI-Katalog §5 ist Praxis-Konsens, nicht Peer-Review.
- ISiK: „Stufe 3 verbindlich" gilt Stand Mitte 2026; Stufe 5 offen → beobachten.

## 10. Quellen (verifizierte Kernbelege)
MII KDS & FHIR R4: Bundesgesundheitsblatt 2024 (10.1007/s00103-024-03888-4); PMC11166738;
medizininformatik-initiative.de (KDS Fall V2025 IG). · ISiK: fachportal.gematik.de;
§373 SGB V. · IS-H-Referenz: UMM-DIZ-Datenkatalog (uni-heidelberg.de). · IPS/on-prem:
hapifhir.io (IPS/$summary); smilecdr.com. · Patient-360-Abrufmuster:
developer.healthgorilla.com ($p360). · UX: PMC4394966 (JAMIA-Review, LifeLines);
PMC2779809 (i2b2); Book of OHDSI Kap. 11 (ATLAS); arXiv:2108.02550 (VBridge). ·
Stack: github.com/the-momentum/fhirboard; pathling.csiro.au; SQL-on-FHIR v2
(build.fhir.org). · MC-KPIs: DRG-Berichtswesen-Konsenspapier; TIP-HCe-Cockpit.
