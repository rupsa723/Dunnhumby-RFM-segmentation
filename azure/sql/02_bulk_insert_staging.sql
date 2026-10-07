-- =============================================================
-- 02_bulk_insert_staging.sql
-- Loads seven CSVs from ADLS Gen2 into the stg schema.
--
-- Authentication is via the SQL server's system-assigned managed
-- identity, so no SAS token or storage key appears anywhere in
-- this file or the codebase. Prerequisites, done once in the
-- portal:
--   1. SQL server -> Security -> Identity -> system assigned = On
--   2. Storage account -> Access Control (IAM) -> add role
--      assignment -> Storage Blob Data Reader -> Managed identity
--      -> select the SQL server
--   Role assignments can take a few minutes to propagate.
--
-- Every load is paired with a TRUNCATE. BULK INSERT appends, so
-- without this a second run doubles the table.
-- =============================================================


-- ---------- One-time setup ----------
-- Replace the placeholder before running. Do not commit a real
-- password to source control.

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<SET-A-STRONG-PASSWORD-HERE>';
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = 'MsiCredential')
    CREATE DATABASE SCOPED CREDENTIAL MsiCredential
    WITH IDENTITY = 'MANAGED IDENTITY';
GO

IF NOT EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = 'RfmBlobStorage')
    CREATE EXTERNAL DATA SOURCE RfmBlobStorage
    WITH (
        TYPE       = BLOB_STORAGE,
        LOCATION   = 'https://strfmpipeline01.blob.core.windows.net/data',
        CREDENTIAL = MsiCredential
    );
GO


-- ---------- Loads ----------
-- FIRSTROW = 2        skip the header row
-- ROWTERMINATOR 0x0a  line feed; FORMAT='CSV' absorbs the CR in CRLF
-- TABLOCK             table-level lock, faster than row-level on bulk loads

TRUNCATE TABLE stg.campaign_desc;
GO
BULK INSERT stg.campaign_desc
FROM 'raw/campaign_desc.csv'
WITH (DATA_SOURCE='RfmBlobStorage', FORMAT='CSV', FIRSTROW=2,
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

TRUNCATE TABLE stg.campaign_table;
GO
BULK INSERT stg.campaign_table
FROM 'raw/campaign_table.csv'
WITH (DATA_SOURCE='RfmBlobStorage', FORMAT='CSV', FIRSTROW=2,
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

TRUNCATE TABLE stg.coupon;
GO
BULK INSERT stg.coupon
FROM 'raw/coupon.csv'
WITH (DATA_SOURCE='RfmBlobStorage', FORMAT='CSV', FIRSTROW=2,
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

TRUNCATE TABLE stg.coupon_redempt;
GO
BULK INSERT stg.coupon_redempt
FROM 'raw/coupon_redempt.csv'
WITH (DATA_SOURCE='RfmBlobStorage', FORMAT='CSV', FIRSTROW=2,
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

TRUNCATE TABLE stg.hh_demographic;
GO
BULK INSERT stg.hh_demographic
FROM 'raw/hh_demographic.csv'
WITH (DATA_SOURCE='RfmBlobStorage', FORMAT='CSV', FIRSTROW=2,
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

TRUNCATE TABLE stg.product;
GO
BULK INSERT stg.product
FROM 'raw/product.csv'
WITH (DATA_SOURCE='RfmBlobStorage', FORMAT='CSV', FIRSTROW=2,
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

TRUNCATE TABLE stg.transactions;
GO
BULK INSERT stg.transactions
FROM 'raw/transaction_data.csv'
WITH (DATA_SOURCE='RfmBlobStorage', FORMAT='CSV', FIRSTROW=2,
      FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO


-- ---------- Verification ----------
-- Expected:
--   transactions     2,595,732
--   hh_demographic         801
--   product             92,353
--   campaign_table       7,208
--   campaign_desc           30
--   coupon             124,548
--   coupon_redempt       2,318
-- A count off by exactly one means FIRSTROW was wrong and the
-- header loaded as data. A count that is an exact multiple means
-- the load ran more than once without a TRUNCATE.

SELECT 'transactions'   AS tbl, COUNT(*) AS row_count FROM stg.transactions
UNION ALL SELECT 'hh_demographic', COUNT(*) FROM stg.hh_demographic
UNION ALL SELECT 'product',        COUNT(*) FROM stg.product
UNION ALL SELECT 'campaign_table', COUNT(*) FROM stg.campaign_table
UNION ALL SELECT 'campaign_desc',  COUNT(*) FROM stg.campaign_desc
UNION ALL SELECT 'coupon',         COUNT(*) FROM stg.coupon
UNION ALL SELECT 'coupon_redempt', COUNT(*) FROM stg.coupon_redempt;
GO

-- Confirm every text value in stg.transactions converts before
-- 03 runs with plain CAST. All zeros expected.
SELECT
    SUM(CASE WHEN TRY_CAST(household_key AS INT)    IS NULL THEN 1 ELSE 0 END) AS bad_household,
    SUM(CASE WHEN TRY_CAST(BASKET_ID     AS BIGINT) IS NULL THEN 1 ELSE 0 END) AS bad_basket,
    SUM(CASE WHEN TRY_CAST(DAY           AS INT)    IS NULL THEN 1 ELSE 0 END) AS bad_day,
    SUM(CASE WHEN TRY_CAST(PRODUCT_ID    AS INT)    IS NULL THEN 1 ELSE 0 END) AS bad_product,
    SUM(CASE WHEN TRY_CAST(QUANTITY      AS INT)    IS NULL THEN 1 ELSE 0 END) AS bad_quantity,
    SUM(CASE WHEN TRY_CAST(SALES_VALUE   AS FLOAT)  IS NULL THEN 1 ELSE 0 END) AS bad_sales,
    SUM(CASE WHEN TRY_CAST(RETAIL_DISC   AS FLOAT)  IS NULL THEN 1 ELSE 0 END) AS bad_retail
FROM stg.transactions;
GO