-- Gold-Layer: Analyse-Views ueber die Bronze-Parquet-Dateien.
-- DuckDB liest Parquet direkt; keine Materialisierung noetig (out-of-core).
-- Pfade relativ zum Arbeitsverzeichnis (data/bronze/...).

CREATE SCHEMA IF NOT EXISTS gold;

-- Faelle je Monat, getrennt nach Fallart
CREATE OR REPLACE VIEW gold.faelle_monat AS
SELECT
    strftime(TRY_CAST(BEGDT AS DATE), '%Y-%m') AS monat,
    FALAR AS fallart,           -- VERIFY Enum
    COUNT(*)                    AS faelle
FROM read_parquet('data/bronze/nfal/**/*.parquet', union_by_name=true)
WHERE COALESCE(STORN,'') IN ('','0')
GROUP BY 1, 2
ORDER BY 1;

-- Verweildauer stationaerer Faelle (Tage)
CREATE OR REPLACE VIEW gold.verweildauer AS
SELECT
    FALNR,
    TRY_CAST(BEGDT AS DATE)                                   AS aufnahme,
    TRY_CAST(ENDAT AS DATE)                                   AS entlassung,
    date_diff('day', TRY_CAST(BEGDT AS DATE), TRY_CAST(ENDAT AS DATE)) AS vwd_tage
FROM read_parquet('data/bronze/nfal/**/*.parquet', union_by_name=true)
WHERE FALAR = '1'               -- VERIFY stationaer
  AND ENDAT IS NOT NULL
  AND COALESCE(STORN,'') IN ('','0');

-- Top-Hauptdiagnosen (ICD-10-GM)
CREATE OR REPLACE VIEW gold.top_diagnosen AS
SELECT
    DKEY1 AS icd,               -- VERIFY ICD-Spalte
    COUNT(*) AS n
FROM read_parquet('data/bronze/ndia/**/*.parquet', union_by_name=true)
WHERE COALESCE(STORN,'') IN ('','0')
GROUP BY 1
ORDER BY n DESC
LIMIT 50;

-- DRG / Case-Mix
CREATE OR REPLACE VIEW gold.casemix AS
SELECT
    strftime(TRY_CAST(UPDAT AS DATE), '%Y') AS jahr,
    COUNT(*)                                AS drg_faelle
    -- SUM(bewertungsrelation) AS cm  -- VERIFY Spalte fuer CMI
FROM read_parquet('data/bronze/ndrg/**/*.parquet', union_by_name=true)
GROUP BY 1;

-- Belegung nach OE (aus Bewegungen, aktuell offene)
CREATE OR REPLACE VIEW gold.belegung_oe AS
SELECT
    COALESCE(ORGPF, ORGFA) AS oe,
    COUNT(*)               AS offene_bewegungen
FROM read_parquet('data/bronze/nbew/**/*.parquet', union_by_name=true)
WHERE BWEDT IS NULL
  AND COALESCE(STORN,'') IN ('','0')
GROUP BY 1
ORDER BY offene_bewegungen DESC;
