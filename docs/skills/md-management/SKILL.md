---
name: md-management
description: MD-Management / Medizincontrolling nach § 275c SGB V und § 17c KHG auf Basis der i.s.h.med-RKT-Tabellen (sap.ZNRKT_*) und der Anwendung CliniBots MDM (Testsystem mdm.greenbay.systems). IMMER verwenden, sobald eine Krankenkassen-Rechnungsprüfung, ein MD-Prüfverfahren, eine Reklamation, eine Prüfanzeige, ein Leistungsentscheid, ein Erörterungsverfahren, eine Aufwandspauschale, Unterlagenanforderungen oder Fristen dazu berührt werden — auch beiläufig: "Prüfquote", "Erfolgsquote MD", "was hat der MD gekürzt", "Fristen-Cockpit", "Arbeitskorb", "Stellungnahme an den MD", "Widerspruch gegen das Gutachten", "Falldialog", "EV vorbereiten", "AWP", "Strafzahlung", "Downcoding", "welche Kasse prüft am meisten", "ZNRKT", "RKT". Gilt auch für automatisierte Bearbeitungsschritte (Argo-Workflows), die diesen Skill als Arbeitsanweisung laden. Verhindert die drei teuren Fehler: Beträge über Statuszeilen mehrfach zu summieren, Fristen aus Kopffeldern statt aus der Unterlagenstrecke zu rechnen und eine KI-Empfehlung ohne menschliche Freigabe nach außen zu geben.
---

# MD-Management (RKT / CliniBots MDM)

> **ENTWURF R34** (SAP_FIHR `docs/skills/md-management`). Wird nach Freigabe nach
> `C:\ai\infra\skills\md-management` übernommen. Fachliche Werte (Fristen, Klassen)
> vor Produktivnutzung vom Medizincontrolling bestätigen lassen.

Kassen beanstanden Krankenhausrechnungen; der Medizinische Dienst (MD) prüft. Das Haus
muss fristgerecht Unterlagen liefern, Ergebnisse prüfen, ggf. widersprechen, ein
Erörterungsverfahren (§ 17c KHG) führen und Erlösdifferenzen, Aufwandspauschalen und
Strafzahlungen verbuchen. In i.s.h.med bildet das kundeneigene Modul **RKT** diesen
Workflow ab (`sap.ZNRKT_*`, 83 Tabellen). **CliniBots MDM** ist die Anwendung darauf.

## Drei Regeln, die nie gebrochen werden

1. **Nichts geht ohne Freigabe nach außen.** Keine Nachricht an Kasse oder MD, kein
   §301-Versand, keine Rechnungskorrektur, keine Statusänderung in SAP. KI-Ergebnisse
   sind *Vorschläge* in der eigenen Datenbank, bis ein Mensch sie freigibt
   (Argo-Schritt `freigabe`, Audit-Eintrag). SAP wird nie beschrieben.
2. **Nur pseudonymisierte Daten.** Namen, Adressen, Versichertennummern, Freitexte
   (`*_BEM`, `*_TXT`), Sachbearbeiter-/Arztkürzel nie im Klartext lesen, ausgeben oder
   in Prompts geben. Im Cluster liegen ausschließlich synthetische Testdaten, solange
   keine Datenschutz-Folgenabschätzung und kein Betriebsbeschluss vorliegen.
3. **Erst zählen, dann behaupten.** Jede Zahl mit Ebene (Vorgang, Reklamation,
   Statuszeile, Bericht) und Filter (Vorgangsart, Storno, Zeitraum) nennen.

## Datenmodell in einem Satz je Ebene

| Ebene | Tabelle | Schlüssel | Merke |
|---|---|---|---|
| Vorgang (Prüfverfahren) | `ZNRKT_KOPF` | `FALNR, KOSTR, LFDNR` | `LFDNR` ist eine **Vorgangsart**: 001–003 Prüfverfahren, 400–409 Rechnungsabweisung, 410–419 interne Prüfung |
| Reklamation | `ZNRKT_REKL` je `REKL_POS` | + `REKL_POS` | Gründe, Ergebnis (`REKL_ERLGR`), Rechnung (`REK_NETWR`) |
| Statuszeile | `ZNRKT_REKL` je `REKL_ST_POS` | + `REKL_ST_POS` | **Beträge wiederholen sich je Statuszeile → nie darüber summieren** |
| Unterlagen | `ZNRKT_BER` (`ZNRKT_BERMAHN` nur bis 2015) | + `BER_LFDNR` | **echte Fristenquelle**: `BER_ANF_DAT` → `BER_AUSG_DAT` |
| Aufgaben | `ZNRKT_AUF` | + `AUF_LFDNR` | Wiedervorlagen, Typen in `ZNRKT_C_AUFTYP` |
| Streitgegenstände | `ZNRKT_DRG/ICD/OPS/Z75/BEA/TOB` | + Doppelschlüssel | Sichten `_ISH/_KK/_MDK/_ANF/_RKT`; `_MDE` ist leer, Ergebnis = `_RKT` |
| §301-Meldungen | `/SMS/RKT_EDI` | — | belastbare gemeldete Erlösdifferenz |
| Kataloge | `ZNRKT_C_*` | Text-Schlüssel + `BEGDT` | `C_STAND` (Endstand `REKL_ERL`), `C_REKLERL` (`GRUPPE`), `C_GRUND`, `C_AUFTYP` |

Details, Fallen und geprüfte Zahlen: `reference/datenmodell.md`.

## Wie gezählt wird

- **Erfolgsquote:** je *Reklamation* (nicht Statuszeile), nur erledigte, Klasse aus
  `ZNRKT_C_REKLERL.GRUPPE`: gewonnen / verloren / Kompromiss / MDK. Quote =
  gewonnen ÷ (gewonnen + verloren); Kompromiss und unbewertete Erledigungen
  („Vorgang erledigt“ seit 02/2020) getrennt ausweisen.
- **Rechnungsvolumen:** `MAX(REK_NETWR)` je Vorgang und Rechnungsbeleg `REK_VBELN`.
- **Erlösverlust:** §301-gemeldete Differenz (`/SMS/RKT_EDI`) vor DRG-Entgeltdifferenz
  (`ZNRKT_DRG._ISH − _RKT`); beides benennen.
- **Vorgangsart filtern:** Das Haus-Reporting schließt interne Prüfungen (LFDNR
  410–419) aus.
- **Sentinels:** `0101-01-01`, `0001-01-01`, `9999-12-31` sind keine Daten.

Formeln und SQL-Muster: `reference/kennzahlen.md`.

## Fristen

Fristen werden aus der Unterlagenstrecke und den Kopffeldern `FRIST1`/`FRIST1_EIN`
(Tage oder Monate) gerechnet, nicht aus `PRF_BEG/PRF_END` (bei Rechnungsabweisung und
interner Prüfung prozessbedingt leer). Altbestand (> 24 Monate) getrennt zeigen, nicht
verschweigen. Ablauf und Ampellogik: `reference/fristen.md`.

## Arbeiten als Bearbeitungsschritt (Argo)

Ein Workflow-Schritt lädt diesen Skill und bekommt **genau einen Vorgang** als
pseudonymisiertes JSON-Dossier. Er darf nur die Werkzeuge der Anwendung nutzen
(`mdm_*`, siehe `reference/werkzeuge.md`) und liefert ein **strukturiertes Ergebnis**
nach dem Schema des Schritts, nie Freitext allein. Jede Empfehlung trägt Begründung,
Belege (Feld/Tabelle) und eine Sicherheit (hoch/mittel/niedrig). Bei Unsicherheit:
`eskalieren` statt raten. Prozesse und Schemas: `reference/prozesse.md`.

## Texte für Kasse und MD

Entwürfe sachlich, kurz, mit Bezug auf Kodierrichtlinie, OPS-/ICD-Definition und
Dokumentation (Fundstelle im Dossier). Keine Behauptung ohne Beleg im Dossier.
Jeder Entwurf endet mit dem Hinweis „Entwurf — vor Versand fachlich prüfen“.
Für Kodierfragen den Skill `dxgrouper` (Gruppierung, CCL, Kodierrichtlinien)
heranziehen, für Leitlinienevidenz `medizin-evidenz`.
