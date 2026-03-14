-- ============================================================================================================================
-- GOLD LAYER : View  –  gold.dim_products
-- ============================================================================================================================
-- Purpose      : Unified product catalogue combining product details and ERP category hierarchy.
-- Sources      : silver.crm_prd_info      (master – product identity, cost, line, dates)
--                silver.erp_px_cat_g1v2   (category, subcategory, maintenance flag)
-- Surrogate key: product_key = prd_id
--                prd_id is a stable integer, unique per product version row in Silver.
--                Acts as the PK of this dimension and FK in gold.fact_sales.
-- -- Surrogate : product_key  (ROW_NUMBER)
-- ============================================================================================================================
IF OBJECT_ID('gold.dim_products', 'V') IS NOT NULL
    DROP VIEW gold.dim_products;
GO

CREATE VIEW gold.dim_products AS
SELECT
    -- Surrogate key  (PK of this dimension | FK in fact_sales)
        ROW_NUMBER() OVER (ORDER BY  p.prd_start_dt, p.prd_sub_key)        AS product_key,

     p.prd_id                   AS product_id,

    -- Natural / business key
     p.cat_id                   AS catagory_id,
     p.prd_sub_key              AS product_number, 
    p.prd_nm                    AS product_name,
    p.prd_cost                  AS product_cost,
    p.prd_line                  AS product_line,

    -- Validity window  (SCD Type 2 columns)
    p.prd_start_dt              AS start_date,

    -- ERP category hierarchy
    c.cat                       AS category,
    c.subcat                    AS subcategory,
    c.maintenance               AS maintenance_required  -- 1 = Yes | 0 = No

FROM silver.crm_prd_info         p

-- LEFT JOIN : keep all products even if ERP category mapping is absent (7 unmatched rows)
LEFT JOIN silver.erp_px_cat_g1v2 c  ON p.cat_id = c.id
wHERE prd_end_dt IS NULL;

GO
select * from gold.dim_products
