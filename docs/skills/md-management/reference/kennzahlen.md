# Kennzahlen — Formeln und SQL-Muster

Alle Muster für die Replika (T-SQL, `sap.`) bzw. sinngemäß für die Gold-Schicht der
Anwendung. Immer `MANDT='100'` und Storno raus (`COALESCE(…_STORN,'')<>'X'`).

## Reklamation statt Statuszeile

```sql
WITH rk AS (
  SELECT FALNR, KOSTR, LFDNR, REKL_POS,
         MAX(RKT_PHASE) phase, MAX(REKL_ERLGR) erlgr, MAX(REKL_ERL) erl,
         MAX(REKL_ERLDAT) erldat, MIN(ERDAT) erdat
  FROM sap.ZNRKT_REKL
  WHERE MANDT='100' AND COALESCE(REKL_STORN,'')<>'X'
  GROUP BY FALNR, KOSTR, LFDNR, REKL_POS)
SELECT ... FROM rk
```

## Erfolgsquote (Haus-Definition)

```sql
kat AS (SELECT REKL_ERLGR, MAX(NULLIF(GRUPPE,'')) gruppe
        FROM sap.ZNRKT_C_REKLERL WHERE MANDT='100' GROUP BY REKL_ERLGR)
-- gewonnen ÷ (gewonnen + verloren), je Erledigungsjahr und Phase;
-- Kompromiss, MDK und unbewertet separat zeigen
```

Live (MD-Phase, nur bewertete Fälle): 2023 69 % · 2024 61 % · 2025 61 % gewonnen.
Gespeicherte Abfrage im sapfhir-live-MCP: `RKT_ERFOLGSQUOTE_JE_JAHR_PHASE`.

## Rechnungsvolumen unter Prüfung

```sql
WITH je_beleg AS (
  SELECT YEAR(REK_REDAT) jahr, FALNR, KOSTR, LFDNR, REK_VBELN, MAX(REK_NETWR) netwr
  FROM sap.ZNRKT_REKL
  WHERE MANDT='100' AND COALESCE(REKL_STORN,'')<>'X'
    AND REK_REDAT > '1900-01-01' AND COALESCE(REK_VBELN,'')<>''
  GROUP BY YEAR(REK_REDAT), FALNR, KOSTR, LFDNR, REK_VBELN)
SELECT jahr, SUM(netwr) FROM je_beleg GROUP BY jahr
```

Gespeichert als `RKT_RECHNUNGSVOLUMEN_JE_JAHR_DEDUPLIZIERT`.

## Erlösminderung

- Belastbar: §301-gemeldete Differenz aus `/SMS/RKT_EDI` (vorher/nachher je Meldung).
- Strukturell: `ZNRKT_DRG` `DRG_ENTGELT_ISH − DRG_ENTGELT_RKT` (nur Zeilen mit
  `_RKT` ≠ 0, ohne `DRG_STORN`). Live 1,5–5 Mio €/Jahr.
- Das Haus selbst (Qlik) rechnet die Belegdifferenz vor/nach Reklamationsphase.

## Prüfquote je Kasse (§ 275c)

Prüfungen je Kasse und Quartal ÷ abgerechnete Schlussrechnungen je Kasse und Quartal;
die Haus-Qlik-App rechnet sie in `ES_TS_3750`. Für die Anwendung: Zähler aus
`ZNRKT_KOPF` (Vorgangsart Prüfverfahren, Eingangsquartal), Nenner aus der Abrechnung
(NFAL/Faktura) — Nenner-Definition vor Nutzung mit dem Medizincontrolling abstimmen.

## Durchlaufzeiten

- Unterlagen: `BER_ANF_DAT` → `BER_AUSG_DAT` (live Ø 19,6 Tage).
- Vorgang: erste → letzte Statuszeile (`REKL_ST_DAT`) bzw. SCD2-Historie der App.
