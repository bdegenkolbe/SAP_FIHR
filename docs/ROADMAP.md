# ROADMAP — CliniBots Patient Insight (die einzige Roadmap)

**Stand: 20.07.2026 (R19).** Dieses Dokument ersetzt alle verstreuten Backlogs:
CONCEPT §12 (Basisphasen) & §19 (Ausbau), GESAMTREVIEW §4 (#-Backlog),
INGOLF_FUNKTIONSVERGLEICH §5 (P1a–P3), Analyse_Datenbank §8. Alte IDs sind unten je
Arbeitspaket in `[..]` gemappt. Neue Vorhaben werden NUR hier ergänzt (INDEX.md-Regel 2).

> **Einbettung:** Die Phasen hier sind im `GESAMTKONZEPT.md` §7 zu Suite-Meilensteinen
> M0–M5 gebündelt (M0=Q1/Q4 · M1=P1+P2 · M2=MDM-2027 · M3=P3+P4 · M4=P5 · M5=P6) und je
> Use-Case begründet. Neu aus dem Gesamtkonzept (siehe unten): AP-M1, AP-M6 (MDM-Repo),
> AP-K3 sowie Nachrecherchen N1–N4.

## 0. Erledigt (Fundament — Stand der Wahrheit)
- ✅ Pipeline komplett: Keyset-Backfill + `__ct`-CDC → `bronze_current` + Compaction →
  FHIR-NDJSON (16 Ressourcentypen aus 21 Tabellen, Mapper+Tests) → Gold → `mcp.*` →
  Kuzu-Basisgraph. [CONCEPT §12 Phasen 1–5]
- ✅ MCP-Server gehärtet (9 Tools, Sandbox, Audit-Hash-Kette). [CONCEPT §17]
- ✅ Registry ~100 Tabellen, PKs live verifiziert R8–R19; DIAS-Abdeckungsdiff
  automatisiert; ref_*-Klartextschicht + `resolve_code`. [GESAMTREVIEW #3, Analyse_DB §8.3/.4]
- ✅ RKT/ZNRKT-Familie (16 Tabellen) verifiziert → **CliniBots MDM** als eigenes Produkt
  gebaut, validiert, deployt (eigenes Repo/Roadmap).
- ✅ Patienten-Datenkatalog (77 Tabellen / 37 Lücken) + Berechtigungskonzept mit live
  verifizierter Kette (PA0105→PA0001→SETNODE/SETLEAF ⇄ NOEK→NBEW) + `authz`-Modul
  (Resolver, deny-by-default, whoami/P360-Gate, 11 Tests).
- ✅ Natives Deployment auf MFAI_BDE_HOME (beide Apps, Autostart, ops.ps1);
  Datenpumpe demo-e2e; Live-Config vorbereitet (`connection.yaml`, pytds).
- ✅ Zielbild 2.0 (CONCEPT_P360_VOLLAUSBAU, Deep-Research-fundiert).
- ✅ Kohorten-Backfill „aktuelle Stationspatienten" mit **Ladeknopf** im Entlade-Monitor
  (`POST /api/cohort/load` + Status-Polling); Default-Scope korrigiert auf NUR aktuell
  offene Faelle (kein automatischer Historie-Ausbau); DQ-Dashboard kennzeichnet
  Kohorten-Teilladungen als `KOHORTE` statt `UNKNOWN`. Details/Lehre: VERIFY_LOG R22.

## Q. Querschnitt (laufend, kein Phasen-Gate)
| AP | Inhalt | Herkunft |
|---|---|---|
| Q1 | **Live-Backfill** fahren (User+PW → `dbsource --check` → `backfill --tier 1` → Gold-Rebuild) — wartet auf Zugang | DEPLOYMENT |
| Q2 | **37 Katalog-Lücken** je Dreiklang schließen (Prio: ZCOPRA_01/ZISH_COPRA_FALNR, NLKZ/NLLZ, NCIR, NDOC_ZNA, NAMB/NMBG, NPIX/NPAE) | PATIENT_DATENKATALOG §3 |
| Q3 | Lastfenster-Verifikationen: NICP↔N1LSTEAM-Alternativpfad, NDOC-Fill (54 M), N2LABOR-Familie | [Analyse_DB §8.2] |
| Q4 | `authz.sql.build` in Nightly einhängen + AD-Header-Login (Reverse-Proxy) bzw. lokale Logins | BERECHTIGUNGSKONZEPT §6 |
| Q5 | Fehler-207-Fallback im Extractor (Schema-Drift) | [INGOLF P1d / GESAMTREVIEW #14] |
| Q6 | NFFZ-REFA-Katalog klären (Q/T/S) → ggf. Patient.link M/N | [Analyse_DB §8.5] |

## P1 „Sichtbar machen" (2–3 SE) — größter Hebel, Daten liegen in mcp.*
| AP | Inhalt | Herkunft |
|---|---|---|
| P1.1 | P360-Sektionen für ALLE gemappten Ressourcen (Prozeduren, Risiken/Allergien, Coverage, Account, ServiceRequest, Org/Practitioner-Links, Geburt) — **Layout-Rahmen dafür steht: Darstellung D1 umgesetzt** (Master-Detail-Ersetzen + Deep-Link, Sticky-Patient-Header, ICD-Problemliste aufklappbar, Fälle offen/Jahr gruppiert, keine Sentinel/leeren Panels; `CONCEPT_P360_DARSTELLUNG.md`) | Zielbild §3 + Darstellung §6 |
| P1.2 | **Facettensuche** vor der Akte (ICD/OPS/Alter/Labor/OE/Zeitraum, Live-Count, Trefferliste) — v0 erledigt: gepagte Patientenliste (50/100/200, PATNR-Suche, Klick→Akte, `GET /api/patients`); fehlt noch: ICD/OPS/OE/Zeitraum-Filter | [INGOLF P1b / GESAMTREVIEW #12] |
| P1.3 | **Drilldown-Kontrakt v1**: alle Analytik-Charts → Fallliste → Akte, URL-State | Zielbild §1 |
| P1.4 | Aggregatschutz `mask(n<5)` zentral in der API | [INGOLF P1c / GESAMTREVIEW #13] |
| P1.5 | Mode-Badge (Pseudonym/Klartext) + CDC-Lag-Kachel + VERIFY-Kachel im Monitor | [INGOLF P1a-UI, CONCEPT §15.4/§19.4] |

## P2 „Fall & Timeline" (2–3 SE)
| AP | Inhalt | Herkunft |
|---|---|---|
| P2.1 | 3-Ebenen-Encounter-Verlegungskette (MII KDS Fall V2025: Einrichtung→Abteilung→Versorgungsstelle) als Grafik im Fall-Detail | Zielbild §3.2 |
| P2.2 | ✅ **v1 umgesetzt:** Interaktive Swimlane-Timeline (Fall-Balken + Ereignispunkte je Domäne, Jahres-Ticks, Brush-Zoom per Ziehen, 1/5/10J-Schnellbereiche, klickbare Legende) = Darstellungsstufe **D2**; offen: Klick→Fall-Drilldown, danach D3 (Episodes-of-Care, Chart-Suche, Quick-Filter-Chips) | Zielbild §3.1, Darstellung §6 |
| P2.3 | `map_appointment` (NAPP; NTMN nach Dreiklang) | [CONCEPT §6, Registry deklariert] |
| P2.4 | N2OPDIAGNOSEN → Condition (surgical) | [CONCEPT_EXT §4/§8.6] |
| P2.5 | Fall-Detail — **v1 umgesetzt:** Drilldown-Drawer per Klick auf Fall-Zeile/Timeline-Balken (`GET /api/fall/{falnr}`: Kopf, NBEW-Bewegungskette mit Typ-Text+OE-Name, Diagnosen, Prozeduren; MDM-Deep-Link ⚖, Esc/Backdrop schließt). Offen: DRG/Erlös-Panel + echtes MD-Badge (braucht NDRG/ZNRKT in der Kohorte) | Zielbild §2 Stufe C |

## P3 „Medikation & ZNA" (3–4 SE)
| AP | Inhalt | Herkunft |
|---|---|---|
| P3.1 | **COPRA-Adapter**: ZCOPRA_01 + ZISH_COPRA_FALNR Dreiklang → MedicationStatement + Observation(vital-signs) | [GESAMTREVIEW #8, Analyse_DB §8.7] |
| P3.2 | NDOC_ZNA + NDOCSTORNO (entered-in-error) in DocumentReference | Datenkatalog |
| P3.3 | Stationsboard (offene Bewegungen je Station, authz-gefiltert) + ZNA-/OP-Sicht | Zielbild §4 |

## P4 „Steuern" (3 SE)
| AP | Inhalt | Herkunft |
|---|---|---|
| P4.1 | Erlös-/Leistungs-Marts: NLEI/NLKZ/NLLZ (Lastfenster!) + NDRG/TNDRG (LBFW) | [GESAMTREVIEW Großbaustelle, CONCEPT §19.2] |
| P4.2 | MC-Dashboards: CMI/Erlös, VWD vs. GVD, Belegungs-Heatmap, Wiederaufnahmen, OP, ZNA — alle mit Drillthrough | Zielbild §5 |
| P4.3 | Kodierqualität + MD-Risiko (Kennzahlen aus MDM-Verbund) — inkl. **Kodier-Feedback-Loop MDM→CPI** (beanstandete Konstellationen als Hinweis in der Fall-Akte) | Zielbild §5, GESAMTKONZEPT UC-M5 |
| P4.4 | **AP-K3** Entlassmanagement-Transparenz: 48h-Melde-KPI + VWD-Überschreiter-Liste (bewusst OHNE VWD-Senkungs-Versprechen) | GESAMTKONZEPT UC-K3 [A] |

## P5 „Forschen & Standards" (3–4 SE)
| AP | Inhalt | Herkunft |
|---|---|---|
| P5.1 | Kohorten-Builder (Kriterien-JSON, Live-Count) + ATLAS-Charakterisierung (any/365/180/30-Fenster) | [INGOLF P2a / GESAMTREVIEW #15] |
| P5.2 | MCP-Tool `cohort_query` + NL→Kriterien (Review-Schritt) | [INGOLF P2d] |
| P5.3 | FHIR-Profil-Layer `meta.profile` (Basis-R4 → ISiK → MII-KDS) | [INGOLF P2b / GESAMTREVIEW #16, CONCEPT §19.1] |
| P5.4 | IPS-Export (`$summary`-Muster; eigener Generator, optional HAPI-Sidecar) | Zielbild §3.2 |
| P5.5 | Forschungs-Sektion (Studien /UKL/ /UKU/, Biobank ZBIO_*; Consent-Einordnung prüfen) | Zielbild §2 Stufe D |

## P6 „Vertrauen" (3+ SE)
| AP | Inhalt | Herkunft |
|---|---|---|
| P6.1 | Governance-Vollausbau: Login Argon2id+TOTP, Rollen, Session, security.db, API-Audit | [INGOLF P1a / GESAMTREVIEW #11] |
| P6.2 | Settings-UI Write-Through + DPAPI-Secrets | [INGOLF P2c / GESAMTREVIEW #17] |
| P6.3 | Dokument-Intelligence (Viewer, Annotation, NLP-lite; nach SOOD/SRGBTBREL-Verify) | [INGOLF P3 / GESAMTREVIEW #18] |
| P6.4 | Graph-Vervollständigung (Labor/Dokument/Practitioner/Kostenträger-Knoten + Kanten, Pathway-Mining) | [CONCEPT §19.3] |
| P6.5 | Provenance-Ressourcen je Lauf vollenden | [CONCEPT §16.3] |
| P6.6 | SCD2-/CDPOS-Historisierungsstrang (Lastfenster) | [GESAMTREVIEW #7, Analyse_DB §8.6] |

## MDM (Verbund-relevante Pakete; Führung im MDM-Repo)
| AP | Inhalt | Herkunft |
|---|---|---|
| AP-M1 | **§275c-Quoten-Cockpit**: eigene Quartals-Quote, Abstand zur Staffelschwelle, Simulation Regime 2025 (5/10/15 @60/40) vs. **2027 (5/15/25 @80/60)** — harte Deadline 1.1.2027 | GESAMTKONZEPT UC-M1 [A] |
| AP-M6 | **GKV-SV-Benchmark-Import** (CSV/XLSX Q1/2020–Q1/2026, standortbezogen; vorhandenen Monitoring-Skill nutzen) → „wir vs. Bund/Land" | GESAMTKONZEPT UC-M6 [A] |

## N. Nachrecherchen (aus Verifikations-Lücken; N1 priorisiert)
| AP | Inhalt |
|---|---|
| N1 | Erlösverluste/Erfolgsquoten je Kassenart **selbst aus GKV-SV-CSVs auswerten** (Rohdaten offen; zugleich MDM-Demonstrator) |
| N2 | Personalaufwand MD-Management (DGfM/FoKA) + eigene Messung aus ZNRKT_AUF-Durchlaufzeiten |
| N3 | Publizierte Effekte Belegung/OP/Wiederaufnahme/QM/Pflegecontrolling (eigene Recherche-Runde) |
| N4 | Wettbewerbs-Funktionsvergleich (TIP HCe, Tiplu MOMO, ORBIS BI, MetaKIS, LOGEX): FHIR/on-prem/MDM-Lücke |

**Reihenfolge-Logik:** P1 zuerst (nur Frontend/API, sofortiger Mehrwert), Q1/Q2 parallel
(Datenbasis), dann P2→P3→P4; P5/P6 nach Bedarf priorisierbar. **AP-M1 hat eine externe
Deadline (1.1.2027).** CliniBots MDM hat eine eigene Roadmap im eigenen Repo;
Verbundpunkte (P2.5, P4.3, AP-M1, AP-M6) stehen hier gespiegelt.

## G. Lückenanalyse 22.07.2026 (interner Soll-Ist-Abgleich + Wettbewerbs-Research N4)

**Intern (Konzept verspricht, Code fehlt — Top-Prioritäten):**
| AP | Befund | Schwere |
|---|---|---|
| G1 | **Authz real scharfschalten**: `authz.sql.build` läuft NIRGENDS; PA0105/PA0001/SETNODE/SETLEAF/NOEK werden weder von Kohorte noch Backfill geladen; `authz.enabled=true` würde gegen leere auth-Tabellen ALLES sperren (toter Schalter). Kein Login-Fluss. | hoch |
| G2 | **P1.1-Sektionen**: NRSF (Risiken) + NKSK (Coverage) sind GELADEN, haben aber keine Akten-Sektion; Prozeduren nur im Drawer | hoch |
| G3 | `mask(n<5)` fehlt in allen Analytik-Endpunkten (P1.4-Zusage) | mittel |
| G4 | Tote Mapper: `map_organization_einrichtung`/`_das301` nie im PLAN; `map_appointment` deklariert aber nicht existent; `n1meorder`-Mapper läuft auf leerer Tabelle statt COPRA | mittel |
| G5 | Labor: UI-Sektion + KPI + Timeline-Lane vorhanden, N2LABOR/001 aber nicht in COHORT_KEY → dauerhaft leer | mittel |
| G6 | MCP-FHIR-Tools (`fhir_get/search/doc_search`) laufen im Default-Ladeweg ins Leere (FHIR-Export übersprungen, N2TEXT nicht geladen) | mittel |
| G7 | CDC existiert nur als unbenutzte CLI; GESAMTKONZEPT §4 „Datenpumpe ✅ (Backfill+CDC)" ist zu optimistisch — Ladeknopf macht Voll-Backfill | mittel |
| G8 | `fhir.profile`-Schalter (r4/isik/mii) wird nirgends gelesen; keine FHIR-Validierung (§15.3), kein `meta.profile` | niedrig |
| G9 | Endpunkte ohne UI: top_prozeduren, verweildauer, monitor/runs, whoami — Berechtigungsmodell im UI unsichtbar | niedrig |

**Markt (verifiziert, N4 — nur TIP HCe + Tiplu überlebten die Prüfung; Rest offen):**
- **Marktlücke BESTÄTIGT:** FHIR-nativ + on-prem auf IS-H-Replika + operatives §275c-MD-Management + Patient-360 + Self-Service-Kohorten in EINEM Stack bietet keiner. Aber zwei Annäherungen: TIP Medical Data Lake (FHIR/OMOP-Kohorten, nur Dedalus-KIS-Quellen, 5 Ressourcentypen Stand 2021) und **TipluDB** (FHIR-CDR, ISiK/MII-kompatibel lt. Hersteller, longitudinale Patientenbasis).
- **Was Wettbewerber haben, wir nicht** (Kandidaten für spätere Phasen): KI-Kodiervorschläge (Tiplu MOMO, Uniklinik-Referenzen Würzburg/Leipzig) · betriebswirtschaftliches Controlling: Kostenträger-/Deckungsbeitragsrechnung, Planung/Simulation, Process Mining (TIP HCe) · PpUGV-/AEB-Budgetverhandlungs-Unterstützung (TIP HCe). TIP-HCe-MD ist NUR nachgelagerte Analytik — CliniBots MDM (operativ) bleibt differenzierend.
- **Offen (Nachrecherche N4b):** BinDoc/Vebeto/LOGEX/KMS/MetaKIS/myMedis/CGM ohne verifizierte Claims; TipluDB-IS-H-Fähigkeit klären.
