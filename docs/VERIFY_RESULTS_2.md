# SAP_FIHR — Verifikationsrunde 2 (breiter N-Tabellen-Scan)

Stand 15.07.2026, `replicate` read-only, TOP-100-stabil. Ergänzt/korrigiert v0.2 und
`VERIFY_RESULTS.md`. **Enthält mehrere Korrekturen falscher v0.2-Annahmen.**

## 1. Füllstände (verifiziert)

| Tabelle | Zeilen | Einordnung (verifiziert) | Verwendung |
|---|---:|---|---|
| NLCO | 72.424.425 | **Leistungs-Controlling / IBLV** (CO) | ✗ irrelevant (Kostenrechnung) |
| NBKZ | 13.732.942 | **Beleg-Zuordnung je Fall** (FALNR↔BELNR) | ○ Join-Hilfe, kein FHIR |
| NKSP | 12.522.903 | **Kostenübernahme-Splitting/Pflegesatz** | △ Tier 3 (Abrechnungsdetail) |
| NTMN | 11.520.761 | Termine (klassisch IS-H) | △ Appointment (Tier 2) |
| NKSK | 9.566.537 | **Kostenübernahme/Versicherung je Fall** | ✔ **Coverage (Tier 1)** |
| NKSD | 6.778.952 | Kostenübernahme-Detail | △ Coverage-Anreicherung |
| NADR | 6.107.954 | Adressen | ✔ Patient/Org-Adresse |
| NFKL | 5.721.988 | **Fall-Klassifikation** (nicht FA-Katalog!) | △ Encounter-Anreicherung |
| NPIR | 3.427.723 | Patienten-Index (Referenz/Verweis) | ✗ Suchindex |
| NPIX | 1.563.445 | **Patienten-Namensindex** (phonetisch) | ✗ Suchindex |
| NPAE | 1.464.271 | Patient-Ergänzung (1:1 zu NPAT) | ○ Patient-Anreicherung |
| NPAP | 1.445.694 | **Patient-Stammdaten-Historie** (Snapshots) | △ Historisierung (sensibel) |
| NEHC | 1.085.061 | **eGK-Kartendaten** (ICCSN, Einlese-Historie) | △ Coverage-Anreicherung (sensibel) |
| NC301E | 581.573 | **§301-Meldungs-/Fehlerprotokoll** (nicht Aufnahme!) | ✗ Übertragungs-Log |
| NC301D | 496.349 | **§301-Dateiübertragungsprotokoll** (nicht Diagnose!) | ✗ Übertragungs-Log |
| NKDI | 390.504 | Katalog Diagnosearten | ✔ Referenz (CodeSystem) |
| NGPA | 261.210 | Geschäftspartner | ✔ Referenz P1 |
| NPER | 236.106 | Personen (= NGPA PERS-Sicht) | ✔ Practitioner |
| NBSNR | 148.535 | Betriebsstätten-Nr | ○ Identifier |
| NAMB | 142.498 | ambulante Falldaten | △ Encounter ambulant |
| NADR2 | 141.035 | Adress-Ergänzung | ○ |
| NGEB | 61.110 | **Geburtendaten/Perinatal** (nicht Gebührenkatalog!) | ✔ **Observation (Tier 2)** |
| NKTR | 17.336 | Kostenträger | ✔ Referenz P1 |
| NBAU | 4.541 | **Baustruktur/Gebäude** (Koordinaten) | ✔ **Location (Tier 2)** |
| NC301KTR | 4.481 | §301-Kostenträger-Log | ✗ |
| NORG | 2.406 | Organisationseinheiten | ✔ Organization/Location |
| NC301P | 123 | §301-Protokoll (fast leer) | ✗ |
| NLOC | 0 | leer | ✗ |
| NEAC | 0 | leer | ✗ |
| NC301R | 0 | leer | ✗ |

Legende: ✔ Kern/wertvoll · △ optional Tier 2/3 · ○ Anreicherung/Join · ✗ irrelevant

## 2. Korrekturen gegenüber v0.2 (wichtig!)

1. **NC301-Familie ist KEIN §301-Nutzdatenstrom**, sondern die §301-**Kommunikations-/
   Übertragungsverwaltung** (Dateiprotokolle, Fehler-/Meldungslogs). NC301D =
   Dateiübertragung, NC301E = Meldungsprotokoll (MSGTY/MSGNR/MSGV1-4), NC301R leer.
   → **Gesamte NC301-Familie aus der Registry entfernen.** Die fachlichen Diagnosen/
   Prozeduren liegen in NDIA/NICP (bereits im Kern). §301-Diagnose-Validierung entfällt.
2. **NKSP ≠ Sperrvermerke.** NKSP ist Kostenübernahme-Splitting (Pflegesatz-Positionen).
   Sperr-/VIP-Kennzeichen liegen in **NPAT.VIPKZ/RISKF** (bereits erfasst). → NKSP-Eintrag
   in der Registry als Tier-3-Abrechnung umwidmen, NICHT als Datenschutz-Flag.
3. **NFKL ≠ Fachabteilungskatalog.** Ist Fall-Klassifikation (5,7 Mio). FA-Klartext kommt
   aus NORG bzw. dem OM-Baum. → NFKL aus Referenzschicht raus.
4. **NKSK ist die zentrale Coverage-Quelle** (Kostenübernahme je Fall, 9,5 Mio) —
   besser als das bisher gesetzte NFPZ. Fall→KOSTR mit Gültigkeit BEGDT/ENDDT.
5. **NGEB = Geburten-/Perinataldaten**, nicht Gebührenkatalog. Neuer Observation-Mapper.
6. **NBAU = Gebäude/Baustruktur** mit Geokoordinaten → Location-Hierarchie über NORG.

## 3. Neue verwertbare Quellen (in Registry aufnehmen)

**NKSK → Coverage (Tier 1):** MANDT/BELNR/FALNR/KOSTR, KSTYP/KSART (Kostenträgertyp),
BEGDT/ENDDT (Gültigkeit), BSTAT. KOSTR→NKTR (Kassenname). KOSTR='0009999999' =
Selbstzahler/Sammelplatzhalter. Live: durchweg Quartalsgültigkeit, KSTYP='N' Normalfall.

**NGEB → Observation (Tier 2, Geburtshilfe):** FALN1/FALN2 (Mutter-/Kind-Fall),
GBDAT/GBTIM (Geburt), GBGEW (Gewicht), GBGRO (Länge), HEAD_SIZE (Kopfumfang),
BIRTH_POS (Lage), MEHRL (Mehrling), BIRTH_ANO (Anomalie), SEX_SPECIAL. → Neugeborenen-
Vitalparameter + Verknüpfung Mutter↔Kind-Fall. 61.110 Geburten.

**NBAU → Location (Tier 2):** BAUID/BAUTY/BAUNA (Gebäude), XKOOR/YKOOR (Koordinaten),
BREIT/LAENG, ADRNR. Physische Standorthierarchie oberhalb der OE (NORG).

**NEHC → Coverage-Anreicherung (Tier 3, sensibel):** EGK_ICCSN (Kartenseriennr),
READ_DATE, CARDVALID, BEGDT/ENDDT, PATNR. eGK-Einlese-Historie. Datenschutz beachten.

**NPAP → Patient-Historie (Tier 3, sensibel):** vollständige Stammdaten-Snapshots
(PAPID, Name/Adresse/RVNUM/PASSNR). Nur für Historisierung; unterliegt voller De-ID.

## 4. Unverändert bestätigt (aus Runde 1)

NPAT/NFAL/NBEW/NDIA/NICP/NGPA/NKTR + NAPX-Fallzusammenführung wie in `VERIFY_RESULTS.md`.
NLOC leer → Location kommt aus NORG + NBAU statt NLOC.

## 5. Endgültige Tabellen-Klassifikation für den Export

**Tier 1 (Kern + Referenz):** NPAT, NFAL, NBEW, NDIA, NICP, N2LABOR, NDOC, N2TEXT,
NORG, NADR, NKSK(→Coverage), NGPA, NKTR, NKDI, NPER.
**Tier 2 (Analytik/Spezial):** NDRG, NLEI, NLEM, N1CORDER, NAPP/NTMN, N2OPDIAGNOSEN,
NGEB(→Geburt), NBAU(→Location), NAPX/NAPX_FAL(→Zusammenführung), hrp.HRP1000/1001.
**Tier 3 (optional/sensibel):** NKSP, NKSD, NEHC, NPAP, NAMB, NPAE.
**Irrelevant (nicht exportieren):** NLCO, NBKZ, NPIX, NPIR, NFKL, gesamte NC301-Familie,
NLOC/NEAC (leer), sowie die in CONCEPT_EXT §6 gelisteten Steuer-/UI-Tabellen.
