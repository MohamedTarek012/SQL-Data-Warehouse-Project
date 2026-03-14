-- ============================================================================================================================
-- GOLD LAYER : View  –  gold.fact_sales
-- ============================================================================================================================
-- Purpose      : Grain-level sales transactions. One row = one sales order line.
--                Contains measurable facts and surrogate foreign keys to both dimensions.
-- Source       : silver.crm_sales_details   (transaction rows)
--                gold.dim_customers         (lookup surrogate customer_key via customer_id = cst_id)
--                gold.dim_products          (lookup surrogate product_key  via product_number = prd_sub_key)
-- Relationships:
--                fact_sales.customer_key  ->  gold.dim_customers.customer_key  (many-to-one)
--                fact_sales.product_key   ->  gold.dim_products.product_key    (many-to-one)
-- Notes        : dim_products already filters WHERE prd_end_dt IS NULL (active version only)
--                so no extra date filter is needed in this view.
-- ============================================================================================================================
IF OBJECT_ID('gold.fact_sales', 'V') IS NOT NULL
    DROP VIEW gold.fact_sales;
GO

CREATE VIEW gold.fact_sales AS
SELECT
    -- Surrogate foreign keys  (pulled from dim views)
    dc.customer_key,                            -- FK -> gold.dim_customers.customer_key
    dp.product_key,                             -- FK -> gold.dim_products.product_key

    -- Degenerate dimension
    s.sls_ord_num               AS order_number,

    -- Dates
    s.sls_order_dt              AS order_date,
    s.sls_ship_dt               AS ship_date,
    s.sls_due_dt                AS due_date,

    -- Measures
    s.sls_sales                 AS sales_amount,
    s.sls_quantity              AS quantity,
    s.sls_price                 AS unit_price

FROM silver.crm_sales_details   s

-- customer_key : sls_cust_id matches dim_customers.customer_id (= cst_id)
LEFT JOIN gold.dim_customers    dc
    ON  s.sls_cust_id = dc.customer_id

-- product_key  : sls_prd_key matches dim_products.product_number (= prd_sub_key)
--               dim_products is already filtered to active records only
LEFT JOIN gold.dim_products     dp
    ON  s.sls_prd_key = dp.product_number;
GO

PRINT '>> View gold.fact_sales created successfully.';
 select * from gold.fact_sales
