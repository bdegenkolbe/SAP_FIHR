-- Gold-Layer: Analyse-Views ueber die Merge-Views bronze_current.* (CONCEPT §14).
-- NIE direkt auf Roh-Parquet — sonst sind CDC-Aenderungen unsichtbar (ANALYSE A1).
-- Voraussetzung: extract/merge.py hat die bronze_current-Views erzeugt.

CREATE SCHEMA IF NOT EXISTS gold;

-- Faelle je Monat, getrennt nach Fallart.
-- STASP = Statistiksperre (Altbestand): gesperrte Faelle nie in Statistik.
-- R34: Monat aus gold.fall_zeitraum (gold/fallzeit.py), NICHT aus NFAL.BEGDT —
-- das ist bei stationaeren Faellen zu 99,9 % Sentinel 0101-01-01 (alle stationaeren
-- Faelle landeten frueher im Monat '0101-01'). Faelle ohne ableitbaren Beginn: monat NULL.
CREATE OR REPLACE VIEW gold.faelle_monat AS
SELECT
    strftime(beg, '%Y-%m')      AS monat,
    FALAR                       AS fallart,
    COUNT(*)                    AS faelle
FROM gold.fall_zeitraum
WHERE NOT ist_storno
  AND COALESCE(STASP,'') <> 'X'
GROUP BY 1, 2
ORDER BY 1;

-- Verweildauer stationaerer Faelle (Tage).
-- R7/R16: Fallende = ENDDT (ENDAT waere das Entbindungsdatum!). R34: Aufnahme/
-- Entlassung aus gold.fall_zeitraum (NFAL, wenn echt; sonst NBEW-Aufnahme BEWTY=1 /
-- -Entlassung BEWTY=2). Offene Faelle (ende NULL) bleiben aussen vor.
CREATE OR REPLACE VIEW gold.verweildauer AS
SELECT
    FALNR,
    beg                          AS aufnahme,
    ende                         AS entlassung,
    date_diff('day', beg, ende)  AS vwd_tage
FROM gold.fall_zeitraum
WHERE FALAR = '1'
  AND beg IS NOT NULL AND ende IS NOT NULL
  AND NOT ist_storno;

-- Top-Hauptdiagnosen (ICD-10-GM) — nur echte KH-Hauptdiagnosen (KHDIA-Flag),
-- sonst dominieren die ~96% Behandlungsdiagnosen die Statistik (VERIFY_RESULTS_3).
CREATE OR REPLACE VIEW gold.top_diagnosen AS
SELECT
    DKEY1 AS icd,
    COUNT(*) AS n
FROM bronze_current.ndia
WHERE COALESCE(TRIM(STORN),'') NOT IN ('X','1')
  AND COALESCE(KHDIA,'') = 'X'
GROUP BY 1
ORDER BY n DESC
LIMIT 50;

-- Diagnosen nach Verwendungstyp je Monat (Flags NICHT exklusiv, VERIFY_RESULTS_3)
CREATE OR REPLACE VIEW gold.diagnose_typen AS
SELECT
    strftime(TRY_CAST(DIADT AS DATE), '%Y-%m') AS monat,
    SUM(CASE WHEN KHDIA='X' THEN 1 ELSE 0 END) AS kh_haupt,
    SUM(CASE WHEN AFDIA='X' THEN 1 ELSE 0 END) AS aufnahme,
    SUM(CASE WHEN ENDIA='X' THEN 1 ELSE 0 END) AS entlass,
    SUM(CASE WHEN EWDIA='X' THEN 1 ELSE 0 END) AS einweisung,
    SUM(CASE WHEN OPDIA='X' THEN 1 ELSE 0 END) AS op,
    SUM(CASE WHEN BHDIA='X' THEN 1 ELSE 0 END) AS behandlung,
    COUNT(*) AS gesamt
FROM bronze_current.ndia
WHERE COALESCE(TRIM(STORN),'') NOT IN ('X','1')
GROUP BY 1
ORDER BY 1;

-- Top-Prozeduren (OPS)
CREATE OR REPLACE VIEW gold.top_prozeduren AS
SELECT
    ICPML AS ops,               -- VERIFY OPS-Spalte
    COUNT(*) AS n
FROM bronze_current.nicp
GROUP BY 1
ORDER BY n DESC
LIMIT 50;

-- Belegung nach OE (aus Bewegungen, aktuell offene).
-- Jahr 9999 = unbekanntes/offenes Ende (Altbestand-Regel) — zaehlt als offen.
CREATE OR REPLACE VIEW gold.belegung_oe AS
SELECT
    COALESCE(ORGPF, ORGFA) AS oe,
    COUNT(*)               AS offene_bewegungen
FROM bronze_current.nbew
WHERE (BWEDT IS NULL OR substr(CAST(BWEDT AS VARCHAR),1,4) = '9999')
  AND COALESCE(TRIM(STORN),'') NOT IN ('X','1')
GROUP BY 1
ORDER BY offene_bewegungen DESC;
