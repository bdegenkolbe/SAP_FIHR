# Automatisierte Bearbeitungsprozesse (Argo Workflows)

Alle Prozesse laufen als Argo-`WorkflowTemplate` im Namespace `jobs-mdm` unter dem
ServiceAccount `mdm-jobs`. Ausgelöst werden sie entweder zeitgesteuert
(`CronWorkflow`) oder von der Anwendung über die Argo-Server-API (Ereignis im Fall,
z. B. „neue Reklamation“). Argo Events ist im Cluster nicht installiert und wird dafür
nicht gebraucht.

## Grundmuster jedes KI-Prozesses

```
dossier  ->  ki-schritt  ->  pruefen  ->  [freigabe: suspend]  ->  uebernehmen  ->  audit
```

| Schritt | Art | Inhalt |
|---|---|---|
| `dossier` | deterministisch | Vorgang aus der App-DB als pseudonymisiertes JSON (Kopf, Reklamationen je REKL_POS, Streitsichten, Unterlagen, Historie gleichartiger Fälle) |
| `ki-schritt` | Modell + Skill `md-management` | strukturierte Antwort nach JSON-Schema des Prozesses |
| `pruefen` | deterministisch | Schema-Validierung, Belegprüfung (jedes zitierte Feld existiert im Dossier), Regelcheck (keine Klartext-Personendaten, keine verbotenen Aktionen) |
| `freigabe` | Mensch | Argo `suspend`; Freigabe/Ablehnung in der App, nicht in der Argo-UI |
| `uebernehmen` | deterministisch | Vorschlag wird Aufgabe/Notiz/Entwurf in der App-DB (nie SAP, nie Versand) |
| `audit` | deterministisch | Eintrag in die Audit-Hashkette: Prozess, Modell, Prompt-Hash, Ergebnis-Hash, Freigebender |

Fällt `pruefen` durch oder meldet der KI-Schritt `eskalieren`, endet der Workflow mit
einer Aufgabe „manuell prüfen“ statt mit einem Vorschlag.

## Prozesskatalog

| ID | Name | Auslöser | KI | Ergebnis |
|---|---|---|---|---|
| P1 | Datenlauf | Cron nachts | nein | Testdaten bzw. Delta laden → SCD2 → Marts → DQ-Gate (Abbruch bei DQ-Fehler) |
| P2 | Fristenwächter | Cron 2× täglich | nein | Ampel neu rechnen, Eskalationsaufgaben anlegen (gelb/rot/überfällig), Tagesliste je Bearbeitergruppe |
| P3 | Eingangs-Triage | App: neue Reklamation | ja | Prüfgrund-Einordnung, Erfolgsaussicht aus Historie, Unterlagen-Checkliste, vorgeschlagene Aufgaben mit Fälligkeit |
| P4 | Gutachten-Auswertung | App: Leistungsentscheid erfasst | ja | Abgleich MD-Forderung ↔ Kodierung (Sichten `_ISH`/`_MDK`), Empfehlung akzeptieren / widersprechen / EV, Begründung mit Belegen |
| P5 | Stellungnahme-Entwurf | Nutzer auf Knopfdruck | ja | Entwurf einer Stellungnahme / eines Widerspruchs als Text in der App |
| P6 | EV-Vorbereitung | App: Stand „Eröffnung EV“ | ja | Fallmappe für das Erörterungsverfahren (Streitpunkte, Argumente, Unterlagenstand) |
| P7 | AWP- und Strafzahlungsprüfung | Cron täglich | nein | Fälle mit fälliger Aufwandspauschale bzw. Strafzahlungsbescheid ohne Reaktion → Aufgabe |
| P8 | Kodier-Feedback | Cron wöchentlich | ja (Zusammenfassung) | Bericht: systematisch beanstandete ICD/OPS/DRG je Fachabteilung |

## JSON-Schema (Beispiel P3, gekürzt)

```json
{
  "einordnung": {"pruefgruende": ["sec. VWD"], "phase": "MDK", "vorgangsart": "Prüfverfahren"},
  "erfolgsaussicht": {"wert": "mittel", "basis": {"vergleichsfaelle": 214, "gewonnen_quote": 0.58},
                      "begruendung": "..."},
  "unterlagen": [{"typ": "Entlassbrief", "vorhanden": true, "beleg": "ZNRKT_BER.BER_TYP=..."}],
  "aufgaben": [{"typ": "AKTE_PRÜF", "faellig": "2026-11-29", "grund": "..."}],
  "sicherheit": "mittel",
  "eskalieren": false
}
```

## Was ein KI-Schritt nie tut

Versenden, buchen, in SAP schreiben, Status „erledigt“ setzen, Fristen verlängern,
Personen nennen, Werte erfinden, die nicht im Dossier stehen.
