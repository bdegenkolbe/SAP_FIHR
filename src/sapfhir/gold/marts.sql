-- Gold-Layer: Analyse-Views ueber die Merge-Views bronze_current.* (CONCEPT §14).
-- NIE direkt auf Roh-Parquet — sonst sind CDC-Aenderungen unsichtbar (ANALYSE A1).
-- Voraussetzung: extract/merge.py hat die bronze_current-Views erzeugt.

CREATE SCHEMA IF NOT EXISTS gold;

-- Faelle je Monat, getrennt nach Fallart.
-- STASP = Statistiksperre (Altbestand): gesperrte Faelle nie in Statistik.
CREATE OR REPLACE VIEW gold.faelle_monat AS
SELECT
    strftime(TRY_CAST(BEGDT AS DATE), '%Y-%m') AS monat,
    FALAR AS fallart,
    COUNT(*)                    AS faelle
FROM bronze_current.nfal
WHERE COALESCE(STORN,'') IN ('','0')
  AND COALESCE(STASP,'') <> 'X'
GROUP BY 1, 2
ORDER BY 1;

-- Verweildauer stationaerer Faelle (Tage)
CREATE OR REPLACE VIEW gold.verweildauer AS
SELECT
    FALNR,
    TRY_CAST(BEGDT AS DATE)                                   AS aufnahme,
    TRY_CAST(ENDAT AS DATE)                                   AS entlassung,
    date_diff('day', TRY_CAST(BEGDT AS DATE), TRY_CAST(ENDAT AS DATE)) AS vwd_tage
FROM bronze_current.nfal
WHERE FALAR = '1'               -- VERIFY stationaer
  AND ENDAT IS NOT NULL
  AND COALESCE(STORN,'') IN ('','0');

-- Top-Hauptdiagnosen (ICD-10-GM) — nur echte KH-Hauptdiagnosen (KHDIA-Flag),
-- sonst dominieren die ~96% Behandlungsdiagnosen die Statistik (VERIFY_RESULTS_3).
CREATE OR REPLACE VIEW gold.top_diagnosen AS
SELECT
    DKEY1 AS icd,
    COUNT(*) AS n
FROM bronze_current.ndia
WHERE COALESCE(STORN,'') IN ('','0')
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
WHERE COALESCE(STORN,'') IN ('','0')
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
  AND COALESCE(STORN,'') IN ('','0')
GROUP BY 1
ORDER BY offene_bewegungen DESC;
