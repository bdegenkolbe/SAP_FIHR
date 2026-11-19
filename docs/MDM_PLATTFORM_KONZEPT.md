# CliniBots MDM auf der Cluster-Plattform — Konzept v2 (rkt.greenbay.systems)

> **ABGELÖST (Stand 19.11.2026).** Führend ist das MDM-Repo: `docs/KONZEPT_MDM_GREENBAY.md`
> (Testsystem `mdm.greenbay.systems`, anonymisierte Einzeldaten, Qwen-Modelle,
> Produktivbetrieb on-premise im UKL), ergänzt um `KONZEPT_EINGANG_PROZESSE_KI.md` und
> `KONZEPT_DOKUMENTENABLAGE.md`. Die Befunde F1–F3, F8, F9 sind dort erledigt (R41–R44).
> Dieses Dokument bleibt nur als Herleitung erhalten (§1.2 Befunde, §2.3/§2.4 Datenbefunde).

**Stand:** 15.11.2026 (R34) · **Status:** Entwurf zur Entscheidung
**Baut auf:** `MD_MANAGEMENT_KONZEPT.md` (Domänenmodell), Repo `bdegenkolbe/MD_Management`
(App, Stand R40), VERIFY_LOG R34 (ZNRKT-Detailanalyse), Cluster-Erkundung vom 15.11.2026.

## 0. Kurzfassung

Ja, aus der ZNRKT-Familie lässt sich eine MD-Anwendung für den Cluster bauen — und es
gibt sie im Kern schon: **CliniBots MDM** (FastAPI + DuckDB, drei Stufen: Analytik,
Fristen-Cockpit, Fallakte). Sie läuft heute als Einzelplatz-Anwendung unter Windows.
Der Weg nach `rkt.greenbay.systems` ist deshalb **kein Neubau, sondern drei Schritte**:

1. **Fachlich reparieren** (vor allem anderen): Die Kennzahlen der App zählen
   Statuszeilen statt Reklamationen. Das Rechnungsvolumen steht dort mit 9,19 Mrd €
   (richtig: 80–142 Mio € pro Jahr), die Erfolgsquote mit 36,8 % (Haus-Definition auf
   Reklamationsebene: 57–69 % in der MD-Phase).
2. **Plattformfähig machen:** Container, Postgres statt Einzel-DuckDB-Schreibpfad,
   Anmeldung über Keycloak, Synthetik-Testdaten mit realistischer Struktur.
3. **Prozesse und KI ergänzen:** Argo Workflows (läuft im Cluster bereits) für acht
   Bearbeitungsprozesse, davon fünf mit KI-Schritt, jeder mit menschlicher Freigabe;
   ein Skill `md-management` als gemeinsame Arbeitsanweisung für Mensch-Claude und
   Workflow-Schritte (Entwurf: `docs/skills/md-management/`).

Die Plattform passt: Argo Workflows 4.1.2 mit Keycloak-SSO, cert-manager, ingress-nginx
und ein Wildcard-DNS `*.greenbay.systems`, das `rkt.` bereits auf den Cluster auflöst.
Argo Events und Argo CD fehlen — beides wird für den Start **nicht** gebraucht.

---

## 1. Prüfung des bisherigen Konzepts

### 1.1 Was trägt

- Domänenmodell (Fallklammer `FALNR+KOSTR+LFDNR`, Streit-Sichten, Brücken zu NDIA/NICP/
  NLEI/NFAL) — live bestätigt, Referenzintegrität sehr gut (4 Waisen bei 4,8 Mio Zeilen).
- MDM-Repo R35/R36: `ZNRKT_BER` als echte Fristenquelle, `LFDNR` als Vorgangsart,
  Abgleich mit der produktiven Qlik-RKT-App des Hauses, `/SMS/RKT_EDI` als belastbare
  §301-Erlöszahl, Altbestandsfilter sichtbar statt verschwiegen.
- Sicherheitsgrundsätze: read-only gegen SAP, Maskierung vor Persistenz, Audit-Hashkette.

### 1.2 Was falsch oder überholt ist

| # | Befund | Wirkung | Quelle |
|---|---|---|---|
| F1 | `gold.fakt_reklamation` liegt auf **Statuszeilen-Ebene**; `SUM(rechnung_netto)` und `COUNT(*)` laufen darüber | Volumen ~7-fach, Reklamationszahl 1,34 Mio statt 295.179, Erfolgsquote verzerrt | MDM `marts.py`, `kpis.py`; R34 |
| F2 | Ergebnisklassen hand-kuratiert (`config/catalogs.yaml`) statt Hauskatalog `ZNRKT_C_REKLERL.GRUPPE`; „Kompromiss“ und „MDK“ fehlen, „Beendigung nach Datenkorrektur“ als *verloren* statt *Kompromiss* | Erfolgsquote weicht von der Haus-Definition ab | R34 |
| F3 | `RKT_PHASE` kennt im App-Katalog nur RKZ/MDK; **VVF** (Vorverfahren/Erörterung) fehlt | EV-Fälle unsichtbar | R34 |
| F4 | Vorgangsart aus LFDNR ist umgesetzt, der **Filter auf interne Prüfungen** (Haus-Reporting) liegt seit R36 zur Entscheidung | jede Kachel betroffen | MDM R36 |
| F5 | Architektur Einzelplatz: DuckDB-Einzelschreiber, Windows Credential Manager, Aufgabenplanung, loopback | nicht mehrbenutzer- und clusterfähig | MDM `DEPLOYMENT.md` |
| F6 | Wissen driftet zwischen zwei Repos: SAP_FIHR kannte R35/R36 nicht, MDM kennt R34 nicht | Doppelarbeit, widersprüchliche Zahlen | dieses Dokument |
| F7 | `MD_MANAGEMENT_KONZEPT.md` nennt 16 Tabellen und keine Kataloge; das Repo hat 83 | Konzept unterschätzt Datenbasis | MDM R35 |
| F8 | Demo-Seed bildet Reklamationen mit nur einer Statuszeile ab | der Ebenenfehler F1 war in Tests unsichtbar | MDM `seed.py` |
| F9 | Fristen-Cockpit rechnet nur die Unterlagenstrecke; Aufgaben-SLA (`C_AUFTYP.AUF_BEARBZT`) und MD-Begehungstermine fehlen, stornierte Aufgaben werden je nach Filter mitgezählt | Arbeitskorb unvollständig | R34 §2.3 |
| F10 | `MD_MANAGEMENT_KONZEPT`/Registry: MCS als „Datenaustausch“, MDK als „Altworkflow“, KLA als „kompletter Instanzweg“ beschrieben — alle drei widerlegt | Fehlplanung von Funktionen | R34 §2.3 |

**Konsequenz:** F1–F3, F8 und F9 werden vor jeder Plattformarbeit behoben, sonst trägt das
Cluster-System die falschen Zahlen nur weiter. F6 wird durch eine Regel gelöst:
**Fachliche Datenbefunde zur ZNRKT-Familie werden im MDM-Repo geführt**, SAP_FIHR
verweist nur noch darauf (VERIFY_LOG-Einträge mit Querverweis).

---

## 2. Datenbasis

### 2.1 Abdeckung der ZNRKT-Familie

Inventarisiert sind alle 83 Tabellen (MDM R35 + SAP_FIHR R34). Alle 24 Transaktions-
tabellen sind PK-geprüft und mit R34 auch inhaltlich geprüft (Belegung, tote Felder,
Kataloge, Zeitfelder, Brücken). Von den 59 Katalogen sind die fachlich tragenden
vollständig gelesen; Personen- und Technikkataloge nur strukturell erfasst. Offen ist
allein die Brücke `ZNRKT_Z75 → NLEI` (Massentabelle, nur im Lastfenster prüfbar).

### 2.2 Testdaten statt Echtdaten

Im Cluster liegen **nur synthetische Daten**. Echte Fall- und Abrechnungsdaten des UKL
gehören erst dorthin, wenn Datenschutz-Folgenabschätzung, AV-Vertrag mit dem
Betreiber und ein Betriebsbeschluss vorliegen (Art. 9 DSGVO, § 203 StGB).

Der Generator wird aus dem bestehenden `seed.py` weiterentwickelt:

| Anforderung | Umsetzung |
|---|---|
| richtige Ebenen | Vorgang → 1–n Reklamationen → 1–32 Statuszeilen (Verteilung aus der Replika: Ø 4,6), Beträge je Statuszeile wiederholt — so fällt F1 in Tests auf |
| realistische Verteilungen | **Profil-Export:** nur aggregierte Verteilungen (Typen, Gründe, Stände, Laufzeiten, Beträge als Quantile) über den sapfhir-live-MCP → `profil.json` → Generator. Keine Einzelwerte, keine Kennungen |
| echte Kataloge | `ZNRKT_C_*` ohne Personenbezug (Stände, Gründe, Erledigungsgründe, Aufgabentypen …) dürfen 1:1 übernommen werden — es ist Haus-Customizing, keine Patientendaten. Personenkataloge (Sachbearbeiter, MD-Ärzte) werden synthetisch ersetzt |
| alle Streitgegenstände | DRG/ICD/OPS/Z75/BEA/TOB je Sicht, BER mit Fristen, EDI mit Differenzen |
| Prozessrealismus | Zeitachse „heute“ mit offenen Fällen in allen Ampelfarben, Altbestand, Mahnungen, EV |
| Kennzeichnung | jede Ansicht und jeder Export trägt „TESTDATEN“ |
| Klinischer Kontext für KI | synthetische Kurz-Dossiers (Diagnosen, Prozeduren, Verlauf in Stichworten), damit Triage und Entwürfe testbar sind |

### 2.3 Ergebnisse der Detailprüfung R34 (Resttabellen, live 15.11.2026)

| Tabelle | Was sie wirklich ist | Für die App nutzbar | Tot / Falle |
|---|---|---|---|
| `ZNRKT_AUF` (968k) | Aufgaben/Wiedervorlagen; Status NEU/INAR/WAST/ERL (`C_AUFSTAT`) | **1.729 offen, 938 überfällig**; Soll-Bearbeitungstage je Typ in `C_AUFTYP.AUF_BEARBZT` → SLA (z. B. Gutachtenprüfung Ist 164 Tage gegen Soll 30) | 20.322 **stornierte** Aufgaben stehen noch auf offenem Status → Storno immer filtern; 515k ohne Reklamationsbezug (`REKL_POS='00'`); Tippfehler-Jahre (1024, 2225) |
| `ZNRKT_MCS` (219k) | **Ergebnisklassifikation je Vorgang** (1 Zeile/Vorgang), *nicht* Datenaustausch | Fehlerursache `MCS_ERG` (`C_MCSERG`): kein Fehler 64,5k · Fehlbelegung 54,9k · Dokumentation 37,6k · sonstiges 30,3k · unbewertet 25,6k; Prüfdatum ab 2020 verlässlich | MCS_ERG2–4, MCS_BEGR, Zweitarzt |
| `ZNRKT_FAK` (565k) | Rechnungen vorher (V) / nachher (N) je Vorgang und Reklamation; Modul 20 Reklamation, 80 Klage | Erlösdelta N−V (−38,3 Mio € je REKL_POS) | **FAK_STREIT/FAK_ERGEBNIS tot**; Platzhalterbelege („RECHNUNG01“, „RESTBTR“); V-Belege über mehrere REKL_POS mehrfach → deduplizieren |
| `ZNRKT_BER` (968k) | angeforderte Unterlagen, 43 Typen (`C_BERTYP`) | Zeitkette Anforderung → Ausgang (98 %) → Wiedereingang (76 %) | `BER_ZIEL_DAT` tot (88 Zeilen) — keine Frist am Bericht selbst |
| `ZNRKT_KG` (238k) | Papierakten-Logistik | 62.513 hängen auf „angefordert“ | Erinnerungslogik nur bis 04/2024 (Prozessumstellung, Deutung) |
| `ZNRKT_ICD/OPS` | Kodestreit je Sicht | Brücke NDIA 96 % / NICP 82 %; **ICD_LFDNR_NDIA ≥ 800 = MD/KK-eigene Kodes** ohne Hauszeile (seit 2025 ~50 %) | `_MDE`, KORGR tot |
| `ZNRKT_Z75` (165k) | Zusatzentgelt-Streit mit Beträgen je Sicht | Beträge ISH/MDK/RKT | Join zu NLEI timeoutet → nur im Lastfenster |
| `ZNRKT_BEA` (15k) | Beatmungsstunden je Sicht | 2.126 Abweichungen ISH↔MDK | Brücke nur über FALNR |
| `ZNRKT_TOB` (78k) | Tage ohne Berechnung (Grund aus `C_TOBGRUND`: SFB, PFB, präop. Diagnostik) | 55.870 gekürzte Tage | Tage als Text gespeichert |
| `ZNRKT_KLA` (4,5k) | Klagen, 75–110 neue pro Jahr | Streitwert, Abgabe-/Erledigungsgrund, Aktenzeichen SG | **34 Felder tot** (Instanzweg, Gutachten, Beträge); Kanzleifeld Freitext |
| `ZNRKT_MDK` (18k) | **MD-Begehungen, aktiv** (bis 2026, 105 künftige Termine) | Terminkalender, Konsens/Dissens | Gutachtendaten, CW_* tot — „Altworkflow“ war falsch |
| `ZNRKT_C_FRIST` | 1 Zeile: FRIST1 = 42, FRIST2 = 180 Tage | Default-Fristen (fachlich zu bestätigen) | — |

**Folgen für die Anwendung:**
- **Arbeitskorb und Fristen** stützen sich auf drei Quellen: Aufgaben (`AUF`, mit SLA aus
  `C_AUFTYP`), Unterlagenkette (`BER` + `BERMAHN`, Restanten aus `KG`) und
  Begehungstermine (`MDK`). Prüffristen kommen aus `KOPF.FRIST1/FRIST1_EIN` und
  `C_FRIST`. Tote Datumsfelder (BER_ZIEL_DAT, KLA-Daten, MDKGUTDAT) werden nicht genutzt.
- **Erfolgs- und Erlösanalytik:** Ergebnis aus `REKL_ERLGR` + `C_REKLERL`, Fehlerursache aus
  `MCS_ERG`, Erlösdelta aus `FAK` (V gegen N, dedupliziert) und `/SMS/RKT_EDI`,
  Kürzungstage aus `TOB`.
- **KI-Material:** Die Sichten ISH/MDK/KK/ANF/RKT in ICD/OPS/Z75/BEA/TOB zeigen je Fall,
  was das Haus kodiert, was MD und Kasse fordern und was herauskam — Grundlage für
  Vergleichsfälle (P3/P4) und Kodier-Feedback (P8).

### 2.4 Schriftverkehr und Dokumente (live 18.11.2026)

Das RKT-Modul verwaltet Schreiben über vier Kanäle (Konfiguration `ZNRKT_C_PARAM`):

| Kanal | Was | Wo es liegt | Menge |
|---|---|---|---|
| DMS-Dokument, Eingang Kasse | Scan `MED/DTA_KASSE` | NDOC + DRAW, Inhalt auf dem Content-Server | 291.902 seit 2005, ~10–12k/Jahr |
| DMS-Dokument, Eingang MD | Scan `MED/DTA_MDK` | dito | 166.901; **2024: 10.510 → 2025: 1.314 → 2026: 62** |
| DMS-Dokument, eigene Schreiben | `RKT/ZRKT_BRF_1` (Anschreiben MD, Stellungnahme Gutachten, Widerspruch Sanktionszahlung) | dito, ohne Dateiformat | 49.113 seit 02/2015, ~600–750/Jahr |
| DMS-Dokument, Stellungnahmen | Scan `VER/VRW_VER-02` | dito | 20.457, ~500–800/Jahr |
| **neu seit 09.11.2026** | `ARC/DTAKASSE_I` (Kasseneingang über Archiv) | dito | 120 in der ersten Woche |
| Word-Vorlagen | Stellungnahme MLQM, Schreiben an MD, EV-Dokubogen, Widerspruch Sanktionszahlung, Begleitschreiben PV, Klageanfrage | Vorlagen auf `W:\_GLOBAL\RKT_MDK\Dokumentvorlagen`, ausgefüllt **lokal gespeichert** | nicht zählbar — außerhalb SAP |
| SAP-Formular | EV-Dokumentation `ZRKT_EVF_01` | SAP-Druck | — |
| Elektronisch | §301-DTA (`/SMS/RKT_EDI`), MD-Leistungsentscheid-Portal (Menüpunkt `ZMDPORTAL`) | SAP / Portal | siehe EDI |

**Befunde:**
- **Inhalte sind nicht repliziert**, nur Metadaten (Typ, Datum, Fall, Status). Ein
  Dokumentenregister in der App ist möglich, das Öffnen braucht den Content-Server des
  Hauses (Link per DOKAR/DOKNR in i.s.h.med).
- **Status `AN`/`FR`:** Die meisten Dokumente stehen auf `AN` (angelegt), auch in
  abgeschlossenen Vorgängen. Das ist offenbar der Normalzustand und **kein
  Freigabestau** (Korrektur zur ersten Fassung dieses Abschnitts).
- **Kanalwechsel MD, mit Lücke in der Akte:** Die Leistungsentscheide des MD kommen
  stabil an (Status „Eingang LE“: 2024 4.974, 2025 4.903, 2026 4.533). Das Schreiben dazu
  liegt aber immer seltener im DMS: Ein MD-Scan ±5 Tage um den Eingang findet sich 2024
  bei 73 %, 2025 bei 11 % und 2026 bei 0,4 %. Bei DRG-Prüfverfahren ohne jedes
  RKT-Dokument: 2024 7 %, 2025 67 %, 2026 85 %. Vermutlich laufen Prüfanzeige und
  Leistungsentscheid jetzt über das LE-Portal (Menüpunkt `ZMDPORTAL`). **Wo diese
  fristauslösenden Dokumente abgelegt werden, ist offen** und muss mit dem
  Medizincontrolling geklärt werden.

**Typischer Dokumentenverlauf eines DRG-Prüfverfahrens (Stichproben 2024):**
MD-Prüfanzeige als Scan am Tag 0–2 → Unterlagenpaket (Entlassbrief, Kurzbericht,
Pflege-, Labor-, Medikationsbericht …) am Tag 0–1 angefordert → gebündelter Versand an
einem Tag (Tag 14–47; Stände „Unterlagen an Kasse / MDK“ + „E-Unterlagenversandt“) mit
RKT-Begleitschreiben → Leistungsentscheid als Scan, einen Tag später Status „Eingang LE“
→ gegebenenfalls Erörterungsverfahren, Rechnungskorrektur, Strafzahlungsbescheid.
Eine direkte Verknüpfung Vorgang ↔ Dokument gibt es nicht. Die Zuordnung geht nur
über Fall und Zeitraum; die Checkliste in `ZNRKT_MCS` (Akte versandt 50–70 %, sonst
kaum gepflegt) ersetzt sie nicht.
- **Schriftverkehr außerhalb SAP:** Mit Word-Vorlagen erstellte Stellungnahmen,
  EV-Dokumentationen und Klageanfragen liegen nicht strukturiert am Vorgang.
- **Gericht:** Gerichtsschriftverkehr gibt es im RKT nicht als Dokumenttyp. Klagen sind
  nur als Datensatz (`ZNRKT_KLA`) und Notiz (`ZNRKT_KLA_TXT`) erfasst; die Akten
  liegen vermutlich beim Justiziariat bzw. der Prozessvertretung (Ordner „PV“).

**Konsequenz für die App:**
- **Dokumentenregister je Vorgang** (Eingang, Ausgang, Fristbezug) aus NDOC/DRAW,
  zugeordnet über Fall und Zeitraum, mit sichtbarer Zuordnungsregel.
- **Prüfregel „Fristauslöser ohne Dokument“:** Status „Beginn“, „Eingang LE“ oder
  „Strafzahlung“ ohne zugehöriges Schreiben → Hinweis im Arbeitskorb. Heute träfe das
  fast jeden Vorgang seit 2025.
- **Anbindung des neuen Eingangskanals** (LE-Portal bzw. `ARC/DTAKASSE_I`), sobald
  geklärt ist, wo die Dokumente liegen.
- **Prozesse P5/P6** legen Entwürfe direkt am Vorgang ab statt in lokalen
  Word-Dateien. Der Versand bleibt beim Menschen.

---

## 3. Zielarchitektur im Cluster

```
                        rkt.greenbay.systems (ingress-nginx, letsencrypt)
                                      │
                         ┌────────────┴────────────┐
                         │   Namespace rkt          │
                         │  ┌────────┐ ┌─────────┐  │
  Keycloak (login.       │  │ mdm-web│ │ mdm-api │──┼──► Argo-Server-API (submit,
  greenbay.systems,  ◄───┼──│ (SPA)  │ │FastAPI  │  │     resume/freigabe)
  Realm higl, OIDC)      │  └────────┘ │+ MCP rkt│  │
                         │             └────┬────┘  │
                         │        ┌─────────┴─────┐ │
                         │        │ Postgres rkt  │ │  PVC ionos-ssd-retain,
                         │        │ (app, gold,   │ │  Sicherung nach
                         │        │  audit)       │ │  ops/dateien/06
                         │        └───────────────┘ │
                         └────────────▲─────────────┘
                                      │ nur Netzwerkfreigabe jobs-rkt → rkt
                         ┌────────────┴─────────────┐
                         │ Namespace jobs-rkt        │
                         │ WorkflowTemplates P1–P8   │
                         │ CronWorkflows P1,P2,P7,P8 │
                         │ SA rkt-jobs               │──► KI-Endpunkt (siehe §5)
                         └───────────────────────────┘
```

| Baustein | Entscheidung | Begründung |
|---|---|---|
| Namespaces | `rkt` (App, DB) und `jobs-rkt` (Workflows) | Konvention „ein Namespace je Rechtekreis“ (`ops/argo/README.md`) |
| Manifeste | `C:\ai\infra\ops\rkt\01-namensraum … 08-argo-*.yaml`, `kubectl apply` | bestehende Konvention; GitOps (Argo CD) später gesondert entscheiden |
| Image | `higl.cr.de-fra.ionos.com/rkt/mdm:<version>`, Pull-Secret im Namespace | Registry vorhanden |
| Datenbank | eigenes Postgres in `rkt` (nicht Supabase in `plattform`) | Testdaten sauber getrennt von Produktivschemata, keine Freigabe in `plattform` nötig |
| Analytik | Gold-Marts als Postgres-Views/materialisierte Views; DuckDB nur noch optional für Exporte | Mehrbenutzer, Transaktionen für Freigaben und Aufgaben |
| Anmeldung | OIDC gegen Keycloak `higl` in der App; Rollen über Keycloak-Gruppen (`rkt-leser`, `rkt-bearbeiter`, `rkt-freigabe`, `rkt-admin`) | gleiche Identität wie Argo-UI; Freigaben brauchen eine echte Person im Audit |
| Netz | `default-deny-ingress` + `allow-from-ingress`; zusätzlich Netzzugang-Profil `verwaltung` | Muster der übrigen Apps |
| Ereignisse | App ruft die Argo-Server-API direkt (submit/resume); Zeitsteuerung über CronWorkflows | Argo Events ist nicht installiert und für diese Ereignisse (alle entstehen in der App) überflüssig |
| MCP | `mdm-api` stellt zusätzlich die Werkzeuge `rkt_*` bereit; Einbindung in den Verbund `mcp.greenbay.systems` | Claude-Zugang für das Medizincontrolling ohne eigenen Server |

**Risiken der Plattform** (aus der Erkundung): ingress-nginx ist abgekündigt (Umstieg
auf Traefik geplant, Manifeste neutral halten); Kyverno steht nur auf *Audit*; Keycloak-
Scope `groups` muss im Realm existieren, bevor gruppenbasierte Rechte greifen.

---

## 4. Automatisierte Bearbeitungsprozesse

Acht Prozesse als Argo-`WorkflowTemplate`s, beschrieben in
`docs/skills/md-management/reference/prozesse.md`. Kurzform:

| ID | Prozess | Auslöser | KI | Nutzen |
|---|---|---|---|---|
| P1 | Datenlauf (Testdaten bzw. Delta → SCD2 → Marts → DQ-Gate) | nachts | — | stabile Basis; Abbruch bei DQ-Fehler statt falscher Zahlen |
| P2 | Fristenwächter | 2× täglich | — | Ampel, Eskalationsaufgaben, Tagesliste |
| P3 | Eingangs-Triage | neue Reklamation | ✓ | Einordnung, Erfolgsaussicht, Unterlagen-Checkliste, Aufgaben |
| P4 | Gutachten-Auswertung | Leistungsentscheid | ✓ | akzeptieren / widersprechen / EV — mit Belegen |
| P5 | Stellungnahme-Entwurf | Knopfdruck | ✓ | Entwurf in der App |
| P6 | EV-Vorbereitung | Stand „Eröffnung EV“ | ✓ | Fallmappe für das Erörterungsverfahren |
| P7 | AWP-/Strafzahlungsprüfung | täglich | — | nichts verjährt unbemerkt |
| P8 | Kodier-Feedback | wöchentlich | ✓ (Bericht) | Prävention statt Reaktion |

**Grundmuster jedes KI-Prozesses:** `dossier → ki-schritt → pruefen → freigabe (suspend)
→ uebernehmen → audit`. Die Freigabe erfolgt in der App durch eine Person mit Rolle
`rkt-freigabe`; die App setzt den Workflow per API fort. Kein Prozess sendet etwas nach
außen oder schreibt in SAP.

---

## 5. KI-Funktionen

### 5.1 Funktionen

| Funktion | Eingabe | Ausgabe | Technik |
|---|---|---|---|
| Erfolgsaussicht | Dossier + Vergleichsfälle (gleiche DRG/Prüfgrund/Kasse) | hoch/mittel/niedrig + Quote + Fallzahl | **deterministisch** (Statistik über Historie); KI formuliert nur die Begründung |
| Prüfgrund-Einordnung | Prüfanzeige-Kodes, Streitsichten | Gründe nach `ZNRKT_C_GRUND` | Regeln zuerst, KI für Freitext-Anteile |
| Unterlagen-Checkliste | Prüfgrund, Vorgangsart, Berichtstypen | fehlende Unterlagen | Regeln + Katalog `ZNRKT_C_BERTYP` |
| Gutachten-Bewertung | MD-Forderung vs. Kodierung, Kodierrichtlinien | Empfehlung + Begründung + Belege | KI mit Skill, `dxgrouper` für Gruppierung/CCL |
| Entwürfe (Stellungnahme, EV-Mappe) | Dossier, Empfehlung | Text | KI mit Skill, Vorlagen |
| Kodier-Feedback | Aggregat beanstandeter Kodes je Abteilung | Bericht | Statistik + KI-Zusammenfassung |
| Assistenz im Dialog | Fragen des Medizincontrollings | Antworten mit Zahlen | Claude + MCP `rkt` + Skill |

Grundsatz: **Zahlen kommen aus SQL, Worte aus dem Modell.** Das Modell bekommt
Kennzahlen fertig gerechnet und darf keine eigenen berechnen.

### 5.2 Modellwahl (zu entscheiden)

| Option | Für | Gegen |
|---|---|---|
| Claude über die Anthropic-API | beste Qualität bei Begründungen und Entwürfen; Skill-Format nativ | Datenverarbeitung außerhalb des Clusters — für **Testdaten unkritisch**, für Echtdaten DSFA und Vertrag nötig |
| IONOS AI Model Hub (EU, offene Modelle) | Daten bleiben bei IONOS in Deutschland; im Konto bereits verfügbar | schwächere Modelle für juristisch-medizinische Texte; Skill-Inhalt muss als System-Prompt übergeben werden |

**Empfehlung:** Für die Testphase Claude (Qualitätsmaßstab setzen). Den KI-Schritt
hinter eine schmale Schnittstelle legen (`dossier + skill + schema → ergebnis`), damit
für den Echtbetrieb der Anbieter ohne Prozessänderung wechselbar ist. Vor dem
Echtbetrieb beide Optionen gegen denselben Prüfsatz messen.

### 5.3 Qualitätssicherung der KI

- **Prüfsatz:** 100 synthetische Fälle mit bekannter richtiger Antwort je Prozess;
  läuft bei jeder Änderung an Skill, Prompt oder Modell als Argo-Workflow.
- **Messgrößen:** Schema-gültig (100 % Pflicht), Belegtreue (jede Aussage mit Feld im
  Dossier), Übereinstimmung mit Sollentscheidung, Eskalationsquote.
- **Im Betrieb:** Freigabe-/Ablehnungsquote je Prozess und Begründung der Ablehnung
  zurück in den Prüfsatz.
- **Recht:** Die KI trifft keine Entscheidung gegenüber Dritten; jede Ausgabe wird von
  einer Person geprüft (kein Fall von Art. 22 DSGVO). Kennzeichnung „KI-Entwurf“ an
  jedem Text; Protokoll von Modell, Prompt-Hash und Freigebendem in der Audit-Kette.

---

## 6. Skill `md-management`

Entwurf: `docs/skills/md-management/` (SKILL.md + `reference/datenmodell.md`,
`kennzahlen.md`, `fristen.md`, `prozesse.md`, `werkzeuge.md`).

Ein Skill, zwei Nutzer:
- **Claude im Dialog** (Medizincontrolling, Entwicklung): lädt ihn bei MD-Themen
  automatisch, arbeitet über den MCP `rkt`.
- **KI-Schritte in Argo:** der Workflow-Container lädt `SKILL.md` + die für den Prozess
  nötigen `reference/*.md` als Arbeitsanweisung und liefert das Prozess-Schema.

Kern des Skills sind die drei Regeln (nichts nach außen ohne Freigabe; nur
pseudonymisierte Daten; erst zählen, dann behaupten) und die geprüften Fallen der
Datenbasis. Nach Freigabe wird er nach `C:\ai\infra\skills\md-management` übernommen
und im Container-Image versioniert mitgeliefert (gleiche Version wie die App).

---

## 7. Umsetzungsplan

| Phase | Inhalt | Ergebnis | Aufwand (grob) |
|---|---|---|---|
| **A — Korrektur** | F1–F3, F8, F9 im MDM-Repo: Mart je Reklamation, Volumen je Beleg, Klassen aus `C_REKLERL`, VVF, Seed mit Statuszeilen, Arbeitskorb aus AUF (SLA, Storno) + MDK-Termine; Entscheidung F4 | Zahlen stimmen mit Replika und Haus-Definition überein | 3–4 Tage |
| **B — Plattform** | Dockerfile, Postgres-Backend, Keycloak-OIDC, Testdaten-Generator mit Profil-Export, Manifeste `ops/rkt/01–07`, Deployment | App läuft unter `rkt.greenbay.systems` mit Testdaten | 5–8 Tage |
| **C — Prozesse** | P1, P2, P7 (ohne KI) als WorkflowTemplates/CronWorkflows, Freigabe-Mechanik in der App | Fristenwächter läuft automatisch | 3–5 Tage |
| **D — KI** | KI-Schnittstelle, P3–P6, P8, Skill finalisieren, Prüfsatz + QS-Workflow | KI-Vorschläge mit Freigabe | 8–12 Tage |
| **E — Echtbetrieb** (separat) | DSFA, AV, Datenweg Replika → Cluster oder Betrieb on-prem, Rollen- und Rechtekonzept mit dem Medizincontrolling | Entscheidungsvorlage | — |

## 8. Offene Entscheidungen

1. **Interne Prüfungen** (LFDNR 410–419) wie im Haus-Reporting ausschließen? (F4)
2. **Modell für die Testphase:** Claude-API (Empfehlung) oder IONOS Model Hub?
3. **Zugang:** nur Netzzugang-Profil `verwaltung` + Keycloak, oder zusätzlich offen für
   Demo-Zwecke (Testdaten)?
4. **GitOps:** bei `kubectl apply` bleiben (Empfehlung für den Start) oder Argo CD
   einführen?
5. **Führendes Repo:** Fachbefunde zur ZNRKT-Familie künftig nur im MDM-Repo (Empfehlung).
6. **Echtbetrieb:** im Cluster (dann Datenweg + DSFA) oder on-prem beim Kunden mit
   gleichem Container?
7. **Ablage der MD-Dokumente seit 2025:** Wo liegen Prüfanzeigen und Leistungsentscheide
   aus dem LE-Portal? Das klärt das Medizincontrolling; erst danach ist ein
   Dokumentenregister vollständig.
