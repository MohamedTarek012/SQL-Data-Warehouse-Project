-- ============================================================================================================================
-- DDL : Silver Layer  –  All Tables
-- ============================================================================================================================
-- Purpose   : Define the clean, standardised tables of the Silver Layer.
--             Silver is the single source of truth before business aggregations (Gold).
-- Sources   : CRM system (lowercase files) and ERP system (UPPERCASE files)
-- Actions   : CREATE TABLE for each of the 6 entities  (schema [silver] already exists).
-- Run once  : Safe to re-run – each table is dropped and recreated if it already exists.
-- ============================================================================================================================


-- ============================================================
--  1.  silver.crm_prd_info
--      Source : CRM  →  prd_info.csv
-- ============================================================
-- Cleaning contract
--   • prd_cost        : NULL replaced with 0
--   • prd_line        : single-char code expanded to full label
--                       (R → Road | M → Mountain | S → Other Sale | T → Touring | else → N/A)
--   • prd_start_dt    : VARCHAR DD/MM/YYYY  →  DATE
--   • prd_end_dt      : DERIVED  =  LEAD(prd_start_dt) – 1 day  OVER (PARTITION BY prd_key ORDER BY prd_start_dt)
--                       Source end date is discarded – it pre-dates start date in 200 of 397 rows
--   • prd_sub_key     : derived join key  =  segments [2:]  of prd_key   → joins crm_sales_details.sls_prd_key
--   • cat_id          : derived join key  =  segment[0] + '_' + segment[1]  → joins erp_px_cat_g1v2.id
-- ============================================================
IF OBJECT_ID('silver.crm_prd_info', 'U') IS NOT NULL
BEGIN
    DROP TABLE silver.crm_prd_info;
    PRINT '>> Table silver.crm_prd_info dropped for recreation.';
END

CREATE TABLE silver.crm_prd_info (
    prd_id          INT             NOT NULL,
    prd_key         NVARCHAR(50)    NOT NULL,
    prd_sub_key     NVARCHAR(50)    NOT NULL,       -- derived  | joins → crm_sales_details.sls_prd_key
    cat_id          NVARCHAR(10)    NULL,            -- derived  | joins → erp_px_cat_g1v2.id
    prd_nm          NVARCHAR(100)   NOT NULL,
    prd_cost        DECIMAL(10,2)   NOT NULL CONSTRAINT DF_silver_crm_prd_info_cost DEFAULT 0,
    prd_line        NVARCHAR(20)    NULL,            -- Road | Mountain | Other Sale | Touring | N/A
    prd_start_dt    DATE            NULL,
    prd_end_dt      DATE            NULL,            -- NULL  =  currently active record
    dwh_create_dt   DATETIME2       NOT NULL CONSTRAINT DF_silver_crm_prd_info_audit DEFAULT GETDATE()
);
PRINT '>> Table silver.crm_prd_info created.';
GO


-- ============================================================
--  2.  silver.crm_cust_info
--      Source : CRM  →  cust_info.csv
-- ============================================================
-- Cleaning contract
--   • cst_id              : NULL rows dropped | FLOAT cast to INT
--   • cst_firstname /
--     cst_lastname        : LTRIM + RTRIM whitespace
--   • cst_marital_status  : M → Married | S → Single | else/NULL → N/A
--   • cst_gndr            : M → Male    | F → Female  | else/NULL → N/A
--   • cst_create_date     : VARCHAR DD/MM/YYYY → DATE
--   • Duplicates on cst_key : keep row with latest cst_create_date (ROW_NUMBER rn = 1)
-- ============================================================
IF OBJECT_ID('silver.crm_cust_info', 'U') IS NOT NULL
BEGIN
    DROP TABLE silver.crm_cust_info;
    PRINT '>> Table silver.crm_cust_info dropped for recreation.';
END

CREATE TABLE silver.crm_cust_info (
    cst_id              INT             NOT NULL,
    cst_key             NVARCHAR(20)    NOT NULL,
    cst_firstname       NVARCHAR(50)    NULL,
    cst_lastname        NVARCHAR(50)    NULL,
    cst_marital_status  NVARCHAR(10)    NULL,        -- Married | Single | N/A
    cst_gndr            NVARCHAR(10)    NULL,        -- Male | Female | N/A
    cst_create_date     DATE            NULL,
    dwh_create_dt       DATETIME2       NOT NULL CONSTRAINT DF_silver_crm_cust_info_audit DEFAULT GETDATE()
);
PRINT '>> Table silver.crm_cust_info created.';
GO


-- ============================================================
--  3.  silver.crm_sales_details
--      Source : CRM  →  sales_details.csv
-- ============================================================
-- Cleaning contract
--   • sls_order_dt : INT YYYYMMDD → DATE  |  value <= 0 → NULL
--   • sls_ship_dt  : INT YYYYMMDD → DATE
--   • sls_due_dt   : INT YYYYMMDD → DATE
--   • sls_price    : negative → ABS  |  NULL → sls_sales / sls_quantity
--   • sls_sales    : negative → ABS  |  NULL → sls_quantity * sls_price
--   • Consistency  : if sls_sales <> sls_quantity * sls_price  → recalculate sls_sales
-- ============================================================
IF OBJECT_ID('silver.crm_sales_details', 'U') IS NOT NULL
BEGIN
    DROP TABLE silver.crm_sales_details;
    PRINT '>> Table silver.crm_sales_details dropped for recreation.';
END

CREATE TABLE silver.crm_sales_details (
    sls_ord_num     NVARCHAR(20)    NOT NULL,
    sls_prd_key     NVARCHAR(50)    NOT NULL,        -- joins → crm_prd_info.prd_sub_key
    sls_cust_id     INT             NOT NULL,        -- joins → crm_cust_info.cst_id
    sls_order_dt    DATE            NULL,
    sls_ship_dt     DATE            NULL,
    sls_due_dt      DATE            NULL,
    sls_sales       DECIMAL(12,2)   NULL,
    sls_quantity    INT             NULL,
    sls_price       DECIMAL(10,2)   NULL,
    dwh_create_dt   DATETIME2       NOT NULL CONSTRAINT DF_silver_crm_sales_audit DEFAULT GETDATE()
);
PRINT '>> Table silver.crm_sales_details created.';
GO


-- ============================================================
--  4.  silver.erp_px_cat_g1v2
--      Source : ERP  →  PX_CAT_G1V2.csv
-- ============================================================
-- Cleaning contract
--   • id          : TRIM whitespace
--   • maintenance : 'Yes' → 1  |  'No' → 0
-- ============================================================
IF OBJECT_ID('silver.erp_px_cat_g1v2', 'U') IS NOT NULL
BEGIN
    DROP TABLE silver.erp_px_cat_g1v2;
    PRINT '>> Table silver.erp_px_cat_g1v2 dropped for recreation.';
END

CREATE TABLE silver.erp_px_cat_g1v2 (
    id              NVARCHAR(10)    NOT NULL,        -- joins → crm_prd_info.cat_id
    cat             NVARCHAR(50)    NOT NULL,
    subcat          NVARCHAR(50)    NOT NULL,
    maintenance     BIT             NOT NULL CONSTRAINT DF_silver_erp_cat_maint DEFAULT 0,  -- 1 = Yes | 0 = No
    dwh_create_dt   DATETIME2       NOT NULL CONSTRAINT DF_silver_erp_cat_audit DEFAULT GETDATE()
);
PRINT '>> Table silver.erp_px_cat_g1v2 created.';
GO


-- ============================================================
--  5.  silver.erp_loc_a101
--      Source : ERP  →  LOC_A101.csv
-- ============================================================
-- Cleaning contract
--   • cid   : strip dashes  →  'AW-00011000'  becomes  'AW00011000'
--              normalised to match crm_cust_info.cst_key join format
--   • cntry : normalise variants
--               'US' / 'USA' → 'United States'
--               'DE'         → 'Germany'
--               NULL         → 'Unknown'
-- ============================================================
IF OBJECT_ID('silver.erp_loc_a101', 'U') IS NOT NULL
BEGIN
    DROP TABLE silver.erp_loc_a101;
    PRINT '>> Table silver.erp_loc_a101 dropped for recreation.';
END

CREATE TABLE silver.erp_loc_a101 (
    cid             NVARCHAR(20)    NOT NULL,        -- joins → crm_cust_info.cst_key
    cntry           NVARCHAR(50)    NOT NULL CONSTRAINT DF_silver_erp_loc_cntry DEFAULT 'Unknown',
    dwh_create_dt   DATETIME2       NOT NULL CONSTRAINT DF_silver_erp_loc_audit DEFAULT GETDATE()
);
PRINT '>> Table silver.erp_loc_a101 created.';
GO


-- ============================================================
--  6.  silver.erp_cust_az12
--      Source : ERP  →  CUST_AZ12.csv
-- ============================================================
-- Cleaning contract
--   • cid   : strip leading 'NAS' prefix  →  'NASAW00011000'  becomes  'AW00011000'
--              normalised to match crm_cust_info.cst_key join format
--   • bdate : VARCHAR DD/MM/YYYY → DATE  |  future dates → NULL
--   • gen   : 'Male'/'M' → 'Male'  |  'Female'/'F' → 'Female'  |  blank/NULL → 'N/A'
-- ============================================================
IF OBJECT_ID('silver.erp_cust_az12', 'U') IS NOT NULL
BEGIN
    DROP TABLE silver.erp_cust_az12;
    PRINT '>> Table silver.erp_cust_az12 dropped for recreation.';
END

CREATE TABLE silver.erp_cust_az12 (
    cid             NVARCHAR(20)    NOT NULL,        -- joins → crm_cust_info.cst_key
    bdate           DATE            NULL,
    gen             NVARCHAR(10)    NOT NULL CONSTRAINT DF_silver_erp_cust_gen DEFAULT 'N/A',  -- Male | Female | N/A
    dwh_create_dt   DATETIME2       NOT NULL CONSTRAINT DF_silver_erp_cust_audit DEFAULT GETDATE()
);
PRINT '>> Table silver.erp_cust_az12 created.';
GO

PRINT '';
PRINT '============================================================';
PRINT ' Silver Layer DDL completed – all 6 tables ready.';
PRINT '============================================================';
