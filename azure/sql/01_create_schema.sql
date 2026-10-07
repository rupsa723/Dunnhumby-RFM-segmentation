-- =============================================================
-- 01_create_schema.sql
-- Creates stg / silver / gold schemas and all tables.
-- Run once. Safe to re-run: every object is guarded.
--
-- Layer contract:
--   stg     accepts whatever the source file contains. Untyped
--           where the source is unreliable. No constraints.
--   silver  enforces correctness. Primary keys reject duplicates.
--   gold    business output, read by Power BI.
-- =============================================================

-- ---------- Schemas ----------

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'stg')
    EXEC('CREATE SCHEMA stg');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
    EXEC('CREATE SCHEMA gold');
GO


-- =============================================================
-- STAGING
-- =============================================================

-- transactions is deliberately untyped.
--
-- The source contains 56 rows where a money column holds a
-- floating-point residual in scientific notation, e.g.
-- 5.551115E-17 in SALES_VALUE. BULK INSERT cannot parse exponent
-- notation into a DECIMAL target and aborts the whole load.
-- Landing as text lets the load always succeed; conversion and
-- any data-quality decisions happen in 03_staging_to_silver.sql.
DROP TABLE IF EXISTS stg.transactions;
GO
CREATE TABLE stg.transactions (
    household_key      NVARCHAR(50),
    BASKET_ID          NVARCHAR(50),
    DAY                NVARCHAR(50),
    PRODUCT_ID         NVARCHAR(50),
    QUANTITY           NVARCHAR(50),
    SALES_VALUE        NVARCHAR(50),
    STORE_ID           NVARCHAR(50),
    RETAIL_DISC        NVARCHAR(50),
    TRANS_TIME         NVARCHAR(50),
    WEEK_NO            NVARCHAR(50),
    COUPON_DISC        NVARCHAR(50),
    COUPON_MATCH_DISC  NVARCHAR(50)
);
GO

-- The remaining six sources parse cleanly, so staging is typed.
-- Column order matches each CSV header exactly: BULK INSERT maps
-- by position, not by name.

DROP TABLE IF EXISTS stg.hh_demographic;
GO
CREATE TABLE stg.hh_demographic (
    AGE_DESC             NVARCHAR(20),
    MARITAL_STATUS_CODE  NVARCHAR(5),
    INCOME_DESC          NVARCHAR(20),
    HOMEOWNER_DESC       NVARCHAR(30),
    HH_COMP_DESC         NVARCHAR(30),
    HOUSEHOLD_SIZE_DESC  NVARCHAR(10),
    KID_CATEGORY_DESC    NVARCHAR(20),
    household_key        INT
);
GO

DROP TABLE IF EXISTS stg.product;
GO
CREATE TABLE stg.product (
    PRODUCT_ID            INT,
    MANUFACTURER          INT,
    DEPARTMENT            NVARCHAR(50),
    BRAND                 NVARCHAR(20),
    COMMODITY_DESC        NVARCHAR(100),   -- source truncates at 30; sized with headroom
    SUB_COMMODITY_DESC    NVARCHAR(100),
    CURR_SIZE_OF_PRODUCT  NVARCHAR(30)
);
GO

DROP TABLE IF EXISTS stg.campaign_table;
GO
CREATE TABLE stg.campaign_table (
    DESCRIPTION    NVARCHAR(20),
    household_key  INT,
    CAMPAIGN       INT
);
GO

DROP TABLE IF EXISTS stg.campaign_desc;
GO
CREATE TABLE stg.campaign_desc (
    DESCRIPTION  NVARCHAR(20),
    CAMPAIGN     INT,
    START_DAY    INT,
    END_DAY      INT
);
GO

-- COUPON_UPC max is 59,986,600,074 — 28x over the INT ceiling.
DROP TABLE IF EXISTS stg.coupon;
GO
CREATE TABLE stg.coupon (
    COUPON_UPC  BIGINT,
    PRODUCT_ID  INT,
    CAMPAIGN    INT
);
GO

DROP TABLE IF EXISTS stg.coupon_redempt;
GO
CREATE TABLE stg.coupon_redempt (
    household_key  INT,
    DAY            INT,
    COUPON_UPC     BIGINT,
    CAMPAIGN       INT
);
GO


-- =============================================================
-- SILVER
-- Typed, keyed, deduplicated. loaded_utc records arrival time.
-- =============================================================

-- BASKET_ID max is 42,305,360,000 — BIGINT required.
-- PK (BASKET_ID, PRODUCT_ID) verified unique across all
-- 2,595,732 source rows before being declared.
DROP TABLE IF EXISTS silver.transactions;
GO
CREATE TABLE silver.transactions (
    household_key      INT           NOT NULL,
    BASKET_ID          BIGINT        NOT NULL,
    DAY                INT           NOT NULL,
    PRODUCT_ID         INT           NOT NULL,
    QUANTITY           INT,
    SALES_VALUE        DECIMAL(10,2),
    STORE_ID           INT,
    RETAIL_DISC        DECIMAL(10,2),   -- source has small positive values (rounding artefacts)
    TRANS_TIME         INT,
    WEEK_NO            INT,
    COUPON_DISC        DECIMAL(10,2),
    COUPON_MATCH_DISC  DECIMAL(10,2),
    loaded_utc         DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_silver_transactions PRIMARY KEY (BASKET_ID, PRODUCT_ID)
);
GO

-- Covering index for the RFM transform, which groups by
-- household_key and reads DAY, BASKET_ID and SALES_VALUE.
-- INCLUDE keeps those columns in the index so the query never
-- touches the base table.
CREATE NONCLUSTERED INDEX IX_silver_transactions_household
    ON silver.transactions (household_key)
    INCLUDE (DAY, BASKET_ID, SALES_VALUE);
GO

DROP TABLE IF EXISTS silver.hh_demographic;
GO
CREATE TABLE silver.hh_demographic (
    household_key        INT PRIMARY KEY,
    AGE_DESC             NVARCHAR(20),
    MARITAL_STATUS_CODE  NVARCHAR(5),
    INCOME_DESC          NVARCHAR(20),
    HOMEOWNER_DESC       NVARCHAR(30),
    HH_COMP_DESC         NVARCHAR(30),
    HOUSEHOLD_SIZE_DESC  NVARCHAR(10),
    KID_CATEGORY_DESC    NVARCHAR(20),
    loaded_utc           DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

DROP TABLE IF EXISTS silver.product;
GO
CREATE TABLE silver.product (
    PRODUCT_ID            INT PRIMARY KEY,
    MANUFACTURER          INT,
    DEPARTMENT            NVARCHAR(50),
    BRAND                 NVARCHAR(20),
    COMMODITY_DESC        NVARCHAR(100),
    SUB_COMMODITY_DESC    NVARCHAR(100),
    CURR_SIZE_OF_PRODUCT  NVARCHAR(30),
    loaded_utc            DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

DROP TABLE IF EXISTS silver.campaign_desc;
GO
CREATE TABLE silver.campaign_desc (
    CAMPAIGN     INT PRIMARY KEY,
    DESCRIPTION  NVARCHAR(20),
    START_DAY    INT,
    END_DAY      INT,
    loaded_utc   DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

DROP TABLE IF EXISTS silver.campaign_table;
GO
CREATE TABLE silver.campaign_table (
    household_key  INT NOT NULL,
    CAMPAIGN       INT NOT NULL,
    DESCRIPTION    NVARCHAR(20),
    loaded_utc     DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_silver_campaign_table PRIMARY KEY (household_key, CAMPAIGN)
);
GO

-- Source contains 5,164 duplicate rows (4.1%) on this key.
-- The PK surfaces them; 03 deduplicates with DISTINCT.
DROP TABLE IF EXISTS silver.coupon;
GO
CREATE TABLE silver.coupon (
    COUPON_UPC  BIGINT NOT NULL,
    PRODUCT_ID  INT    NOT NULL,
    CAMPAIGN    INT    NOT NULL,
    loaded_utc  DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_silver_coupon PRIMARY KEY (COUPON_UPC, PRODUCT_ID, CAMPAIGN)
);
GO

DROP TABLE IF EXISTS silver.coupon_redempt;
GO
CREATE TABLE silver.coupon_redempt (
    household_key  INT    NOT NULL,
    DAY            INT    NOT NULL,
    COUPON_UPC     BIGINT NOT NULL,
    CAMPAIGN       INT    NOT NULL,
    loaded_utc     DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_silver_coupon_redempt PRIMARY KEY (household_key, DAY, COUPON_UPC, CAMPAIGN)
);
GO


-- =============================================================
-- GOLD
-- =============================================================

-- TINYINT (0-255, one byte) for R/F/M (1-5) and RFM_Score (3-15).
-- VARCHAR not NVARCHAR for segment: values are ASCII and
-- generated here, not sourced.
-- Demographics are NOT denormalised into this table. They cover
-- only 801 of 2,500 households, so joining from
-- silver.hh_demographic avoids ~11,900 null cells and keeps the
-- partial coverage explicit in the model.
DROP TABLE IF EXISTS gold.rfm_household;
GO
CREATE TABLE gold.rfm_household (
    household_key   INT PRIMARY KEY,
    recency_days    INT           NOT NULL,
    frequency       INT           NOT NULL,
    monetary        DECIMAL(12,2) NOT NULL,
    R               TINYINT       NOT NULL,
    F               TINYINT       NOT NULL,
    M               TINYINT       NOT NULL,
    RFM_Score       TINYINT       NOT NULL,
    segment         VARCHAR(30)   NOT NULL,
    calculated_utc  DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO


-- ---------- Verification ----------
-- Expect 15 rows: 7 stg, 7 silver, 1 gold.
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('stg','silver','gold')
ORDER BY TABLE_SCHEMA, TABLE_NAME;
GO