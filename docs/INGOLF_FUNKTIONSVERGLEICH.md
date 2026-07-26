# Funktionsvergleich Ingolf (EUGASTRO-Praxisplattform) ↔ CliniBots Patient Insight (SAP_FIHR)

> **STATUS: REFERENZ-ANALYSE** (siehe `INDEX.md`). Die Übernahme-Roadmap §5 (P1a–P3) ist
> in `ROADMAP.md` aufgegangen (dort als `[INGOLF Px]` gemappt); die Funktionsanalyse
> §1–§4 bleibt als Referenz gültig. Nicht mehr fortschreiben.

Quelle: `legacy/ingolf-main.zip` (Stand 2026-07-16, 122 Dateien). Analysiert:
README, CLAUDE.md, docs/ (CONCEPT, BENUTZERVERWALTUNG, UI_SPEC, KI_INTEGRATION,
DOKUMENTE_ANNOTATION, SCHEMA), server/ (auth, rbac, analysis, patients, settings),
store/ (annotate, vault), agent/ (privacy, profiles, dbsource), ui/app.

## 1. Was Ingolf ist

In einer Arztpraxis betriebene Schwesterplattform desselben Musters wie SAP_FIHR:
read-only MSSQL-Quelle (PVS „EUGASTRO") → inkrementeller FHIR-R4-Export → lokaler
verschlüsselter Store (SQLCipher) → Analyse-UI (FastAPI, 127.0.0.1) — No-Admin,
Klardaten verlassen das Haus nie. Darüber hinaus hat Ingolf aber eine komplette
**Governance-Schicht** (Benutzer/Rollen/Audit/Break-Glass), eine **Kohorten-Analyse**
mit Aggregatschutz, einen **Dokument-Intelligence-Layer** (BLOB→Text→Annotation)
und einen **FHIR-Profil-Layer** (R4/MII-KDS/KBV). Genau diese vier Blöcke fehlen
SAP_FIHR heute.

## 2. Architekturvergleich

| Dimension | Ingolf | SAP_FIHR | Konsequenz für Übernahme |
|---|---|---|---|
| Quelle | EUGASTRO dbo (142 Tab., MedDok-Drehscheibe) | IS-H/i.s.h.med sap (85 Tab. Registry, NPAT/NFAL-zentriert) | Domänenlogik NICHT übertragbar, Muster schon |
| Store | SQLCipher/SQLite, Präfix-Schemas sec_/audit_/vault_/fhir_/nlp_ | DuckDB (bronze/silver/gold/mcp) + Parquet | Sicherheits-Tabellen als eigene SQLite neben DuckDB (DuckDB kennt keine Zeilen-Rechte) |
| Ausleitung | FHIR NDJSON + Store-Load, uuid5-idempotent | FHIR NDJSON + Index/Provenance | gleichwertig |
| Privacy | 3 Modi (off/pseudonymize/anonymize), rollengebunden, Re-ID-Vault | 1 Modus (pseudonymize_view für mcp.*), Einweg-hash_id, KEIN Vault | Weiche + Vault = größte konzeptionelle Lücke |
| UI | SPA + Login + Rollen + Modus-Badge, 5 Bereiche | SPA ohne Login, 3 Tabs | Auth-Schicht fehlt komplett |
| Analyse | Kohorten-Builder (Kriterien-JSON, UND/ODER), Aggregatschutz n<5, Forschungsexport | feste Dashboards + MCP sql_query | Kohorten-Engine ist 1:1 portierbar (SQL auf mcp.*/gold statt fhir_resource) |
| Betrieb | Setup.bat + Uninstall + signierbare Setup.exe, Settings-UI mit Write-Through nach config.yaml | Setup.bat + Nightly | Settings-UI + Uninstall übernehmen |
| KI | Gateway-Konzept (chat/embed/ocr/code) + Sandbox-Service (gebaut) | MCP-Server (Claude als Client), gehärtet | komplementär — MCP bleibt unser Weg; NL→Kohorte-Idee übernehmen |

## 3. Funktionsinventar Ingolf mit Übernahmebewertung

Legende: ✅ übernehmen · 🔶 angepasst übernehmen · ⏸ später/optional · ❌ nicht (Praxis-spezifisch)

### 3.1 Sicherheit & Governance (BENUTZERVERWALTUNG.md, server/auth.py, rbac.py)
| Funktion | Detail | Bewertung |
|---|---|---|
| Login Argon2id + TOTP (RFC 6238, stdlib), Rate-Limit, Sperre, Recovery-Codes, First-Run-Bootstrap (Owner + TOTP-QR im Browser, kein Mailserver) | `server/auth.py` 241 Z., ohne externe Dienste | ✅ **P1** — im Klinikumfeld (mehr Nutzer als Praxis!) zwingender als bei Ingolf selbst |
| 7 Rollen mit Rechtematrix (owner/clinician/mfa/analyst/researcher/auditor/admin_tech), additiv, deny-gewinnt bei Klardaten | `rbac.py`, Matrix in BENUTZERVERWALTUNG §3 | 🔶 **P1** — für UKL-Sekundärnutzung reichen zunächst 4: owner, analyst, auditor, admin_tech. clinician/mfa erst falls Klardaten-Modus je kommt (§5) |
| Datenschutz-Weiche: Modus (Klar/Pseudonym/Anonym) an Rolle+Zweck gebunden, dauerhaft sichtbarer Modus-Badge (rot/grün) auf jedem Screen | Herzstück laut Ingolf-Doku | 🔶 **P1** — SAP_FIHR ist heute IMMER pseudonym (Badge trivial). Die Weiche wird relevant, sobald Klartext-Freitexte angezeigt werden sollen (Dokument-Layer, §3.3) |
| Break-Glass-Re-Identifikation: Vault (Pseudonym↔PATNR, separat verschlüsselt), Re-Auth + Pflicht-Begründung, zeitlich begrenzt, append-only-Audit, optional 4-Augen | `store/vault.py` | 🔶 **P2** — heute ist hash_id bewusst EINWEG (Verkryptungsregel). Vault = bewusste Konzeptänderung: nur einführen, wenn der Fachbereich Re-ID wirklich braucht (z.B. Rückmeldung auffälliger Befunde). Dann exakt nach Ingolf-Muster |
| Append-only-Audit mit Hash-Kette für ALLE UI-Aktionen (Login, Moduswechsel, Export, Re-ID, Rechteänderung) | `audit_*`-Tabellen + Trigger | ✅ **P1** — SAP_FIHR hat die Hash-Kette bereits für den MCP-Server (mcp/audit.py); dieselbe Mechanik aufs Dashboard/API ausweiten |
| Session-Handling: kurzlebiges Token, Idle-Timeout, Re-Auth vor sensiblen Aktionen | `auth.py` | ✅ P1 (Teil des Logins) |

### 3.2 Patientenauswahl & Kohorten-Analyse (server/analysis.py, patients.py, UI_SPEC §3/§5)
| Funktion | Detail | Bewertung |
|---|---|---|
| Patientensuche mit Facetten (ICD, Alter, Laborschwelle, Medikation, Freitext), Trefferliste mit Diagnose-Tags/Ampel-Pill, Zeile → 360°-Sicht | `patients.search` | ✅ **P1** — größte UX-Lücke: unser Patient 360 setzt heute die KENNTNIS der PATNR voraus. Suche über mcp.diagnose/labor/fall ist mit DuckDB trivial |
| Kohorten-Builder: Kriterien-JSON `icd|atc|lab|age|gender|text|concept|period`, UND/ODER-Baum, deterministische SQL-Auswertung | `analysis._eval_node/_pseudonyms_for` (279 Z.) | ✅ **P1** — Engine 1:1 portierbar: Kriterien → Mengen von PATNR über mcp.*; ATC entfällt vorerst (Medikation erst mit COPRA), dafür `ops|fachr|bewty` ergänzen |
| Aggregatschutz: Zellen mit n < 5 maskiert (`mask()`) | `MIN_CELL = 5` | ✅ **P1** — Pflicht fürs Klinikumfeld; auch in bestehende Dashboard-Endpunkte einziehen (Top-Diagnosen/OE mit kleinen n) |
| „Als Kohorte analysieren" aus der Suche; Kohorten-KPIs, Verlaufskurven, Begleitdiagnosen | UI-Fluss | ✅ P2 (nach Engine) |
| Forschungsexport pseudonym/anonym (Generalisierung, nur Geburtsjahr) | `research_export`, `anonymize_extra` | 🔶 P2 — als NDJSON-Export der Kohorte; Anonymisierungsstufe aus Ingolf übernehmen |
| Provenienz-Schalter structured/nlp/all in jeder Auswertung | `_derivation_filter` | 🔶 P3 — erst relevant mit Dokument-Annotation (§3.3) |

### 3.3 Dokument-Intelligence (DOKUMENTE_ANNOTATION.md, agent/documents.py, store/annotate.py)
| Funktion | Detail | Bewertung |
|---|---|---|
| Typerkennung per Magic-Bytes (nie Endung), Text aus docx/pdf/rtf, OCR-Hook (pytesseract `deu`, Scan-Heuristik <40 Zeichen/Seite), saubere Degradation | `documents.py` | 🔶 **P2** — IS-H-Pendant: Arztbriefe via SOOD/SRGBTBREL (Backlog #4!) und DVS-Dokumente (NDOC verweist auf Archiv). Sobald der SOOD-Pfad verifiziert ist, ist dieser Parser das fertige Werkzeug |
| NLP-lite-Annotation: Terminologie-Matching (stdlib, kein spaCy-Zwang) + deutsche Negation/Verdacht/Familienanamnese, Overlay-Ablage `nlp_annotation` (DOC_CONCEPT), Konfidenz-Schwelle | `store/annotate.py` 241 Z. | 🔶 **P2** — auf N2TEXT-Freitexte (FTS existiert schon) und §301-Segmente anwendbar. ABER: Verkryptungsregel §4 — Annotation läuft auf Rohtexten, Ergebnis-Snippets sind PII-kritisch → nur mit Rollenmodell (§3.1) ausrollen |
| Dokument-Viewer mit farbig hinterlegten Annotationen + Konzeptliste (SNOMED/ICD) rechts, Annotations-Badge | UI | ⏸ P3 — nach Viewer-Grundlage (heute zeigt SAP_FIHR nur NDOC-Metadaten) |
| „Dokument-Konzept" als Kohorten-Kriterium (inkl. include_uncertain-Flag) | analysis.py `concept` | ⏸ P3 — folgt aus beidem |
| ai-provenance / nlp-provenance an abgeleiteten Ressourcen | Extension-Muster | ✅ P2 — Muster sofort in unsere NDJSON-Provenance übernehmen, sobald abgeleitete Ressourcen entstehen |

### 3.4 FHIR-Profil-Layer (agent/profiles.py, UI_SPEC §7)
| Funktion | Detail | Bewertung |
|---|---|---|
| Profil-Umschaltung R4 (bare) / **MII-KDS** / KBV: meta.profile-URLs + Pflichtfeld-/Slicing-Layer über unverändertem Mapping-Kern, Doppelausleitung möglich | `profiles.py`, pro Export wählbar | ✅ **P1–P2** — für ein UNIKLINIKUM der wertvollste Einzelbaustein: MII-KDS (Person, Diagnose, Prozedur, Fall, Labor) ist die Eintrittskarte in DIZ/Forschungsnetz-Kompatibilität. Layer-Ansatz (Kern bleibt, Profil setzt drauf) exakt übernehmen |

### 3.5 Betrieb, Settings, Robustheit
| Funktion | Detail | Bewertung |
|---|---|---|
| Einstellungen zentral in der UI (Recht settings.manage) mit **Write-Through nach config.yaml** → Nachtläufe nutzen dieselben Werte | `server/settings.py` | ✅ P2 — löst unser „Config nur per Datei"-Problem elegant |
| Secrets via DPAPI-geschützte Dateien (DB-Passwort, API-Keys) | `settings._dpapi_protect` | ✅ P2 — besser als unsere reine ENV-Lösung auf Windows (Nightly-Task!) |
| dbsource: unbekannte Spalte (MSSQL-Fehler 207) → generisch `NULL AS <col>` + Retry, je Query gemerkt, `[WARN]` im Log — Export läuft weiter | `agent/dbsource.py` | ✅ **P1, klein** — Schema-Drift-Robustheit für unseren Extraktor; passt zu unserer partial-PK-Robustheit in merge.py |
| Uninstall.bat, signierbare Setup.exe (PyInstaller) | installer/ | ✅ P3 |
| Design-System `ui/design/tokens.css` als Single Source of Truth (GREENBAY CI, Dark-Mode-Variante, AA, reduced-motion), i18n.js | ui/design | 🔶 P3 — Token-Datei übernehmen und Dashboard darauf umstellen (ein CI für beide Produkte) |
| Golden-Record-Testfälle mit fixierten Sollwerten | tests, Patient 3659 | ✅ bereits vorhanden (tests/test_golden.py) — Muster „Sollwerte fixiert je echtem Fall" nach Live-Anbindung nachziehen |
| Skeleton/Empty/Error-Zustände je Datenfläche | UI_SPEC §2 | ✅ P2, klein |

### 3.6 KI-Integration (KI_INTEGRATION.md, sandbox-service/)
| Funktion | Detail | Bewertung |
|---|---|---|
| Gateway mit 5 Kanälen (chat/embed/transcribe/ocr/code), Datenklassen-Policy je Kanal, Prompt-Gate, Audit mit Prompt-Hash | konzipiert, Sandbox gebaut | 🔶 — SAP_FIHR hat den umgekehrten, bereits gehärteten Weg (MCP: Claude als Client). KEIN zweites Gateway bauen. Übernehmen als Ideen: |
| **NL→Kohorte**: LLM erzeugt Kriterien-JSON, Nutzer sieht/korrigiert Tokens, Rechnung bleibt deterministisch inkl. Aggregatschutz | §3.3 | ✅ **P2** — als MCP-Tool `cohort_query(kriterien_json)` auf der Kohorten-Engine (§3.2); die „LLM schlägt vor, SQL rechnet"-Trennung ist genau richtig |
| NL→Auswertung mit Zahlen-Nachvalidierung (jede Zahl im Text muss im Aggregat vorkommen) | §3.3 | ✅ P3 — Guardrail-Muster fürs MCP-Berichtswesen merken |
| RAG-Wissensassistent (SOPs/AWMF, Zitierpflicht), Transkription, Arztbrief-Assistent | Stufe 1–2 | ⏸ — Versorgungskontext, nicht Sekundärnutzung; erst wenn SAP_FIHR je in die Behandlung rückt |
| Code-Interpreter-Sandbox (1 Container/Session, kein Netz) | sandbox-service/ | ⏸ — MCP sql_query + sandboxed DuckDB decken unseren Bedarf |

### 3.7 Nicht übernehmen (Praxis-/PVS-spezifisch)
- **PVS-Strang komplett** (Kernel, Fall/Schein, KVDT/ADT, GOÄ/PADneXt, Strangler gegen medatixx): IS-H IST das KIS — kein Äquivalenzbedarf. ❌
- eAU/Rezept/BMP/Heilmittel/DMP/HZV-Mapper: ambulante Versorgungsartefakte; IS-H-Pendants (NTMN-Termine, NDRG-Abrechnung) sind bereits in unserer Registry. ❌
- openEHR-Vorstufe: kein Bedarf angemeldet; FHIR + MII-KDS reicht. ⏸
- SQLCipher als Hauptstore: DuckDB bleibt (Analytik-Performance); SQLCipher/SQLite NUR für sec_/audit_/vault_ (§4). ❌/🔶

## 4. Architektur-Einpassung in SAP_FIHR

1. **Sicherheits-Store getrennt vom Warehouse:** `data/security.db` (SQLite,
   optional SQLCipher) mit Ingolf-DDL-Muster sec_benutzer/sec_rolle/sec_session/
   audit_eintrag (Hash-Kette wie mcp/audit.py). DuckDB-Warehouse bleibt unverändert;
   FastAPI prüft Session+Rolle VOR jedem `_q()`.
2. **Kohorten-Engine als eigenes Modul** `src/sapfhir/gold/cohort.py`: Kriterien-JSON
   (Ingolf-Schema minus atc, plus ops/fachr/bewty/vwd) → PATNR-Mengen über mcp.*;
   `mask(n)` mit MIN_CELL=5 zentral, auch von den bestehenden /api/analytics/*
   genutzt. UI: vierter Tab „Kohorten" mit Token-Builder (Ingolf ui/app als Vorlage).
3. **Profil-Layer** `src/sapfhir/fhir/profiles.py` nach Ingolf-Muster: `apply_profile
   (resource, "mii")` setzt meta.profile + Pflichtfelder NACH normalize_resource,
   VOR dem Schreiben; Auswahl in config + pro Lauf.
4. **Dokumentpfad bleibt hinter dem SOOD/SRGBTBREL-Verify** (GESAMTREVIEW #4):
   erst Quellpfad verifizieren (lokale Session), dann documents.py/annotate.py
   portieren. Freitext-Anzeige strikt hinter Rollenrecht `docs.read` + Modus-Badge.
5. **Verkryptungsregel bleibt Obergesetz:** Klardaten-Modus (Ingolf `off`) wird NICHT
   eingeführt, solange SAP_FIHR reine Sekundärnutzung ist. Der Modus-Badge zeigt
   dauerhaft „Pseudonym"; Break-Glass/Vault nur nach expliziter fachlicher
   Anforderung + Datenschutz-Freigabe (dann Ingolf §5 1:1).

## 5. Priorisierte Übernahme-Roadmap

| Prio | Paket | Inhalt | Aufwand (Session-Einheiten) |
|---|---|---|---|
| P1a | Governance-Grundschicht | Login (Argon2id+TOTP aus auth.py portieren), 4 Rollen, Session, Audit-Hash-Kette auf API, Modus-Badge | 2–3 |
| P1b | Patientensuche | /api/patients/search (Facetten ICD/Alter/Labor/Fachr) + Trefferliste → P360 | 1 |
| P1c | Aggregatschutz | mask(n<5) zentral in api/app.py + Kohorten-Vorbereitung | 0,5 |
| P1d | Extract-Robustheit | Fehler-207-Fallback in extract/dbsource.py | 0,5 |
| P2a | Kohorten-Builder | cohort.py + UI-Tab + Forschungsexport (pseudonym) | 2 |
| P2b | MII-KDS-Profil-Layer | profiles.py + meta.profile + Pflichtfelder Person/Diagnose/Prozedur/Fall/Labor | 2 |
| P2c | Settings-UI | app_setting + Write-Through nach config, DPAPI-Secrets | 1 |
| P2d | NL→Kohorte via MCP | MCP-Tool cohort_query auf P2a | 0,5 |
| P3 | Dokument-Intelligence | nach SOOD-Verify: documents.py/annotate.py-Port, Viewer, concept-Kriterium | 3+ |
| P3 | Design-Tokens/i18n, Uninstall, Setup.exe | Gleichschaltung CI | 1 |

## 6. Offene Entscheidungen (Björn)

1. **Rollenmodell-Start:** reichen owner/analyst/auditor/admin_tech (Empfehlung), oder
   sollen clinician/mfa (Klardaten-Sicht) von Anfang an mitgedacht werden?
2. **Break-Glass/Vault:** wird Re-Identifikation im UKL-Anwendungsfall gebraucht?
   (Wenn nein, bleibt hash_id einweg — einfacher und datenschutzfreundlicher.)
3. **MII-KDS:** welche Module zuerst (Person/Diagnose/Prozedur/Fall/Labor ist der
   übliche Kern)? Gibt es DIZ-Vorgaben des Hauses?
4. **MFA-Pflicht:** Ingolf-Default ist „aus" (Einzelplatz). Für UKL-Mehrplatz:
   „required" empfohlen.
