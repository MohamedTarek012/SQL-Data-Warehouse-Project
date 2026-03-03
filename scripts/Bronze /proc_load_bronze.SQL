/*
===============================================================================
Stored Procedure: Load Bronze Layer (Source -> Bronze)
===============================================================================

Script Purpose:
    This stored procedure loads data into the 'bronze' schema from external CSV files.
    It performs the following actions:
    - Truncates the bronze tables before loading data.
    - Uses the `BULK INSERT` command to load data from csv Files to bronze tables.

Parameters:
    None.
    This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC bronze.load_bronze;
===============================================================================
*/

/* =========================================================
   CRM Tables Bulk Load
   ========================================================= */

-- Customers
CREATE OR ALTER PROCEDURE bronze.load_bronze AS
BEGIN 
    DECLARE @start_time  DATETIME2;
    DECLARE @end_time    DATETIME2;
    DECLARE @batch_start DATETIME2;
    DECLARE @batch_end   DATETIME2;

    SET @batch_start = GETDATE();
    PRINT '============================================';
    PRINT 'Loading Bronze Layer Started At: ' + CAST(@batch_start AS NVARCHAR);
    PRINT '============================================';

    -- =========================================================
    -- CRM Tables
    -- =========================================================
    PRINT '--------------------------------------------';
    PRINT '>> CRM Tables';
    PRINT '--------------------------------------------';

    BEGIN TRY
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.crm_cust_info';
        TRUNCATE TABLE bronze.crm_cust_info;
        PRINT '>> Inserting Data Into: bronze.crm_cust_info';
        BULK INSERT bronze.crm_cust_info
        FROM 'D:\DW project\sql-data-warehouse-project\sql-data-warehouse-project\datasets\source_crm\cust_info.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END TRY
    BEGIN CATCH
        SET @end_time = GETDATE();
        PRINT '!! ERROR in bronze.crm_cust_info: ' + ERROR_MESSAGE();
        PRINT '>> Failed After: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END CATCH;

    BEGIN TRY
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.crm_prd_info';
        TRUNCATE TABLE bronze.crm_prd_info;
        PRINT '>> Inserting Data Into: bronze.crm_prd_info';
        BULK INSERT bronze.crm_prd_info
        FROM 'D:\DW project\sql-data-warehouse-project\sql-data-warehouse-project\datasets\source_crm\prd_info.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END TRY
    BEGIN CATCH
        SET @end_time = GETDATE();
        PRINT '!! ERROR in bronze.crm_prd_info: ' + ERROR_MESSAGE();
        PRINT '>> Failed After: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END CATCH;

    BEGIN TRY
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.crm_sales_details';
        TRUNCATE TABLE bronze.crm_sales_details;
        PRINT '>> Inserting Data Into: bronze.crm_sales_details';
        BULK INSERT bronze.crm_sales_details
        FROM 'D:\DW project\sql-data-warehouse-project\sql-data-warehouse-project\datasets\source_crm\sales_details.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END TRY
    BEGIN CATCH
        SET @end_time = GETDATE();
        PRINT '!! ERROR in bronze.crm_sales_details: ' + ERROR_MESSAGE();
        PRINT '>> Failed After: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END CATCH;

    -- =========================================================
    -- ERP Tables
    -- =========================================================
    PRINT '--------------------------------------------';
    PRINT '>> ERP Tables';
    PRINT '--------------------------------------------';

    BEGIN TRY
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.erp_loc_a101';
        TRUNCATE TABLE bronze.erp_loc_a101;
        PRINT '>> Inserting Data Into: bronze.erp_loc_a101';
        BULK INSERT bronze.erp_loc_a101
        FROM 'D:\DW project\sql-data-warehouse-project\sql-data-warehouse-project\datasets\source_erp\LOC_A101.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END TRY
    BEGIN CATCH
        SET @end_time = GETDATE();
        PRINT '!! ERROR in bronze.erp_loc_a101: ' + ERROR_MESSAGE();
        PRINT '>> Failed After: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END CATCH;

    BEGIN TRY
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.erp_cust_az12';
        TRUNCATE TABLE bronze.erp_cust_az12;
        PRINT '>> Inserting Data Into: bronze.erp_cust_az12';
        BULK INSERT bronze.erp_cust_az12
        FROM 'D:\DW project\sql-data-warehouse-project\sql-data-warehouse-project\datasets\source_erp\CUST_AZ12.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END TRY
    BEGIN CATCH
        SET @end_time = GETDATE();
        PRINT '!! ERROR in bronze.erp_cust_az12: ' + ERROR_MESSAGE();
        PRINT '>> Failed After: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END CATCH;

    BEGIN TRY
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.erp_px_cat_g1v2';
        TRUNCATE TABLE bronze.erp_px_cat_g1v2;
        PRINT '>> Inserting Data Into: bronze.erp_px_cat_g1v2';
        BULK INSERT bronze.erp_px_cat_g1v2
        FROM 'D:\DW project\sql-data-warehouse-project\sql-data-warehouse-project\datasets\source_erp\PX_CAT_G1V2.csv'
        WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', TABLOCK);
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END TRY
    BEGIN CATCH
        SET @end_time = GETDATE();
        PRINT '!! ERROR in bronze.erp_px_cat_g1v2: ' + ERROR_MESSAGE();
        PRINT '>> Failed After: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '--------------------------------------------';
    END CATCH;

    SET @batch_end = GETDATE();
    PRINT '============================================';
    PRINT 'Loading Bronze Layer Completed At: ' + CAST(@batch_end AS NVARCHAR);
    PRINT 'Total Batch Duration: ' + CAST(DATEDIFF(SECOND, @batch_start, @batch_end) AS NVARCHAR) + ' seconds';
    PRINT '============================================';

END
GO
EXEC bronze.load_bronze;

