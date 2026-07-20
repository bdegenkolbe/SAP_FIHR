# Dokumentenlandkarte — CliniBots Patient Insight

**Einstiegspunkt für jede Session.** Stand: 20.07.2026 (R19).

## Namensschema (verbindlich)
| Ebene | Name |
|---|---|
| **Produkt** | **CliniBots Patient Insight** (CliniBots-Produktwelt — „Klinik. Daten. Management.") |
| Schwesterprodukt | **CliniBots MDM** (Medizincontrolling/MD-Management, eigenes Repo `C:\ai\MD_Management`) |
| Technische Codenamen (bleiben) | Repo `SAP_FIHR`, Package `sapfhir`, MCP-Server `ishx-mcp`, Branch `claude/concept-analysis-expansion-nwg4ua` |
| Historische Namen (nur noch in Archiv-Docs) | „GREENBAY clinical — IS-H Edition", „ishx" als Produktname |

## Leserichtung
```
INDEX.md (hier)
 ├─ 1. CONCEPT_P360_VOLLAUSBAU.md   ← ZIELBILD (wohin)          [leitend]
 ├─ 2. CONCEPT.md (+ dessen §14–§19) ← ARCHITEKTUR (wie gebaut)  [leitend]
 ├─ 3. ROADMAP.md                    ← EINE Roadmap (was wann)   [leitend]
 ├─ 4. Analyse_Datenbank.md          ← METHODE (Dreiklang etc.)  [verbindlich]
 └─ 5. Fach-/Querschnittskonzepte + Kataloge + Protokolle (unten)
```

## Dokumente nach Rolle & Status

### Leitend (aktiv gepflegt — Widersprüche hierzu sind Fehler)
| Dokument | Rolle |
|---|---|
| `CONCEPT_P360_VOLLAUSBAU.md` | **Zielbild** Patient Insight 2.0: Drilldown-Kontrakt, 3 Lenses, FHIR-Vollkatalog A–D, P360-Akte/Timeline, MC-Dashboards, Kohorten-Builder. Deep-Research-fundiert (24 verifizierte Quellen). |
| `CONCEPT.md` (v0.3) | **Architektur & Betriebskonzept**: Medaillon-Pipeline, No-Admin, Delta-Merge (§14), DQ (§15), FHIR-Ausleitung v2 (§16), MCP-Härtung (§17), Terminologie (§18). §8/§12/§19 sind durch Zielbild+ROADMAP überlagert (dort markiert). |
| `ROADMAP.md` | **Die einzige Roadmap.** Ersetzt: CONCEPT §12/§19-Ausbau, GESAMTREVIEW §4-Backlog, INGOLF §5, Analyse_Datenbank §8-Backlog (dort jeweils Verweis). |
| `Analyse_Datenbank.md` | **Verbindliche Methode**: Dreiklang, NPAT-Breitensuche, Verkryptung, DIAS-Abdeckung, Massentabellen-Regel. |
| `PATIENT_DATENKATALOG.md` | Vollständigkeits-Rahmen: 77 patientenbezogene Tabellen, 37 Lücken (R19). |
| `BERECHTIGUNGSKONZEPT.md` | Zugriff/RBAC: AD→PERNR→KOSTL→SETNODE-Rollup ⇄ NOEK→NBEW (Kette live verifiziert R19); `authz`-Modul umgesetzt. |
| `DEPLOYMENT.md` | Installation & Betrieb (No-Admin). Natives Deployment dieses PCs: `C:\ai\_ops\README.md`. |
| `MCP_SETUP.md` | MCP-Anbindung (Claude Desktop/Code). |

### Fachkonzept Schwesterprodukt
| Dokument | Rolle |
|---|---|
| `MD_MANAGEMENT_KONZEPT.md` | Domänenanalyse RKT/ZNRKT (§275c) — **umgesetzt als CliniBots MDM** (eigenes Repo; dortige Doku: VALIDIERUNG.md, DEPLOYMENT.md). Hier: Datenmodell-Referenz + Verbund-Schnittstelle (MD-Badge → MDM-Fall-Akte). |

### Protokolle (fortlaufend, nur anhängen)
| Dokument | Rolle |
|---|---|
| `VERIFY_LOG_R8-R13.md` | **Fortlaufendes Verifikationslog ab R8** (aktuell bis R19; Dateiname historisch, bleibt wegen Verweisen). Jede neue Runde wird angehängt. |
| `config/tables.yaml` | Lebende Registry (PKs „verifiziert Rx", Befunde in notes). |

### Archiv (historisch — nicht mehr fortschreiben, Aussagen ggf. überholt)
| Dokument | Inhalt | Überholt durch |
|---|---|---|
| `ANALYSE.md` | Review Konzept v0.1→v0.2 | CONCEPT v0.3 |
| `CONCEPT_EXT.md` | Konzepterweiterung v0.2 (N*-Vollauswertung) | in CONCEPT v0.3 §18/§19 + Registry integriert |
| `VERIFY_RESULTS.md` …`_4.md` | Remote-Verifikationsrunden R1–R4 | VERIFY_LOG (R8+) |
| `ALTBESTAND_ANALYSE.md` | BaseTable/DIAS-Altbestand | Erkenntnisse in Registry/CONCEPT §14 übernommen |
| `GESAMTREVIEW.md` | Review nach R8–R16 | Backlog §4 → ROADMAP.md |
| `INGOLF_FUNKTIONSVERGLEICH.md` | Übernahme-Kandidaten aus Schwesterplattform | Roadmap §5 → ROADMAP.md (Analyse bleibt Referenz) |

## Konsistenzregeln
1. Neue Erkenntnisse: **sofort** `tables.yaml` (notes) + VERIFY_LOG (neue Runde).
2. Neue Vorhaben: **nur** in ROADMAP.md (nirgendwo sonst Backlogs anlegen).
3. Archiv-Docs bekommen Status-Banner, werden aber nicht umgeschrieben (Historie).
4. Produktname in allen neuen Texten: CliniBots Patient Insight / CliniBots MDM.
