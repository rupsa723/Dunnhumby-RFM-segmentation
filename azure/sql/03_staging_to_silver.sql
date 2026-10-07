-- =============================================================
-- 03_staging_to_silver.sql
-- Types, deduplicates and loads stg -> silver.
-- Safe to re-run: every target is truncated first.
--
-- Reference tables load first so that anything failing on a
-- constraint fails fast, before the 2.6M-row transaction load.
-- =============================================================

TRUNCATE TABLE silver.campaign_desc;
GO
INSERT INTO silver.campaign_desc (CAMPAIGN, DESCRIPTION, START_DAY, END_DAY)
SELECT CAMPAIGN, DESCRIPTION, START_DAY, END_DAY
FROM stg.campaign_desc;
GO

TRUNCATE TABLE silver.campaign_table;
GO
INSERT INTO silver.campaign_table (household_key, CAMPAIGN, DESCRIPTION)
SELECT household_key, CAMPAIGN, DESCRIPTION
FROM stg.campaign_table;
GO

-- DISTINCT is required here and nowhere else.
-- stg.coupon holds 124,548 rows but only 119,384 distinct
-- (COUPON_UPC, PRODUCT_ID, CAMPAIGN) combinations: 5,164
-- duplicates, 4.1%. The table has only these three columns, so a
-- duplicate is a byte-identical row carrying no extra
-- information — most likely the source export dropped a
-- dimension such as store or week. Campaign 27 accounts for the
-- bulk of them, with some combinations repeating 19 times.
-- The gap between the two counts is a data quality metric, not a
-- silent correction.
TRUNCATE TABLE silver.coupon;
GO
INSERT INTO silver.coupon (COUPON_UPC, PRODUCT_ID, CAMPAIGN)
SELECT DISTINCT COUPON_UPC, PRODUCT_ID, CAMPAIGN
FROM stg.coupon;
GO

TRUNCATE TABLE silver.coupon_redempt;
GO
INSERT INTO silver.coupon_redempt (household_key, DAY, COUPON_UPC, CAMPAIGN)
SELECT household_key, DAY, COUPON_UPC, CAMPAIGN
FROM stg.coupon_redempt;
GO

TRUNCATE TABLE silver.hh_demographic;
GO
INSERT INTO silver.hh_demographic (
    household_key, AGE_DESC, MARITAL_STATUS_CODE, INCOME_DESC,
    HOMEOWNER_DESC, HH_COMP_DESC, HOUSEHOLD_SIZE_DESC, KID_CATEGORY_DESC
)
SELECT
    household_key, AGE_DESC, MARITAL_STATUS_CODE, INCOME_DESC,
    HOMEOWNER_DESC, HH_COMP_DESC, HOUSEHOLD_SIZE_DESC, KID_CATEGORY_DESC
FROM stg.hh_demographic;
GO

TRUNCATE TABLE silver.product;
GO
INSERT INTO silver.product (
    PRODUCT_ID, MANUFACTURER, DEPARTMENT, BRAND,
    COMMODITY_DESC, SUB_COMMODITY_DESC, CURR_SIZE_OF_PRODUCT
)
SELECT
    PRODUCT_ID, MANUFACTURER, DEPARTMENT, BRAND,
    COMMODITY_DESC, SUB_COMMODITY_DESC, CURR_SIZE_OF_PRODUCT
FROM stg.product;
GO


-- ---------- Transactions: the typed cast ----------
--
-- Staging is NVARCHAR, so every column is cast here.
--
-- Money columns go through FLOAT first. That double cast is what
-- absorbs the 56 rows holding scientific notation such as
-- 5.551115E-17: FLOAT parses the exponent, DECIMAL(10,2) then
-- rounds it to 0.00. Casting the string straight to DECIMAL
-- fails.
--
-- Plain CAST rather than TRY_CAST because the conversion check in
-- 02 returned zero failures across all 2,595,732 rows. CAST
-- errors loudly if that ever stops being true, which is what you
-- want once the data has been verified. If a future extract
-- introduced unconvertible values, switch to TRY_CAST and add a
-- WHERE clause to quarantine them.
TRUNCATE TABLE silver.transactions;
GO
INSERT INTO silver.transactions (
    household_key, BASKET_ID, DAY, PRODUCT_ID, QUANTITY,
    SALES_VALUE, STORE_ID, RETAIL_DISC, TRANS_TIME, WEEK_NO,
    COUPON_DISC, COUPON_MATCH_DISC
)
SELECT
    CAST(household_key AS INT),
    CAST(BASKET_ID     AS BIGINT),
    CAST(DAY           AS INT),
    CAST(PRODUCT_ID    AS INT),
    CAST(QUANTITY      AS INT),
    CAST(CAST(SALES_VALUE       AS FLOAT) AS DECIMAL(10,2)),
    CAST(STORE_ID      AS INT),
    CAST(CAST(RETAIL_DISC       AS FLOAT) AS DECIMAL(10,2)),
    CAST(TRANS_TIME    AS INT),
    CAST(WEEK_NO       AS INT),
    CAST(CAST(COUPON_DISC       AS FLOAT) AS DECIMAL(10,2)),
    CAST(CAST(COUPON_MATCH_DISC AS FLOAT) AS DECIMAL(10,2))
FROM stg.transactions;
GO


-- ---------- Verification ----------
-- Expected:
--   transactions     2,595,732   (matches staging)
--   hh_demographic         801
--   product             92,353
--   campaign_table       7,208
--   campaign_desc           30
--   coupon             119,384   (down from 124,548 after DISTINCT)
--   coupon_redempt       2,318

SELECT 'transactions'   AS tbl, COUNT(*) AS row_count FROM silver.transactions
UNION ALL SELECT 'hh_demographic', COUNT(*) FROM silver.hh_demographic
UNION ALL SELECT 'product',        COUNT(*) FROM silver.product
UNION ALL SELECT 'campaign_table', COUNT(*) FROM silver.campaign_table
UNION ALL SELECT 'campaign_desc',  COUNT(*) FROM silver.campaign_desc
UNION ALL SELECT 'coupon',         COUNT(*) FROM silver.coupon
UNION ALL SELECT 'coupon_redempt', COUNT(*) FROM silver.coupon_redempt;
GO

-- The 56 scientific-notation values should now be exactly 0.00.
-- Expect 0.
SELECT COUNT(*) AS residual_float_noise
FROM silver.transactions
WHERE SALES_VALUE <> 0 AND ABS(SALES_VALUE) < 0.01;
GO