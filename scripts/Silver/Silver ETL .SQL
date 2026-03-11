-- ============================================================================================================================
-- STORED PROCEDURE : silver.load_silver
-- ============================================================================================================================
-- Purpose   : Single procedure that transforms and loads ALL six Silver tables in one run.
--             Reads from the Bronze layer, applies all cleaning rules, and inserts into Silver.
-- Tables loaded (in order):
--             1. silver.crm_prd_info        <- bronze.crm_prd_info
--             2. silver.crm_cust_info        <- bronze.crm_cust_info
--             3. silver.crm_sales_details    <- bronze.crm_sales_details
--             4. silver.erp_px_cat_g1v2      <- bronze.erp_px_cat_g1v2
--             5. silver.erp_loc_a101         <- bronze.erp_loc_a101
--             6. silver.erp_cust_az12        <- bronze.erp_cust_az12
-- Strategy  : Full refresh - each table is TRUNCATED then re-inserted on every run.
-- Error handling : Single TRY/CATCH wraps the entire procedure.
--                  On failure: prints table name, error message, line, and severity then re-throws.
-- Execution : EXEC silver.load_silver;
-- ============================================================================================================================

IF OBJECT_ID('silver.load_silver', 'P') IS NOT NULL
    DROP PROCEDURE silver.load_silver;
GO

CREATE PROCEDURE silver.load_silver
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @start_time     DATETIME2;
    DECLARE @end_time       DATETIME2;
    DECLARE @section_start  DATETIME2;
    DECLARE @total_ms       INT;
    DECLARE @rows_loaded    INT;

    -- ============================================================
    --  PIPELINE START
    -- ============================================================
    SET @start_time = GETDATE();

    PRINT '============================================================';
    PRINT '  Silver Layer Load  -  START';
    PRINT '  ' + CONVERT(NVARCHAR, @start_time, 120);
    PRINT '============================================================';
    PRINT '';

    BEGIN TRY

    -- ============================================================
    --  SECTION 1 :  silver.crm_prd_info
    -- ============================================================
    -- Transformations applied:
    --   * prd_sub_key  : derived from prd_key - segments after first two joined by '-'
    --                    e.g.  'CO-RF-FR-R92B-58'  ->  'FR-R92B-58'  (join key to sales)
    --   * cat_id       : derived from prd_key - first two segments joined by '_'
    --                    e.g.  'CO-RF-FR-R92B-58'  ->  'CO_RF'  (join key to ERP categories)
    --   * prd_cost     : NULL  ->  0
    --   * prd_line     : single code expanded  (R->Road | M->Mountain | S->Other Sale | T->Touring | else->N/A)
    --                    NOTE: source values have trailing whitespace -> LTRIM/RTRIM applied first
    --   * prd_start_dt : DD/MM/YYYY string  ->  DATE  (style 103)
    --   * prd_end_dt   : SOURCE COLUMN DISCARDED - end date pre-dates start date in 200/397 rows
    --                    DERIVED as  LEAD(prd_start_dt) - 1 day  OVER (PARTITION BY prd_key ORDER BY prd_start_dt)
    --                    Last/only record per key  ->  NULL  (= currently active)
    -- ============================================================
        SET @section_start = GETDATE();
        PRINT '------------------------------------------------------------';
        PRINT '>> [1/6]  Loading  silver.crm_prd_info';
        PRINT '------------------------------------------------------------';

        PRINT '   Truncating silver.crm_prd_info ...';
        TRUNCATE TABLE silver.crm_prd_info;

        PRINT '   Inserting cleaned data ...';
        INSERT INTO silver.crm_prd_info (
            prd_id, prd_key, prd_sub_key, cat_id,
            prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt
        )
        SELECT
            prd_id,
            prd_key,

            -- prd_sub_key : strip the first two dash-segments, keep the rest
            -- CHARINDEX finds the 2nd dash, then takes everything after it
            REPLACE(
                SUBSTRING(prd_key,
                    CHARINDEX('-', prd_key, CHARINDEX('-', prd_key) + 1) + 1,
                    LEN(prd_key)),
                ' ', '')                                                     AS prd_sub_key,

            -- cat_id : take up to the 2nd dash, replace the dash separator with underscore
            REPLACE(
                LEFT(prd_key,
                    CHARINDEX('-', prd_key, CHARINDEX('-', prd_key) + 1) - 1),
                '-', '_')                                                    AS cat_id,

            prd_nm,
            ISNULL(prd_cost, 0)                                             AS prd_cost,

            -- Expand line code - LTRIM/RTRIM required: source has trailing spaces (e.g. 'R ')
            CASE LTRIM(RTRIM(prd_line))
                WHEN 'R' THEN 'Road'
                WHEN 'M' THEN 'Mountain'
                WHEN 'S' THEN 'Other Sale'
                WHEN 'T' THEN 'Touring'
                ELSE          'N/A'
            END                                                             AS prd_line,

            TRY_CONVERT(DATE, prd_start_dt, 103)                           AS prd_start_dt,

            -- Derive end date from the next record's start date minus one day
            -- Source end date is completely unreliable and is ignored
            DATEADD(DAY, -1,
                LEAD(TRY_CONVERT(DATE, prd_start_dt, 103))
                OVER (PARTITION BY prd_key
                      ORDER BY     TRY_CONVERT(DATE, prd_start_dt, 103))
            )                                                               AS prd_end_dt

        FROM bronze.crm_prd_info;

        SET @rows_loaded = @@ROWCOUNT;
        PRINT '   Rows loaded  : ' + CAST(@rows_loaded AS NVARCHAR);
        PRINT '   Duration     : ' + CAST(DATEDIFF(MILLISECOND, @section_start, GETDATE()) AS NVARCHAR) + ' ms';
        PRINT '';


    -- ============================================================
    --  SECTION 2 :  silver.crm_cust_info
    -- ============================================================
    -- Transformations applied:
    --   * Rows where cst_id IS NULL are excluded  (4 orphaned rows with no customer identity)
    --   * Duplicates on cst_key resolved with ROW_NUMBER: keep the row with the latest cst_create_date
    --     (6 customers appear multiple times with incomplete early records and full later ones)
    --   * cst_firstname / cst_lastname : LTRIM + RTRIM to remove surrounding whitespace
    --   * cst_marital_status : M -> Married | S -> Single | else/NULL -> N/A
    --   * cst_gndr           : M -> Male    | F -> Female  | else/NULL -> N/A
    --   * cst_create_date    : DD/MM/YYYY string  ->  DATE  (style 103)
    -- ============================================================
        SET @section_start = GETDATE();
        PRINT '------------------------------------------------------------';
        PRINT '>> [2/6]  Loading  silver.crm_cust_info';
        PRINT '------------------------------------------------------------';

        PRINT '   Truncating silver.crm_cust_info ...';
        TRUNCATE TABLE silver.crm_cust_info;

        PRINT '   Inserting cleaned data ...';
        INSERT INTO silver.crm_cust_info (
            cst_id, cst_key, cst_firstname, cst_lastname,
            cst_marital_status, cst_gndr, cst_create_date
        )
        SELECT
            cst_id,
            cst_key,
            LTRIM(RTRIM(cst_firstname))                 AS cst_firstname,
            LTRIM(RTRIM(cst_lastname))                  AS cst_lastname,

            CASE LTRIM(RTRIM(cst_marital_status))
                WHEN 'M' THEN 'Married'
                WHEN 'S' THEN 'Single'
                ELSE          'N/A'
            END                                         AS cst_marital_status,

            CASE LTRIM(RTRIM(cst_gndr))
                WHEN 'M' THEN 'Male'
                WHEN 'F' THEN 'Female'
                ELSE          'N/A'
            END                                         AS cst_gndr,

            TRY_CONVERT(DATE, cst_create_date, 103)     AS cst_create_date

        FROM (
            -- Rank duplicates: rn = 1 is the most recently created record per customer key
            SELECT *,
                   ROW_NUMBER() OVER (
                       PARTITION BY cst_key
                       ORDER BY     TRY_CONVERT(DATE, cst_create_date, 103) DESC
                   ) AS rn
            FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL       -- exclude 4 orphaned rows
        ) AS ranked
        WHERE rn = 1;                      -- keep only the latest record per customer

        SET @rows_loaded = @@ROWCOUNT;
        PRINT '   Rows loaded  : ' + CAST(@rows_loaded AS NVARCHAR);
        PRINT '   Duration     : ' + CAST(DATEDIFF(MILLISECOND, @section_start, GETDATE()) AS NVARCHAR) + ' ms';
        PRINT '';


    -- ============================================================
    --  SECTION 3 :  silver.crm_sales_details
    -- ============================================================
    -- Transformations applied:
    --   * sls_order_dt   : INT YYYYMMDD -> DATE (style 112) | value <= 0 -> NULL (17 invalid rows)
    --   * sls_ship_dt    : INT YYYYMMDD -> DATE (style 112)
    --   * sls_due_dt     : INT YYYYMMDD -> DATE (style 112)
    --   * sls_price      : negative -> ABS | NULL -> sls_sales / sls_quantity
    --   * sls_sales      : negative -> ABS | NULL -> sls_quantity * sls_price
    --   * Consistency    : sls_sales recalculated when it differs from sls_quantity * sls_price
    --                      (19 rows found with sls_price stored as negative in source)
    -- ============================================================
        SET @section_start = GETDATE();
        PRINT '------------------------------------------------------------';
        PRINT '>> [3/6]  Loading  silver.crm_sales_details';
        PRINT '------------------------------------------------------------';

        PRINT '   Truncating silver.crm_sales_details ...';
        TRUNCATE TABLE silver.crm_sales_details;

        PRINT '   Inserting cleaned data ...';
        INSERT INTO silver.crm_sales_details (
            sls_ord_num, sls_prd_key, sls_cust_id,
            sls_order_dt, sls_ship_dt, sls_due_dt,
            sls_sales, sls_quantity, sls_price
        )
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,

            -- Integer YYYYMMDD -> DATE  |  invalid values (<=0) -> NULL
            CASE WHEN sls_order_dt <= 0 THEN NULL
                 ELSE TRY_CONVERT(DATE, CAST(sls_order_dt AS CHAR(8)), 112)
            END                                                             AS sls_order_dt,

            TRY_CONVERT(DATE, CAST(sls_ship_dt AS CHAR(8)), 112)           AS sls_ship_dt,
            TRY_CONVERT(DATE, CAST(sls_due_dt  AS CHAR(8)), 112)           AS sls_due_dt,

            -- sls_sales: enforce positive | fix NULL | fix inconsistency vs qty*price
            CASE
                WHEN sls_sales IS NULL OR sls_sales <= 0
                    THEN ABS(sls_quantity * sls_price)
                WHEN sls_sales <> sls_quantity * sls_price
                    THEN sls_quantity * ABS(sls_price)
                ELSE ABS(sls_sales)
            END                                                             AS sls_sales,

            sls_quantity,

            -- sls_price: enforce positive | fix NULL
            CASE
                WHEN sls_price IS NULL OR sls_price <= 0
                    THEN ABS(sls_sales / NULLIF(sls_quantity, 0))
                ELSE ABS(sls_price)
            END                                                             AS sls_price

        FROM bronze.crm_sales_details;

        SET @rows_loaded = @@ROWCOUNT;
        PRINT '   Rows loaded  : ' + CAST(@rows_loaded AS NVARCHAR);
        PRINT '   Duration     : ' + CAST(DATEDIFF(MILLISECOND, @section_start, GETDATE()) AS NVARCHAR) + ' ms';
        PRINT '';


    -- ============================================================
    --  SECTION 4 :  silver.erp_px_cat_g1v2
    -- ============================================================
    -- Transformations applied:
    --   * id / cat / subcat : LTRIM + RTRIM to remove surrounding whitespace
    --   * maintenance       : 'Yes' -> 1  |  'No' / anything else -> 0  (stored as BIT)
    -- ============================================================
        SET @section_start = GETDATE();
        PRINT '------------------------------------------------------------';
        PRINT '>> [4/6]  Loading  silver.erp_px_cat_g1v2';
        PRINT '------------------------------------------------------------';

        PRINT '   Truncating silver.erp_px_cat_g1v2 ...';
        TRUNCATE TABLE silver.erp_px_cat_g1v2;

        PRINT '   Inserting cleaned data ...';
        INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
        SELECT
            LTRIM(RTRIM(id))                            AS id,
            LTRIM(RTRIM(cat))                           AS cat,
            LTRIM(RTRIM(subcat))                        AS subcat,

            -- Convert Yes/No string to BIT
            CASE LTRIM(RTRIM(maintenance))
                WHEN 'Yes' THEN 1
                ELSE             0
            END                                         AS maintenance

        FROM bronze.erp_px_cat_g1v2;

        SET @rows_loaded = @@ROWCOUNT;
        PRINT '   Rows loaded  : ' + CAST(@rows_loaded AS NVARCHAR);
        PRINT '   Duration     : ' + CAST(DATEDIFF(MILLISECOND, @section_start, GETDATE()) AS NVARCHAR) + ' ms';
        PRINT '';


    -- ============================================================
    --  SECTION 5 :  silver.erp_loc_a101
    -- ============================================================
    -- Transformations applied:
    --   * cid   : REPLACE('-', '')  ->  'AW-00011000' becomes 'AW00011000'
    --             aligns CID format to crm_cust_info.cst_key so the tables can be joined
    --   * cntry : standardise known abbreviations and replace NULLs
    --               'US' / 'USA'  ->  'United States'
    --               'DE'          ->  'Germany'
    --               NULL          ->  'Unknown'
    -- ============================================================
        SET @section_start = GETDATE();
        PRINT '------------------------------------------------------------';
        PRINT '>> [5/6]  Loading  silver.erp_loc_a101';
        PRINT '------------------------------------------------------------';

        PRINT '   Truncating silver.erp_loc_a101 ...';
        TRUNCATE TABLE silver.erp_loc_a101;

        PRINT '   Inserting cleaned data ...';
        INSERT INTO silver.erp_loc_a101 (cid, cntry)
        SELECT
            -- Strip dashes to match crm cst_key format
            REPLACE(cid, '-', '')                       AS cid,

            CASE LTRIM(RTRIM(cntry))
                WHEN 'US'  THEN 'United States'
                WHEN 'USA' THEN 'United States'
                WHEN 'DE'  THEN 'Germany'
                ELSE ISNULL(LTRIM(RTRIM(cntry)), 'Unknown')
            END                                         AS cntry

        FROM bronze.erp_loc_a101;

        SET @rows_loaded = @@ROWCOUNT;
        PRINT '   Rows loaded  : ' + CAST(@rows_loaded AS NVARCHAR);
        PRINT '   Duration     : ' + CAST(DATEDIFF(MILLISECOND, @section_start, GETDATE()) AS NVARCHAR) + ' ms';
        PRINT '';


    -- ============================================================
    --  SECTION 6 :  silver.erp_cust_az12
    -- ============================================================
    -- Transformations applied:
    --   * cid   : SUBSTRING(cid, 4, LEN(cid))  ->  strip leading 'NAS' prefix
    --             'NASAW00011000' becomes 'AW00011000'
    --             aligns CID format to crm_cust_info.cst_key so the tables can be joined
    --   * bdate : DD/MM/YYYY string -> DATE (style 103)
    --             future dates set to NULL - they are data-entry errors (16 rows found)
    --   * gen   : standardise from multiple source formats to three canonical values
    --               'Male'   / 'M'  ->  'Male'
    --               'Female' / 'F'  ->  'Female'
    --               blank / NULL    ->  'N/A'
    -- ============================================================
        SET @section_start = GETDATE();
        PRINT '------------------------------------------------------------';
        PRINT '>> [6/6]  Loading  silver.erp_cust_az12';
        PRINT '------------------------------------------------------------';

        PRINT '   Truncating silver.erp_cust_az12 ...';
        TRUNCATE TABLE silver.erp_cust_az12;

        PRINT '   Inserting cleaned data ...';
        INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
        SELECT
            -- Strip 'NAS' prefix (first 3 characters) to align with crm cst_key format
            SUBSTRING(cid, 4, LEN(cid))                 AS cid,

            -- Parse birthdate and nullify any future dates (data-entry errors)
            CASE
                WHEN TRY_CONVERT(DATE, bdate, 103) > CAST(GETDATE() AS DATE)
                    THEN NULL
                ELSE TRY_CONVERT(DATE, bdate, 103)
            END                                         AS bdate,

            -- Standardise gender from multiple source formats
            CASE LTRIM(RTRIM(gen))
                WHEN 'Male'   THEN 'Male'
                WHEN 'M'      THEN 'Male'
                WHEN 'Female' THEN 'Female'
                WHEN 'F'      THEN 'Female'
                ELSE               'N/A'
            END                                         AS gen

        FROM bronze.erp_cust_az12;

        SET @rows_loaded = @@ROWCOUNT;
        PRINT '   Rows loaded  : ' + CAST(@rows_loaded AS NVARCHAR);
        PRINT '   Duration     : ' + CAST(DATEDIFF(MILLISECOND, @section_start, GETDATE()) AS NVARCHAR) + ' ms';
        PRINT '';


    END TRY
    BEGIN CATCH
        PRINT '!! =========================================';
        PRINT '!! PIPELINE FAILED  -  silver.load_silver';
        PRINT '!! Message  : ' + ERROR_MESSAGE();
        PRINT '!! Procedure: ' + ISNULL(ERROR_PROCEDURE(), 'N/A');
        PRINT '!! Line     : ' + CAST(ERROR_LINE()     AS NVARCHAR);
        PRINT '!! Severity : ' + CAST(ERROR_SEVERITY() AS NVARCHAR);
        PRINT '!! =========================================';
        THROW;
    END CATCH


    -- ============================================================
    --  PIPELINE END
    -- ============================================================
    SET @end_time = GETDATE();
    SET @total_ms = DATEDIFF(MILLISECOND, @start_time, @end_time);

    PRINT '============================================================';
    PRINT '  Silver Layer Load  -  COMPLETED SUCCESSFULLY';
    PRINT '  Started  : ' + CONVERT(NVARCHAR, @start_time, 120);
    PRINT '  Finished : ' + CONVERT(NVARCHAR, @end_time,   120);
    PRINT '  Duration : ' + CAST(@total_ms / 1000 AS NVARCHAR)
                          + '.' + RIGHT('000' + CAST(@total_ms % 1000 AS NVARCHAR), 3)
                          + ' seconds';
    PRINT '============================================================';

END;
GO
