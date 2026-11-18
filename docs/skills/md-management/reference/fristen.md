# Fristen — Quelle, Rechnung, Ampel

> Rechtliche Fristwerte (Prüfverfahrensvereinbarung, § 275c SGB V, § 17c KHG) ändern
> sich. **Maßgeblich sind die im Haus gepflegten Werte** (`ZNRKT_KOPF.FRIST1/FRIST1_EIN`,
> `ZNRKT_C_FRIST`, Mahnzeiträume in `ZNRKT_C_STAND`). Feste Zahlen in diesem Dokument
> sind Beispiele aus den Daten, keine Rechtsauskunft — vor Nutzung vom
> Medizincontrolling bestätigen lassen.

## Welche Frist woraus

| Frist | Start | Dauer | Ende / erfüllt durch |
|---|---|---|---|
| Unterlagenübermittlung | `ZNRKT_BER.BER_ANF_DAT` | aus `FRIST1`/`FRIST1_EIN` des Vorgangs bzw. Haus-Customizing | `BER_AUSG_DAT` gesetzt |
| Prüfverfahren gesamt | `ZNRKT_KOPF.PRF_BEG` (nur Prüfverfahren, LFDNR 001–003) | `FRIST1` + Einheit (`T` Tage / `M` Monate; live 42 Tage bzw. 4 Monate) | `PRF_END` echt |
| Wiedervorlage | `ZNRKT_AUF.AUF_TERMIN` | — | `AUF_ERL='X'` (stornierte Aufgaben vorher ausfiltern) |
| Bearbeitungs-SLA je Aufgabe | `ZNRKT_AUF.AUF_BEG_DAT` | `ZNRKT_C_AUFTYP.AUF_BEARBZT` (Soll-Tage je Typ) | `AUF_END_DAT` |
| MD-Begehung | `ZNRKT_MDK.MDKTERMIN` | Termin selbst | Konsens/Dissens erfasst |
| Mahnung Unterlagen | (`ZNRKT_BERMAHN` nur bis 2015 gepflegt — heute keine Mahnstufe aus den Daten) | Mahnzeiträume `ZNRKT_C_STAND.MAHN_ZEITR_1/2` als Regelwert | — |
| Default-Fristen | `ZNRKT_C_FRIST` | FRIST1 = 42, FRIST2 = 180 Tage (Bedeutung fachlich bestätigen) | — |

Monatsfristen mit Kalendermonaten rechnen (wie Qlik: `AddMonths`), nicht 30 Tage.

## Ampel

- **grün:** Restfrist > Warnschwelle (`ZNRKT_C_AUFTYP.AUF_WARNTG` bzw. Default 7 Tage)
- **gelb:** 0 < Restfrist ≤ Warnschwelle
- **rot:** Fristtag heute
- **überfällig:** Restfrist < 0
- **Altbestand:** Anforderung älter als 24 Monate → eigene, sichtbare Menge

## Was nicht als Frist taugt

`PRF_BEG/PRF_END` bei Rechnungsabweisung/interner Prüfung (prozessbedingt leer),
`BER_ZIEL_DAT` (88 von 957.756 belegt), `KOPF.BSTDAT` (0,7 %), alle Datumsfelder in
`ZNRKT_KLA` (tot), `ZNRKT_MDK.MDKGUTDAT` (nach 2013 leer), `KG`-Erinnerungen (nur bis
04/2024). Live 15.11.2026: 1.729 offene Aufgaben, davon 938 überfällig.
