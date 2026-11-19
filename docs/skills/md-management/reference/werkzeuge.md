# Werkzeuge der Anwendung (MCP `mdm_*`, geplant)

Die Anwendung stellt ihre Funktionen als MCP-Werkzeuge `mdm_*` bereit (KONZEPT_MDM_GREENBAY §6.3) — für Claude im Dialog
(Medizincontrolling, über den Verbund unter `mcp.greenbay.systems`) und für die
KI-Schritte der Argo-Prozesse. Lesend sind alle frei; schreibende Werkzeuge erzeugen
ausschließlich **Vorschläge** mit Status `vorgeschlagen`.

| Werkzeug | Art | Zweck |
|---|---|---|
| `anleitung` | lesen | Diese Bedienregeln + Datenstand (Testdaten/Produktiv) |
| `mdm_vorgang` | lesen | Dossier eines Vorgangs (pseudonymisiert) |
| `mdm_vergleichsfaelle` | lesen | Historie gleichartiger Fälle (DRG, Prüfgrund, Kasse) mit Ergebnisverteilung |
| `mdm_fristen` | lesen | Fristen-Cockpit, gefiltert |
| `mdm_kennzahlen` | lesen | Erfolgsquote, Volumen, Prüfquote — mit Ebene und Filter im Ergebnis |
| `mdm_katalog` | lesen | Kataloge (Stände, Gründe, Erledigungsgründe, Aufgabentypen) |
| `mdm_aufgabe_vorschlagen` | Vorschlag | Aufgabe mit Typ, Fälligkeit, Begründung |
| `mdm_entwurf_speichern` | Vorschlag | Text-Entwurf (Stellungnahme, EV-Mappe) am Vorgang |
| `mdm_eskalieren` | Vorschlag | Vorgang zur manuellen Prüfung markieren |

Nicht vorhanden und nicht vorgesehen: Versand, SAP-Schreibzugriff, Löschen,
Freigeben. Freigaben passieren nur in der Oberfläche durch angemeldete Nutzer.
