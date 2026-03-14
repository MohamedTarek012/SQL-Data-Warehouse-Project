-- =============================================================================
-- GOLD LAYER | View: gold.dim_customers
-- =============================================================================
-- Purpose   : Customer dimension built from CRM master data enriched with
--             ERP birthdate / gender (erp_cust_az12) and country (erp_loc_a101)
-- Sources   : silver.crm_cust_info   (CRM – primary customer record)
--             silver.erp_cust_az12   (ERP – birthdate & gender)
--             silver.erp_loc_a101    (ERP – country)
-- Grain     : One row per customer (current snapshot)
-- Surrogate : customer_key  (ROW_NUMBER – deterministic via cst_id order)
-- ============================================================================

CREATE OR ALTER VIEW gold.dim_customers AS

SELECT
    -- -----------------------------------------------------------------------
    -- Surrogate key  (Primary key – referenced by fact_sales.customer_key)
    -- -----------------------------------------------------------------------
    ROW_NUMBER() OVER (ORDER BY crm.cst_id)        AS customer_key,

    -- -----------------------------------------------------------------------
    -- Natural / business keys
    -- -----------------------------------------------------------------------
    crm.cst_id                                      AS customer_id,
    crm.cst_key                                     AS customer_number,

    -- -----------------------------------------------------------------------
    -- Demographics
    -- -----------------------------------------------------------------------
    TRIM(crm.cst_firstname)                         AS first_name,
    TRIM(crm.cst_lastname)                          AS last_name,

    COALESCE(loc.cntry, 'n/a')                      AS country,

     crm.cst_marital_status AS marital_status,

    -- ? FIX: CRM takes priority
    --        Fallback to ERP only when CRM gender is truly absent.
    CASE WHEN crm.cst_gndr !='n/a' THEN crm.cst_gndr
        ELSE COALESCE (erp.gen,'na') 
     
    END                                             AS gender,

    TRY_CAST(erp.bdate AS DATE)                     AS birth_date,
    crm.cst_create_date                             AS customer_create_date

FROM silver.crm_cust_info  crm

-- ERP birthdate & gender  (cid already cleaned in Silver layer)
LEFT JOIN silver.erp_cust_az12  erp
    ON crm.cst_key = erp.cid

-- ERP country  (cid already cleaned in Silver layer)
LEFT JOIN silver.erp_loc_a101  loc
    ON crm.cst_key = loc.cid

WHERE crm.cst_id IS NOT NULL;
go
select * from gold.dim_customers
