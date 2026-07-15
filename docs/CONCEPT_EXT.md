# SAP_FIHR — Konzepterweiterung v0.2
## Vollständige N*-Tabellenauswertung, Referenz-/Katalogschicht, Terminologie

Ergänzung zu `docs/CONCEPT.md` (v0.1). Stand 15.07.2026.
Grundlage: vollständiger Tabellenkatalog des Schemas `sap` (1.152 Basistabellen, davon
185 mit Präfix N). v0.1 deckte 21 Kern-Tabellen ab; diese Erweiterung bewertet die
übrigen 142 N-Tabellen fachlich und definiert, was die Read-only-Sekundärnutzung
zusätzlich gebrauchen kann.

> Hinweis: Live-Füllstände der hier neu aufgenommenen Tabellen konnten in dieser
> Sitzung nicht gezogen werden (mssql-MCP nicht erreichbar). Alle Mengenangaben ohne
> „verifiziert" sind aus der IS-H-Semantik geschätzt und mit `# COUNT?` markiert —
> vor Umsetzung mit einer `sys.partitions`-Abfrage bestätigen (Skript unten §7).

---

## 1. Leitgedanke der Erweiterung

v0.1 bringt den klinischen Kern nach FHIR (Patient, Encounter, Condition, Procedure,
Observation, DocumentReference). Was fehlt, sind drei Dinge:

1. **Referenz-/Katalogschicht** — ohne sie sind die Kerndaten kodiert, aber nicht lesbar.
   NGPA (Geschäftspartner), NKTR (Kostenträger), NORG-Texte, Fachabteilungs- und
   Bewegungsart-Kataloge, ICD/OPS-Kataloge der Einrichtung. Diese Tabellen sind klein,
   ändern sich selten (cdc: full) und machen aus „BEWTY=1" ein „Aufnahme". **Höchste
   Priorität**, weil sie jede Auswertung und jede LLM-Antwort erst verständlich machen.
2. **§301-Abrechnungsdatenstrom (NC301*)** — der bereits GKV-fertig kodierte
   Aufnahme-/Entlass-/Rechnungssatz. Für Analytik (Verweildauer, Entlassgründe,
   Aufnahmeanlass, Kostenträgerwechsel) oft sauberer als die Rohbewegungen.
3. **i.s.h.med-Auftrags-/Statuswelt (N1*) und Zusatzdoku (N2*)** — Leistungsanforderung,
   Auftragsstatus, OP-Diagnosen, strukturierte Zeiten. Selektiv, da vieles Customizing/
   Steuertabellen ist.

Arztbriefe: NDOC/N2TEXT sind zwar gefüllt (53,9 Mio Dok-Köpfe / 53,9 Mio Textzeilen),
aber die **Brief-Kategorien** (Entlassbrief, Epikrise) sind hier offenbar dünn bis leer —
i.s.h.med-Häuser dokumentieren Briefe oft im nachgelagerten System, nicht in N2TEXT.
Konsequenz: DocumentReference bleibt im Kern, aber wir setzen **nicht** auf Volltext-
Arztbriefe als Analysequelle. Statt dessen tragen die strukturierten Tabellen
(NC301*, NDIA, NICP, N2OPDIAGNOSEN) die klinische Aussage. Verifikation §7, Punkt B.

---

## 2. Referenz-/Katalogtabellen (NEU, Priorität 1)

Neue Pipeline-Stufe **`reference/`** analog zum Schwesterprojekt: einmaliger/periodischer
Lauf (cdc: full), Ausleitung als **FHIR-Terminologie** (CodeSystem / ValueSet /
Organization / Location) und als DuckDB-Lookup-Tabellen für die Marts.

| Tabelle | Inhalt (IS-H) | Verwendung | FHIR |
|---|---|---|---|
| **NGPA** | Geschäftspartner (Ärzte, Einweiser, Institutionen, Kostenträger als GP) | Namensauflösung Einweiser/behandelnde Ärzte, Organisationen | Organization / Practitioner / PractitionerRole |
| **NKTR** | Kostenträger (Krankenkassen-Stammdaten) | Kassenname, Kassenart, IK-Nummer → Auswertung nach Kostenträger | Organization (payer) |
| **NKSK / NKSD** | Kostenträger-/Vertrags-Konditionen, Kassenschlüssel-Detail | Zuordnung Fall→Kasse, Kassenart-Gruppierung | Coverage-Anreicherung |
| **NORG** (Texte) | OE-Bezeichnungen (Fachabteilung, Pflege-OE, Station) | „KARD" → „Klinik für Kardiologie"; OE-Baum | Organization / Location |
| **NFKL** | Fachabteilungs-/Fachrichtungsschlüssel | §301-konforme FA-Bezeichnungen | CodeSystem (FA-Schlüssel) |
| **NBKZ** | Bewegungs-/Betriebskennzeichen-Katalog | BEWTY/BWART-Klartext (Aufnahme/Verlegung/…) | CodeSystem |
| **NKDI** | Katalog Diagnosearten/-verwendung | HD/ND/Aufnahme-/Entlassdiagnose-Klartext | CodeSystem (Condition.category) |
| **NLOC / NLCO** | Standort-/Location-Stammdaten | Gebäude/Station/Zimmer-Auflösung | Location |
| **NPER** | Personen-/Personalbezug IS-H (behandelnde Person) | Practitioner-Auflösung ohne HR-Schema | Practitioner |
| **NBSNR / NKBVLANR** | Betriebsstätten-Nr / LANR (KV-Arztnummer) | eindeutige Arzt-/BS-Kennung für ambulante Analytik | Identifier an Practitioner/Location |
| **NGEB** | Gebührenordnung/Katalog (Leistungskatalog-Bezug) | Leistungsklartext zu NLEI-Ziffern | ChargeItemDefinition (COUNT? — kann groß sein) |
| **NTPK / NTPKD / NTPT / NTPZ** | Tarif-/Preis-/Punktwert-Kataloge | nur falls Erlös-Analytik gewünscht (Tier 3) | ChargeItemDefinition |

Nicht in der DB und extern zu ergänzen (wie im Schwesterprojekt): vollständige Register
**ICD-10-GM, OPS, LOINC, ATC**. Wir ziehen die im Haus verwendeten Kataloge aus den
o. g. Tabellen und mappen gegen die offiziellen Register (BfArM/Dimdi-Downloads).

**Warum zuerst:** Die Marts und die MCP-Antworten in v0.1 zeigen heute Rohcodes
(FALAR=1, ORGFA=KARD, DKEY1=I50.14). Erst die Referenzschicht macht daraus lesbare
Auswertungen und verständliche LLM-Antworten. Aufwand gering (kleine Tabellen, full-load),
Nutzen hoch.

---

## 3. §301-Datenstrom (NC301*, Priorität 2)

Der §301-Satz ist der zwischen Krankenhaus und GKV ausgetauschte, normierte Datensatz.
In IS-H als NC301-Familie abgelegt. Für Sekundärnutzung wertvoll, weil bereits
qualitätsgesichert und semantisch eindeutig.

| Tabelle | §301-Segment (Bedeutung) | Analytik-Nutzen |
|---|---|---|
| **NC301** | Kopf/Nachrichtensteuerung | Klammer je Übermittlung |
| **NC301A** *(falls vorh.)* / **NC301E** | Aufnahmesatz (AUFN) | Aufnahmeanlass, -grund, -datum, Fachabteilung |
| **NC301D / NC301DX** | Diagnosen (§301-Diagnosesegment) | HD/ND GKV-konform, oft sauberer als NDIA-Roh |
| **NC301P** | Prozeduren (§301) | OPS GKV-konform |
| **NC301R** | Rechnung/Entgelt | Entgeltarten, DRG-Abrechnung, Erlös |
| **NC301E / NC301V** | Entlassung/Verlegung | Entlassgrund (§301-Schlüssel 3xx), -datum |
| **NC301KTR** | Kostenträger-Bezug | Kassenzuordnung des §301-Vorgangs |
| **NC301T / NC301TX** | Textsegmente/Bemerkungen | Zusatzinfo |
| **NC301M** | Mahnung/Storno-Status | Vollständigkeit/Storno |
| **NC301B / NC301CEX / NC301I / NC301S / NC301W** | weitere Segmente (Zahlung, Info) | Tier 3 |
| **NCIR** | §301-Kommunikations-/Eingangsregister | Übertragungsstatus |

FHIR-Abbildung: NC301E→Encounter (Aufnahme/Entlassung-Anreicherung + `dischargeDisposition`
aus Entlassgrund), NC301D→Condition (Alternative/Validierung zu NDIA), NC301R→Claim/
ChargeItem (nur Analytik). **Empfehlung:** §301 als **Validierungs- und Anreicherungsquelle**
neben NDIA/NICP, nicht als Ersatz — Golden-Record-Abgleich beider Wege.

---

## 4. i.s.h.med-Auftragswelt (N1*) und Zusatzdoku (N2*), Priorität 3

Selektiv. Vieles in N1* sind Customizing-/Typ-/Steuertabellen (Suffixe TYP, T, A, DEF,
STA, TR) — die gehören in die Referenzschicht, nicht in den Bewegungsexport.

Nützliche Bewegungsdaten:
| Tabelle | Inhalt | FHIR |
|---|---|---|
| **N1CORDER** (v0.1) + **N1CORDF** | klinischer Auftrag + Auftragsfelder | ServiceRequest |
| **N1ANF** (v0.1) + **N1ANFTYP** (Ref) | Leistungsanforderung + Anforderungstyp | ServiceRequest |
| **N1LSSTA / N1LSSTT / N1LSSTZ** | Leistungsstatus/-status-Zeitpunkte | ServiceRequest.status + Provenance |
| **N1PRBEW** | Prozess-/Bewegungsbezug des Auftrags | Verknüpfung Auftrag↔Bewegung |
| **N1MEORDER** | Medikations-/Maßnahmenauftrag | ServiceRequest / MedicationRequest (COUNT?) |
| **N1TA / N1TAT** | Tätigkeiten/Tätigkeitstypen | Procedure-Anreicherung |
| **N1XLEI** | Auftrag↔Leistung-Verknüpfung | ChargeItem-Bezug |

Steuer-/Typtabellen → Referenzschicht (Klartext für Auftragsarten, Anforderungstypen,
Statuscodes): N1CORDTYP(T/A), N1ANFTYP, N1LSSTT, N1DESEL(T), N1FAT, N1STGR.

Nützliche N2-Doku:
| Tabelle | Inhalt | FHIR |
|---|---|---|
| **N2OPDIAGNOSEN** | OP-Diagnosen (strukturiert) | Condition (Kategorie surgical) — wertvoll, da Arztbriefe leer |
| **N2LABOR** (v0.1) + **N2LABOR001** | Laborwerte (+ Ergänzungstabelle) | Observation |
| **N2ZEITEN / N2ZTPDEF** | strukturierte Zeitpunkte (OP-Zeiten etc.) + Definition | Procedure.performedPeriod / Encounter-Zeiten |
| **N2TEXT** (v0.1) | med. Texte | FTS (nicht FHIR) |
| **N2DTT / N2PMDETEXT** | Dokumenttext-Typen / PME-Texte | DocumentReference-Anreicherung |
| **N2CLIM_OBSVS** | klinische Observations/Messwerte | Observation (COUNT? — potenziell groß) |

N2DWSWL_* (Worklist-Dashboards), N2INPA_SUGGEST* (Eingabevorschläge), N2ANKER
(Text-Anker) → **irrelevant** für Sekundärnutzung (UI-/Steuerungsartefakte).

---

## 5. Weitere Kern-Ergänzungen (Priorität 2–3)

| Tabelle | Inhalt | Nutzen | FHIR |
|---|---|---|---|
| **NDIP** (v0.1 erwähnt) | Diagnose-Position/-verwendung | HD/ND-Klassifikation | Condition.category |
| **NICP2** | Prozedur-Ergänzung/-Detail | OPS-Zusatzattribute | Procedure-Anreicherung |
| **NGEB** | Gebühren/Leistungskatalogbezug | Leistungsklartext | ChargeItemDefinition |
| **NFFZ / NFPZ** (v0.1) | Fall-Folge-/Versicherungszeiträume | Coverage-Zeiträume | Coverage |
| **NPAE** | Patient-Ergänzung (erweiterte Stammdaten) | Zusatzattribute Patient | Patient-Anreicherung |
| **NPAP / NPAPIX / NPIX / NPIR** | Patienten-Index/-Verweise (MPI-artig) | Dublettenauflösung, PATNR-Verweise | Patient.link |
| **NAMB** | ambulante Falldaten | ambulante Analytik | Encounter (ambulant) |
| **NTMN** | Termine (klassisch IS-H) | Terminanalytik (neben NAPP) | Appointment |
| **NAPX / NAPX_FAL / NAPX_DIA / NAPX_ICP / NAPX_BEW / NAPX_DRG** | **Archiv-/Auslagerungstabellen** (Kopien FAL/DIA/ICP/BEW/DRG) | historische Fälle, falls Kern nur Live-Daten hält | wie Basistab. (COUNT? — prüfen, ob Altfälle nur hier liegen!) |
| **NEHC / NEAC** | eHealth-/eCard-Bezug | Versicherten-/eGK-Kontext | Coverage-Anreicherung |
| **NKSP** | Sperren/Kennzeichen | Datenschutz-Flags (z. B. VIP/Sperrvermerk) | **wichtig**: Flag für Ausschluss aus Analytik |

**Datenschutz-Flags — KORRIGIERT (Verifikationsrunde 2):** Sperrvermerke/VIP liegen
NICHT in NKSP (das ist Kostenübernahme-Splitting), sondern direkt in **NPAT.VIPKZ**
(VIP, 52 Fälle), **NPAT.RISKF** (Risiko, 42k), **NPAT.STORN/INACT**. Diese Flags müssen
als Ausschluss- bzw. Maskierungsregel in die Privacy-/Gate-Schicht einfließen, bevor
Daten in Analytik oder MCP gelangen. Neue Anforderung an §6 Datenschutz.

**NAPX*-Familie — VERIFIZIERT (15.07.2026), Korrektur der v0.2-Annahme:**
NAPX ist **keine** Archiv-/Auslagerungstabelle, sondern das **Fallzusammenführungs-
Konstrukt** nach FPV/KFPV. NAPX = Kopf (APXNR), NAPX_FAL = Verknüpfung APXNR↔FALNR mit
`LEAD` (führender Fall) und `REASON` (Zusammenführungsgrund). NAPX_DIA/ICP/BEW/DRG halten
die zusammengeführten Detaildaten für die DRG-Neugruppierung des Gesamtfalls.
Live: 21.991 Zusammenführungen / 45.081 Fallverknüpfungen. REASON: WA (Wiederaufnahme),
KO (Komplikation), WP (geplant), RV (Rückverlegung), FW (Fehlbelegung). Details und
Zahlen in `docs/VERIFY_RESULTS.md §2`.
**Konsequenz (bereits umgesetzt):** Das Graphmodell erhält Knoten `Fallzusammenfuehrung`
und Kante `ZUSAMMENGEFUEHRT_IN` — die echte, GKV-rechtliche Wiederaufnahme-Beziehung
ersetzt die heuristische 30-Tage-Kante (die bleibt nur für Fälle ohne formale
Zusammenführung). Zusätzlich: NPAT.RFPAT liefert die **Patienten**-Zusammenführung
(26.388 Fälle) als Patient.link (replaces).

---

## 6. Irrelevant / bewusst ausgeschlossen

Reine Steuer-, UI-, Sync- oder Systemtabellen ohne Sekundärnutzungswert:
N1SYNC_SYSTEMS, N1NRSPE/N1NRSPH (Nummernkreise), N1PLATH (Plausibilität), N1COMPA/
N1COMPDEFA (Komponenten-Customizing), N2DWSWL_* (Worklists), N2INPA_SUGGEST* (Vorschläge),
N2ANKER, NSHIFT/NSHIFT_ID (Schichtplanung), NLWARTE_003 (Wartelisten-Instanz), NSTREM,
NRSF, NPTW, NPFO, NPOB, NPCP, NO2K, NMBG, NMATV, NWATFADR/NWATFAPF, NWPG, NLAZ, NLICZ,
NLKZ, NLLZ, NVVF/NVVP, NTSI/NTSP/NTST, NBAU, NDOCA/NDOC_ZNA/NBEW__ct_ZNA (ZNA-Instanz/
Anhang-Varianten — nur falls ZNA-Analytik gewünscht). Alle `*__ct__bak*` sind Qlik-
Backup-Artefakte und werden generell ignoriert.

Diese Liste ist eine Arbeitshypothese aus den Tabellennamen; bei Bedarf im Einzelfall
per `describe_table` + Stichprobe gegenprüfen.

---

## 7. Verifikationsskript (vor Umsetzung ausführen)

Sobald der mssql-MCP wieder erreichbar ist, diese drei Punkte klären:

**A — Füllstände aller relevanten Neuzugänge:**
```sql
SELECT t.name AS tabelle, SUM(p.rows) AS zeilen
FROM replicate.sys.tables t
JOIN replicate.sys.schemas s ON t.schema_id=s.schema_id
JOIN replicate.sys.partitions p ON t.object_id=p.object_id AND p.index_id IN (0,1)
WHERE s.name='sap' AND t.name IN
 ('NGPA','NKTR','NKSK','NKSD','NKSP','NFKL','NBKZ','NKDI','NLOC','NLCO','NPER',
  'NBSNR','NKBVLANR','NGEB','NC301','NC301D','NC301DX','NC301E','NC301P','NC301R',
  'NC301V','NC301KTR','NCIR','N2OPDIAGNOSEN','N2ZEITEN','N2CLIM_OBSVS','N1CORDF',
  'N1LSSTA','N1PRBEW','N1MEORDER','N1XLEI','NICP2','NPAE','NAMB','NTMN',
  'NAPX_FAL','NAPX_DIA','NAPX_ICP','NAPX_BEW','NEHC')
GROUP BY t.name ORDER BY zeilen DESC;
```

**B — Arztbrief-/Dokumentkategorien (leer?):**
```sql
-- Verteilung der Dokumentkategorien in NDOC; sind Entlassbriefe/Epikrisen vorhanden?
SELECT TOP 50 DOCKA, COUNT(*) n FROM sap.NDOC GROUP BY DOCKA ORDER BY n DESC;  -- VERIFY Spalte DOCKA
-- Wieviel echter Volltext steckt in N2TEXT (mittlere Länge)?
SELECT COUNT(*) zeilen FROM sap.N2TEXT;
```

**C — Archiv-Auslagerung NAPX (Historie vollständig im Kern?):**
```sql
SELECT (SELECT MIN(BEGDT) FROM sap.NFAL)     AS nfal_min,
       (SELECT MIN(BEGDT) FROM sap.NAPX_FAL) AS napx_min;  -- VERIFY Spalten
-- Wenn napx_min deutlich < nfal_min: Altfälle liegen NUR in NAPX -> beide entladen.
```

---

## 8. Auswirkungen auf die Umsetzung (v0.1 → v0.2)

Was v0.1 (im Claude-Code-Rollout laufend) NICHT bricht — reine Ergänzung:

1. **Neues Modul `reference/`** (analog Schwesterprojekt): `build_reference.py`,
   `reference_mappers.py`, `terminology.py`. Läuft als eigener, seltener Job (full-load),
   schreibt Lookup-Tabellen `ref_*` in DuckDB + FHIR-Terminologie nach `silver/fhir/`.
2. **`config/tables.yaml` erweitern** um Tier-1-Referenz (NGPA, NKTR, NORG-Texte, NFKL,
   NBKZ, NKDI, NLOC/NLCO, NPER) und Tier-2-§301 (NC301D/E/P/R/V/KTR). Enum-Auflösung in
   den Mappern ersetzt die hartkodierten Dicts (GESCHLECHT/FALLART/BEWEGUNGSART) durch
   Lookups aus `ref_*`.
3. **Marts anreichern:** OE-Namen, Kassennamen, Fachabteilungs- und Entlassgrund-Klartext
   in `gold.*`-Views. Neue View `gold.entlassgrund` aus NC301E/V.
4. **MCP:** neues Tool `resolve_code(system, code)` (schlägt Klartext aus `ref_*` nach) +
   `patient_360` liefert künftig Klartext statt Rohcodes.
5. **Privacy/Gate:** NKSP-Sperrvermerke als harte Ausschluss-/Maskierungsregel ergänzen.
6. **Neue Condition-Quelle:** N2OPDIAGNOSEN (OP-Diagnosen) — kompensiert die dünnen
   Arztbriefe.
7. **Golden-Record-Test erweitern:** NDIA vs. NC301D für denselben Fall gegenprüfen.

Kein Umbau der Bronze/Silver/Gold-Architektur, keine Änderung an dbsource/privacy/keyset/
state. Die Erweiterung ist additiv und Tier-gesteuert.

## 9. Empfohlene Reihenfolge

1. Verifikationsskript §7 laufen lassen, Füllstände + Arztbrief-Frage + NAPX klären.
2. Referenzschicht (§2) bauen — sofort spürbarer Mehrwert für Dashboard + MCP.
3. §301-Diagnosen/Entlassgründe (§3) als Anreicherung + Validierung.
4. N2OPDIAGNOSEN + N1-Auftragsstatus (§4) selektiv.
5. NAPX-Historie nur, falls §7-C zeigt, dass Altfälle dort exklusiv liegen.
