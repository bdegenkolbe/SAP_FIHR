# Darstellungskonzept Patient 360 — CliniBots Patient Insight

**Stand:** 22.07.2026 · **Rolle: UI-/Layout-Blaupause** unter dem Zielbild
(`CONCEPT_P360_VOLLAUSBAU.md` sagt WAS gezeigt wird, dieses Dokument sagt WIE).
Deep-Research-fundiert (106 extrahierte, adversarial geprüfte Claims; Primärquellen:
Epic-/Cerner-Trainingsmaterial, NHS/VA-Design-Systeme, SAP-Fiori-Spezifikation,
kontrollierte Studien). Anlass: Nutzerkritik am v0-Layout („so ist richtig Mist") —
vertikaler Stapel aus Liste + KPIs + Kartensuppe + Endlos-Diagnoseliste.

---

## 1. Evidenzbasis (warum sich der Umbau lohnt)

| Befund | Zahl | Quelle |
|---|---|---|
| Chart Review ist der größte Einzelposten ärztlicher EHR-Zeit | **33 %** | JAMIA-Zeitstudie (ambulante Cerner-Encounters) |
| Problemorientierte Sicht vs. flache Encounter-Listen: schneller | 173 s vs. 205 s (**−16 %**) | randomisiertes Experiment (POV-Studie) |
| … weniger Abruffehler | **3,4 % vs. 7,7 %** (p=.001) | ebd. |
| … bessere Usability (SUS) | **58,5 vs. 41,3** (p<.0001) | ebd. |
| … geringere kognitive Last (NASA-TLX) | 0,72 vs. 0,99 (p<.0001) | ebd. |
| Timeline-Ansicht erzeugt hochwertigere klinische Insights als Tabellen | 1,7 vs. 1,26 (p<.01) | Health-Timeline-Studie (n klein, eine Domäne — Caveat) |
| Signal-fokussierte Notiz-Templates reduzieren Umfang | **−40 %** Länge, SUS 90,6 | Note-Bloat-Interventionsstudie |

**Bewusst NICHT als Begründung verwendet (in Verifikation refutiert):**
„Arbeitsgedächtnis hält nur 3–5 Items" (als Basis für Listenlimits) und „Scrollen ist
grundsätzlich schädlich / alles muss auf einen Screen". Wir begrenzen Listen aus
*Kurations*-Gründen (Signal vor Rauschen), nicht mit Pseudo-Kognitionszahlen.

---

## 2. Sechs Leitprinzipien (je mit Referenzmuster)

1. **Persistenter Patientenkontext.** Wer-ist-das darf beim Scrollen nie verloren
   gehen. Referenz: Epic Storyboard (seit 2019 dauerhaft sichtbare Kontextleiste statt
   Banner; Kernkontext = Identität, Risiken, offene Fälle; Hover-Details statt
   Seitenwechsel), Cerner Banner Bar. → Sticky-Header mit PATNR, Geschlecht/Jahrgang/
   Alter, Fall-/Offen-Zählern, Verstorben-Flag.
2. **Master-Detail mit ERSETZEN-Semantik.** Liste und Akte sind zwei Zustände, kein
   Stapel. Auswahl ersetzt die Liste durch die Akte (Fiori Flexible Column Layout:
   Listen-Spalte schmaler als Detail (33/67), neue Auswahl ERSETZT den Detailinhalt,
   nie leere Detailspalte zeigen; jeder Zustand deep-linkbar). → Bei uns einspaltig:
   Liste ⇄ Akte umschalten, „← Patientenliste"-Rücksprung, URL-Hash `#p360/<PATNR>`.
3. **Problemorientierte Aggregation statt flacher Listen.** Diagnosen gruppiert nach
   ICD-Kode (Anzahl, Erst-/Letztnennung, Hauptdiagnose-Kennzeichen), Einzelnennungen
   als Aufklapp-Detail. Referenz: POV-Studie (Zahlen oben), Epic Problem List +
   Episodes of Care. Fälle gruppiert: offene zuerst, dann nach Jahr.
4. **Timeline als führendes Navigationselement,** nicht als Anhängsel. Referenz: Epic
   Lifetime, LifeLines, Studien-Konsens („eine vereinte Timeline über alle Domänen ist
   die nützlichste Darstellung; Zoom/Filter sind Kernfunktion, nicht Extra").
   → Ausbaustufe D2: Swimlane-Canvas mit Jahres-Gruppierung und Brush.
5. **Progressive Disclosure + Rauschkontrolle.** Einstieg = kuratierte Zusammenfassung;
   Volltiefe per Drilldown (Cerner Provider View: Komponenten-Schnellansicht, Header
   als Link in die Vollsektion; Epic Quick Filters ausdrücklich zur Rauschreduktion).
   → Default-Listen begrenzt mit „Mehr anzeigen", Filter-Chips statt Alles-Zeigen.
6. **Keine leeren Gefäße, keine Sentinel-Rohwerte.** NHS/VA: leere Zellen verboten —
   fehlende Daten explizit benennen und visuell zurücknehmen; leere Panels gar nicht
   erst rendern. SAP-Leerdatum (0101-01-01) NIEMALS anzeigen → „laufend" / „—".

---

## 3. Verbindliche Dichte-/Tabellenregeln (NHS + VA + Fiori destilliert)

- Tabellen NUR für vergleichbare Zeilen/Spalten-Daten, nie als Layout (NHS/VA).
- **Zahlenspalten rechtsbündig** inkl. Spaltenkopf (NHS) — tabellarische Ziffern.
- **Max. ~6 Spalten** je Tabelle (VA: 5 als Obergrenze; wir erlauben 6 bei schmalen
  Spalten); Identifikationsspalte zuerst.
- **Sticky Header ist Default** bei scrollenden Tabellen (Fiori: opt-out, nicht opt-in).
- **Initiale Zeilenzahl begrenzt + „Mehr"**: Fiori-Default 20 Zeilen im List Report,
  10 in Objektseiten-Sektionen → wir: 20 je Akten-Sektion, „Mehr anzeigen" lädt nach.
- **Gruppierung ist erstklassige Alternative zur flachen Liste** (Fiori Row Grouping)
  — bei uns Pflicht für Diagnosen (ICD) und Fälle (Jahr).
- Karten NUR zur Gruppierung zusammengehöriger Inhalte, max. 3 Aktionen, nie für
  Fließtext-Hervorhebung (NHS); Kartengitter nie >2 Reihen ohne Gruppierung.
- Fehlende Werte: „—" bzw. benannt („keine Laborwerte in dieser Kohorte"), sekundäre
  Textfarbe; leere Panels ausblenden statt anzeigen.
- Zebra-Streifen/Rahmen: dezente Trennlinien, randlos als Default (VA); kein Zebra.

---

## 4. Ziel-Anatomie

```
ZUSTAND A — Arbeitsliste (Worklist)                ZUSTAND B — Akte (ersetzt A)
┌────────────────────────────────────┐             ┌────────────────────────────────────┐
│ Suche [PATNR/Name-Pseudonym] 50/100/200          │ ◀ Patientenliste   ⌂ #p360/0004..  │
│ ┌────────────────────────────────┐ │             ├────────────────────────────────────┤
│ │ PATNR | G | Jg | Fälle | offen │ │  Klick      │ ▣ STICKY-HEADER  0004000349        │
│ │ …(20 Zeilen, sticky head,      │ │  ═══════▶   │   weiblich · Jg 1961 (65) ·        │
│ │  Zahlen rechtsbündig, Mehr…)   │ │  ersetzt    │   20 Fälle · 9 offen  [⚖ MD]      │
│ └────────────────────────────────┘ │             ├────────────────────────────────────┤
└────────────────────────────────────┘             │ 1) PROBLEMLISTE (ICD gruppiert)    │
                                                   │    Kode|Text|n|erst|zuletzt|HD     │
  Rücksprung „◀" stellt A wieder her,              │    ▸ Einzelnennungen aufklappbar   │
  Scroll-Position der Liste bleibt.                │ 2) TIMELINE (D2: Swimlanes+Brush;  │
                                                   │    D1: gruppierte Ereignistabelle) │
                                                   │ 3) FÄLLE  [offen (n)] [2026] [2025]│
                                                   │    je Gruppe kompakte Zeilen,      │
                                                   │    „laufend" statt Sentinel        │
                                                   │ 4) LABOR nur wenn Daten            │
                                                   │ 5) weitere Sektionen (P1.1) …      │
                                                   └────────────────────────────────────┘
```

**Sticky-Header-Inhalt (fix):** PATNR · Geschlecht · Jahrgang(Alter) · Verstorben-Flag ·
Fälle gesamt/offen · später: MD-Badge (⚖→MDM), Risiko-Flags (NRSF), Modus-Badge.

---

## 5. Interaktionskontrakt

- Zeilenklick in der Liste **ersetzt** die Ansicht durch die Akte (kein Stapeln,
  kein Scrollen-zur-Akte); „← Patientenliste" stellt die Liste inkl. Seite wieder her.
- Jeder Aktenzustand ist **deep-linkbar**: `#p360/<PATNR>` (Fiori: jeder Layoutzustand
  bookmarkbar); Browser-Zurück verhält sich wie „← Patientenliste".
- Diagnose-Gruppenzeile aufklappen → Einzelnennungen mit Fallbezug (Drillthrough zum
  Fall). Fall-Zeile → Fall-Detail (P2.5: DRG/Erlös + MD-Badge).
- Suchfeld bleibt global erreichbar (Epic Chart Search-Prinzip) — im Header der Liste,
  Enter lädt Direkt-PATNR.

## 6. Umsetzungsstufen

| Stufe | Inhalt | Aufwand |
|---|---|---|
| **D1 (sofort)** | Master-Detail-Umschalten + Rücksprung + URL-Hash · Sticky-Patient-Header · Diagnosen als Problemliste (ICD-gruppiert, Aufklappen) · Fälle gruppiert offen/Jahr, Sentinel→„laufend" · leere Panels ausblenden · Tabellenregeln (rechtsbündig, sticky, 20+Mehr) | 1 Session |
| **D2** | Timeline als Swimlane-Canvas (Domänen-Lanes, Jahres-Ticks, Brush/Zoom, Klick→Fall) ersetzt Ereignistabelle; Quick-Filter-Chips (Domäne, Zeitraum) | ROADMAP P2.2 |
| **D3** | Episodes-of-Care-Gruppierung (Fallketten via NBEW/Wiederaufnahme), Chart-übergreifende Suche, rollenspezifische Einstiegs-Zusammenfassung, Hover-Details im Header | P2/P5 |

## 7. Grenzen der Evidenz (ehrlich)
Design-System-Regeln (NHS/VA/Fiori) sind Herstellervorgaben, keine Studien; die
Timeline-Überlegenheit ist methodisch schmal belegt (kleine Stichproben, eine Domäne,
Zeit-bis-erstem-Insight teils langsamer); Epic-/Cerner-Muster stammen aus Kunden-
Trainingsmaterial einzelner Häuser (site-konfigurierbar). Burnout-/Overload-Evidenz
ist US-zentrisch. Deshalb: Muster übernehmen, aber eigene Nutzerrückmeldung (Björn +
Pilotnutzer) als letzte Instanz je Stufe.
