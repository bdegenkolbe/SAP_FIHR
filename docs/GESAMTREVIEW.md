# Gesamtreview — Tabellenbestand + Konzeptkonsistenz nach Integration R8–R16

Stand 17.07.2026 · Anlass: Integration des `sapfhir-paket` (lokale Verifikationsrunden
R8–R16 gegen `10.50.8.250/Replicate`) in den Repo-Stand (Remote-Runden R1–R4 +
Altbestand-Analyse). Dieses Dokument ist die angeforderte **Gesamtprüfung aller
vorhandenen Tabellen** und die **Konsistenzprüfung des Gesamtkonzepts**.

---

## 1. Wo das Projekt jetzt steht (eine Seite)

- **Registry:** 79 Tabellen in `config/tables.yaml` (76 aus R8–R16 mit live
  verifizierten PKs + 3 Altbestand-Kataloge TN14U/TN14W/TN24T), Statusmodell
  je Tabelle nach `docs/Analyse_Datenbank.md` §2.
- **Mapper:** 23 Mapper (R16-Stand) für 17 FHIR-Ressourcentypen inkl. Account
  (NAPX), DiagnosticReport/Observation (Labor-Familie), AllergyIntolerance/Flag
  (NRSF-Routing), ServiceRequest, Practitioner-Merge (NGPA≡NPER), MedicationRequest.
- **Pipeline:** Mapper → patientenfixer Date-Shift (Pipeline-Schritt, kein
  Doppel-Shift bei NPAT/NFAL) → `normalize_resource()` (ISO-8601, Europe/Berlin)
  → NDJSON + Index + Provenance; Kontext-Lookups (FALNR→PATNR, FALNR→APXNR,
  NKDI-Kodetexte, N2LABOR-Kopf-Join) sind verdrahtet.
- **Verbindliche Methode:** `docs/Analyse_Datenbank.md` (Dreiklang sapdatasheet →
  Schema live → Daten live; Verkryptungsregeln; NPAT-Breitensuche) — gilt für jede
  weitere Session, lokal wie remote.
- **Verprobung:** Demo-Seed erzeugt den R16-Schemastand (ENDDT, DVS-Dokumente,
  Labor-Kopf/Werte, NAPX) und läuft die komplette Pipeline; 76 Tests grün.

## 2. Gesamtprüfung Tabellenbestand

### 2.1 Registry-Kern (auditierte 76)
Alle PKs aus R9 per Uniqueness-Test bestätigt; die wichtigsten Korrekturen sind im
Code nachgezogen:

| Korrektur | Konsequenz im Repo |
|---|---|
| **NFAL: Fallende = ENDDT** (ENDAT = Entbindungsdatum!); Sentinel 0101-01-01 = offener Fall (23 %!) | Mapper (`in-progress`), Marts (`gold.verweildauer`), MCP-Views, Graph, Seed, Spaltenkatalog umgestellt |
| **NDOC: DVS-Schlüssel** [MANDT,DOKAR,DOKNR,DOKVR,DOKTL,LFDDOK]; DOCID/DOCKA/DOCDT existieren nicht | Mapper neu (R8), NDOC.yaml/N2TEXT.yaml neu, FTS auf `TXT` + synthetische Dok-ID, mcp.dokument neu |
| **Labor = N2LABOR (Kopf) + N2LABOR001 (322 Mio Werte)**; Werte sind Freitext | DiagnosticReport+Observation mit robusten Parsern (Komparatoren, Dezimalkomma, Interpretation); Kopf-Join in Pipeline und mcp.labor |
| **NFPZ = Fall↔Person** (nicht Coverage!) → Encounter.participant | Registry + Mapper (R12); Coverage kommt aus NKSK (+NVVP-KVNR gehasht) |
| **NKDI = ICD-Textkatalog** [MANDT,SPRAS,DKAT,DKEY] | kodetext-Lookup → `coding.display` |
| NDIP=[MANDT,DIPNO], NDRG englische Spalten, NLEI/NLEM=[MANDT,LNRLS], NAPP=[MANDT,LNRAPP], NPER ohne EINRI, NADR mit **ADROB im PK** | Registry verifiziert; Merge-Layer prüft PK-Spalten jetzt gegen die realen Bronze-Spalten (Teil-PK mit Warnung statt Absturz) |
| **GPART == PERNR == PHYSNO (236.114, 1:1)** | EIN Practitioner-ID-Schema; NGPA+NPER-Merge als Pipeline-Aufgabe dokumentiert |
| NC301-Familie rehabilitiert: **NC301S/M/V/W/P sind die §301-Meldedaten** | Registry differenziert; NC301M/V/W mit De-ID-Pflicht (EDIFACT-NAD-Klartext!) |
| Tote Felder (R16): NICP.OPART, NBEW.UNFAV/VGNREF/NFGREF, NFAL.FACHR/ENDTYP, NDIA.DIASI | Bewegungskette per ORDER BY BWIDT/BWIZT (Graph macht das bereits); Mapper defensiv |

### 2.2 DIAS-Abdeckungsdiff (Analyse_Datenbank §5, automatisiert)
77 im DIAS-Baum referenzierte `sap.*`-Tabellen, davon 23 in der Registry. Die 54
„Lücken" zerfallen in vier bewusste Kategorien:

1. **Registry-Kandidaten (aufnehmen, Tier 2/3):** NAPX_BEW/NAPX_DIA/NAPX_ICP/NAPX_DRG
   (Zusammenführungs-Detail für DRG-Neugruppierung), TNDRG (DRG-Katalog), NTMN
   (Termine, 11,5 Mio), NLCO/NCIR (nur-Analytik, R14 eingeordnet), TN15S/TFACD/THOC
   (Kataloge). → als nächste Warteschlangen-Einträge nach Analyse_Datenbank §2.
2. **Offener Arztbrief-Pfad:** SOOD/SRGBTBREL (SAP-Office) — bereits offener Punkt;
   Dreiklang-Audit im Lastfenster nötig, bevor DocumentReference-Anreicherung.
3. **Hauseigene RKT-Fakturierung:** 24× ZNRKT_* — reiner **Analytik-Pfad**
   (E-Statistik/RKT), kein FHIR; wird über denselben Bronze-Mechanismus versorgt,
   sobald der Analytik-Abnehmer es braucht (fhir: null, Tier 3).
4. **FI/CO/MM-Welt:** BSEG/BKPF/COEP/COSS/COEJ/COBK/EKBE/EKBZ/EKKN/EINE/EIPA/MSEG/
   VBRK/ANLA/AUFK/AUSP/KSSK — Finanz-/Logistikdomäne außerhalb des klinischen
   Sekundärnutzungs-Scopes. Bewusst NICHT in der Registry; falls Erlös-Analytik
   gewünscht wird, ist das ein eigenes Arbeitspaket mit eigener DSFA-Betrachtung.

**Damit ist das DIAS-SOLL vollständig klassifiziert — es gibt keine unbewerteten
Lücken mehr,** nur bewusst priorisierte.

### 2.3 Nicht-SAP-Quellen (aus dem DIAS-Baum)
COPRA5/COPRA6 (Medikation/Vitalwerte — IS-H-seitig leer, N1MEORDER=0!), HCM/PEP
(Personal), Mirth/HL7, Referenzdaten. Das sind **eigene Quellsysteme** — im
Gesamtkonzept als künftige Adapter geführt, nicht als IS-H-Tabellen.

## 3. Konsistenzprüfung Gesamtkonzept

### 3.1 Aufgelöste Spannungen
- **NAPX: Graph-Kante vs. FHIR-Account.** Beides bleibt, sauber getrennt: Im
  **FHIR-Pfad** gilt R11 (Account-Klammer, kein replaces/partOf — Medizin ≠
  Abrechnung). Im **Analytik-Graph** bleibt die Kante `FUEHRT_ZUSAMMEN` (plus
  30-Tage-Heuristik) — der Graph ist Auswertungs-, nicht Austauschmodell.
  Auswertungsregel überall: klinisch je Encounter, Erlös je Account.
- **NC301:** Runde 2 (komplett raus) war falsch, DIAS-Analyse (nur NC301S) zu eng —
  R10 klärt: S/M/V/W/P sind Nutzdaten. CONCEPT §19.2 gilt mit dieser Präzisierung.
- **Lookup-Schicht vs. kodetext:** `fhir/lookups.py` bleibt für Gold/MCP-Klartexte
  (TN14T/NORG/NKTR); die FHIR-Pipeline nutzt den NKDI-kodetext-Lookup direkt.
  Nicht replizierte Kataloge (TN14K/O, N2DT, TN26B/D) → Rohcode-only (verlustfrei).
- **Datums-Pipeline:** Der frühere Zustand „Shift teils im Mapper, teils gar nicht"
  ist durch die dreistufige Kette (Mapper roh → Shift → normalize) ersetzt; der
  Pipeline-Shift lässt NPAT/NFAL aus (Mapper-intern) — per Test abgesichert.
- **HRP-Schema:** auf Anweisung ausgeklammert; PA0002/HRP1000/1001 bleiben als
  Tier-3-Platzhalter in der Registry, werden aber nicht bearbeitet.

### 3.2 Architektur bestätigt, ein Zielbild geschärft
Die Medaillon-Architektur (Keyset+CDC → bronze_current+Compaction → FHIR/Gold →
MCP/Graph) trägt alle neuen Erkenntnisse ohne Umbau. **Geschärft aus dem Altbestand
(Analyse_Datenbank §6.2):** Trennung Echtzeit- vs. Historisierungs-Strang —
unser Echtzeit-Strang existiert (CDC→bronze_current→FHIR); der Historisierungs-
Strang (SCD2 aus `__ct`+**CDPOS/CDHDR**, Lastfenster) ist als Zielarchitektur
dokumentiert und durch `_delta_archive/` vorbereitet, aber bewusst nicht gebaut —
CT-Lücken sind real (Altbestand-Befund), daher ist CDPOS-Abgleich Pflicht, sobald
Historisierung gebraucht wird.

### 3.3 Datenschutz nachgeschärft
Neu aus R-Serie: **Verkryptungsregel** (Analyse_Datenbank §4) gilt für jede
DB-Sitzung; NVVP.VERNR (KVNR) läuft über `priv.hash_id`; NC301M/V/W tragen
EDIFACT-Klartext (NAD-Segmente) → De-ID-Pflicht vor jeder Ausleitung;
NFAL.STASP-Statistiksperre bleibt als Analytik-/MCP-Ausschluss aktiv.

## 4. Konsolidierter Backlog (ersetzt verstreute Listen)

| # | Punkt | Quelle | Pfad |
|---|---|---|---|
| 1 | ~~NGPA+NPER-Merge~~ **erledigt** (FULL OUTER JOIN, dedupliziertes identifier-Set) | R13 | — |
| 2 | NICP↔N1LSTEAM-Joinpfad (LNRLM leer; Kandidat N2OPDIAGNOSEN.LNRLS) + Fill-Audit NDOC/N2LABOR | R15/R16 | **Lastfenster (mssql)** |
| 3 | ~~Registry-Aufnahme NAPX_BEW/DIA/ICP/DRG + NTMN + TNDRG~~ **erledigt** (PKs noch # VERIFY → mssql-PK-Check offen) | Review §2.2 | mssql (PK-Check) |
| 4 | SOOD/SRGBTBREL-Audit (Arztbrief-Pfad) | DIAS/R-Serie | **Lastfenster (mssql)** |
| 5 | ~~ref_*-Loader~~ **erledigt** (`lookups.build_ref_tables` + Klartext-Marts + MCP-Tool `resolve_code`); offen bleibt der Qlik-Antrag für TN14K/O, N2DT, TN26B/D | §8 Paket | Qlik-Antrag |
| 6 | NFFZ-REFA-Katalog klären (Q/T/S-Deutung) | R15 | mssql/Fachbereich |
| 7 | Echtzeit-/Historisierungs-Trennung als eigener Batch-Strang (CDPOS) | §6.2 | Konzept → später |
| 8 | COPRA5/6-Adapter für Medikation/Vitalwerte | R10/R14 | neues Arbeitspaket |
| 9 | ~~vvp-/personal-/bewegungen-Lookups~~ **erledigt** (LIST(STRUCT)-Broadcast-Joins); offen bleibt `team` (haengt am NICP↔N1LSTEAM-Joinpfad, #2) | Review | mit #2 |
| 10 | ~~DIAS-Abdeckungsdiff als DQ-Job~~ **erledigt** (`_meta.dias_coverage` + Dashboard-Kachel) | §5 Paket | — |

## 5. Prüfergebnis

Das Gesamtkonzept ist nach der Integration **konsistent**: Methode
(Analyse_Datenbank), Registry (79 Tabellen, klassifiziert), Mapper (R16),
Pipeline (Shift/Normalize-Reihenfolge), Analytik (Marts/MCP/Graph) und
Betrieb (CONCEPT §13/§14, DEPLOYMENT) widersprechen sich nicht mehr; alle
bekannten Deutungskonflikte sind entschieden und dokumentiert. Die Restarbeit
ist im Backlog §4 priorisiert — die Punkte 2, 4 und 6 brauchen die lokale
mssql-Session, alles andere ist ohne DB machbar.
