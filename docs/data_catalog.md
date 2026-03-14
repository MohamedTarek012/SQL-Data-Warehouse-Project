# Data Catalog
## Sales Data Warehouse Project

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Data Sources](#data-sources)
4. [Bronze Layer](#bronze-layer)
5. [Silver Layer](#silver-layer)
6. [Gold Layer](#gold-layer)
7. [Data Lineage](#data-lineage)
8. [Naming Conventions](#naming-conventions)

---

## Project Overview

| Property         | Value                                        |
|-----------------|----------------------------------------------|
| Project Name     | Sales Data Warehouse                         |
| Database         | Microsoft SQL Server                         |
| Architecture     | Medallion (Bronze → Silver → Gold)           |
| Schema Pattern   | Star Schema (Gold layer)                     |
| Sources          | CRM System + ERP System                      |
| Total Fact Rows  | 60,398 sales transactions                    |
| Total Customers  | 18,484                                       |
| Total Products   | 397 (versions) / 197 active                  |

---

## Architecture

> 📌 **Figure 1 – High-Level Data Architecture**
>
> ![High-Level Data Architecture](figures/01_high_level_architecture.png)
>
> *Place your high-level architecture diagram here.*

---

## Data Sources

Two operational systems feed the warehouse. Files from each system are loaded into the Bronze layer without transformation.

| System | File Naming  | Tables                                          |
|--------|--------------|-------------------------------------------------|
| CRM    | lowercase    | `cust_info`, `prd_info`, `sales_details`        |
| ERP    | UPPERCASE    | `CUST_AZ12`, `LOC_A101`, `PX_CAT_G1V2`         |

### CRM Source Files

#### `cust_info.csv`  —  Customer Master
| Column               | Type    | Description                        |
|---------------------|---------|------------------------------------|
| `cst_id`            | Integer | Customer unique identifier         |
| `cst_key`           | String  | Customer business key (AW00011000) |
| `cst_firstname`     | String  | First name                         |
| `cst_lastname`      | String  | Last name                          |
| `cst_marital_status`| String  | Marital status code (M / S)        |
| `cst_gndr`          | String  | Gender code (M / F)                |
| `cst_create_date`   | String  | Account creation date DD/MM/YYYY   |

**Rows:** 18,494  |  **Issues found:** 4 NULL cst_id, 6 duplicate cst_key, trailing whitespace in names

---

#### `prd_info.csv`  —  Product Catalogue
| Column        | Type    | Description                                     |
|--------------|---------|-------------------------------------------------|
| `prd_id`     | Integer | Product version unique identifier               |
| `prd_key`    | String  | Full product key (CO-RF-FR-R92B-58)             |
| `prd_nm`     | String  | Product name                                    |
| `prd_cost`   | Float   | Product standard cost                           |
| `prd_line`   | String  | Product line code (R / M / S / T)               |
| `prd_start_dt`| String | Version start date DD/MM/YYYY                   |
| `prd_end_dt` | String  | Version end date DD/MM/YYYY                     |

**Rows:** 397  |  **Issues found:** 2 NULL cost, 17 NULL prd_line, 200 rows where end_dt < start_dt

---

#### `sales_details.csv`  —  Sales Transactions
| Column        | Type    | Description                            |
|--------------|---------|----------------------------------------|
| `sls_ord_num`| String  | Sales order number (SO43697)           |
| `sls_prd_key`| String  | Product sub-key join to prd_info       |
| `sls_cust_id`| Integer | Customer ID join to cust_info          |
| `sls_order_dt`| Integer | Order date YYYYMMDD                   |
| `sls_ship_dt`| Integer | Ship date YYYYMMDD                     |
| `sls_due_dt` | Integer | Due date YYYYMMDD                      |
| `sls_sales`  | Float   | Total sales amount                     |
| `sls_quantity`| Integer| Units sold                             |
| `sls_price`  | Float   | Unit price                             |

**Rows:** 60,398  |  **Issues found:** 17 invalid order dates (≤0), 19 rows where sales ≠ qty × price, negative prices

---

### ERP Source Files

#### `CUST_AZ12.csv`  —  Customer Demographics
| Column  | Type   | Description                              |
|--------|--------|------------------------------------------|
| `CID`  | String | Customer ID (NASAW00011000 format)       |
| `BDATE`| String | Birthdate DD/MM/YYYY                     |
| `GEN`  | String | Gender (Male / Female / M / F / blank)   |

**Rows:** 18,484  |  **Issues found:** 1,472 NULL gender, 16 future birthdates, mixed gender formats, 'NAS' prefix on CID

---

#### `LOC_A101.csv`  —  Customer Location
| Column  | Type   | Description                            |
|--------|--------|----------------------------------------|
| `CID`  | String | Customer ID (AW-00011000 format)       |
| `CNTRY`| String | Country name                           |

**Rows:** 18,484  |  **Issues found:** 332 NULL country, country abbreviations (US, USA, DE)

---

#### `PX_CAT_G1V2.csv`  —  Product Categories
| Column        | Type   | Description                        |
|--------------|--------|------------------------------------|
| `ID`         | String | Category ID (AC_BR format)         |
| `CAT`        | String | Top-level category name            |
| `SUBCAT`     | String | Sub-level category name            |
| `MAINTENANCE`| String | Maintenance required (Yes / No)    |

**Rows:** 37  |  **Issues found:** None

---

## Bronze Layer

Raw data loaded as-is from source files. No transformations applied. Preserves original values for auditability.

| Table                     | Source File         | Rows   | Schema |
|--------------------------|---------------------|--------|--------|
| `bronze.crm_cust_info`   | cust_info.csv       | 18,494 | CRM    |
| `bronze.crm_prd_info`    | prd_info.csv        | 397    | CRM    |
| `bronze.crm_sales_details`| sales_details.csv  | 60,398 | CRM    |
| `bronze.erp_cust_az12`   | CUST_AZ12.csv       | 18,484 | ERP    |
| `bronze.erp_loc_a101`    | LOC_A101.csv        | 18,484 | ERP    |
| `bronze.erp_px_cat_g1v2` | PX_CAT_G1V2.csv     | 37     | ERP    |

---

## Silver Layer

Cleaned and standardised tables. Loaded via `EXEC silver.load_silver`. All six tables are truncated and re-inserted on every run (full refresh).

> 📌 **Figure 2 – Integration Model**
>
> ![Integration Model](docs/integration_model.png)
>
> *Place your integration model diagram here — showing how the six Silver tables relate to each other and what keys connect them.*

---

### `silver.crm_prd_info`

| Column          | Type          | Cleaned From         | Transformation Applied                                                  |
|----------------|---------------|----------------------|-------------------------------------------------------------------------|
| `prd_id`        | INT           | `prd_id`             | No change                                                               |
| `prd_key`       | NVARCHAR(50)  | `prd_key`            | No change                                                               |
| `prd_sub_key`   | NVARCHAR(50)  | `prd_key` (derived)  | Segments [2:] joined by '-' → join key to sales                        |
| `cat_id`        | NVARCHAR(10)  | `prd_key` (derived)  | Segments [0]\_[1] joined by '_' → join key to ERP categories           |
| `prd_nm`        | NVARCHAR(100) | `prd_nm`             | No change                                                               |
| `prd_cost`      | DECIMAL(10,2) | `prd_cost`           | NULL → 0                                                                |
| `prd_line`      | NVARCHAR(20)  | `prd_line`           | TRIM + R→Road, M→Mountain, S→Other Sale, T→Touring, else→N/A           |
| `prd_start_dt`  | DATE          | `prd_start_dt`       | DD/MM/YYYY string → DATE (style 103)                                    |
| `prd_end_dt`    | DATE          | `prd_end_dt`         | Source discarded. Derived: LEAD(prd_start_dt)−1 per prd_key            |
| `dwh_create_dt` | DATETIME2     | —                    | Audit column: GETDATE() at load time                                    |

**Rows:** 397

---

### `silver.crm_cust_info`

| Column               | Type          | Cleaned From           | Transformation Applied                                     |
|--------------------- |---------------|------------------------|------------------------------------------------------------|
| `cst_id`             | INT           | `cst_id`               | NULL rows dropped; FLOAT → INT                             |
| `cst_key`            | NVARCHAR(20)  | `cst_key`              | No change                                                  |
| `cst_firstname`      | NVARCHAR(50)  | `cst_firstname`        | LTRIM + RTRIM                                              |
| `cst_lastname`       | NVARCHAR(50)  | `cst_lastname`         | LTRIM + RTRIM                                              |
| `cst_marital_status` | NVARCHAR(10)  | `cst_marital_status`   | M→Married, S→Single, else→N/A                              |
| `cst_gndr`           | NVARCHAR(10)  | `cst_gndr`             | M→Male, F→Female, else→N/A                                 |
| `cst_create_date`    | DATE          | `cst_create_date`      | DD/MM/YYYY string → DATE (style 103)                       |
| `dwh_create_dt`      | DATETIME2     | —                      | Audit column: GETDATE() at load time                       |

**Rows:** 18,484  (4 NULL cst_id dropped, 6 duplicates resolved — latest record kept)

---

### `silver.crm_sales_details`

| Column        | Type           | Cleaned From    | Transformation Applied                                          |
|--------------|----------------|-----------------|------------------------------------------------------------------|
| `sls_ord_num` | NVARCHAR(20)   | `sls_ord_num`   | No change                                                        |
| `sls_prd_key` | NVARCHAR(50)   | `sls_prd_key`   | No change                                                        |
| `sls_cust_id` | INT            | `sls_cust_id`   | No change                                                        |
| `sls_order_dt`| DATE           | `sls_order_dt`  | INT YYYYMMDD → DATE; value ≤ 0 → NULL (17 rows)                  |
| `sls_ship_dt` | DATE           | `sls_ship_dt`   | INT YYYYMMDD → DATE                                              |
| `sls_due_dt`  | DATE           | `sls_due_dt`    | INT YYYYMMDD → DATE                                              |
| `sls_sales`   | DECIMAL(12,2)  | `sls_sales`     | Negative → ABS; NULL → qty×price; recalculated if ≠ qty×price   |
| `sls_quantity`| INT            | `sls_quantity`  | No change                                                        |
| `sls_price`   | DECIMAL(10,2)  | `sls_price`     | Negative → ABS; NULL → sales/qty                                 |
| `dwh_create_dt`| DATETIME2     | —               | Audit column: GETDATE() at load time                             |

**Rows:** 60,398

---

### `silver.erp_px_cat_g1v2`

| Column          | Type         | Cleaned From    | Transformation Applied             |
|----------------|--------------|-----------------|-------------------------------------|
| `id`            | NVARCHAR(10) | `ID`            | LTRIM + RTRIM                       |
| `cat`           | NVARCHAR(50) | `CAT`           | LTRIM + RTRIM                       |
| `subcat`        | NVARCHAR(50) | `SUBCAT`        | LTRIM + RTRIM                       |
| `maintenance`   | BIT          | `MAINTENANCE`   | Yes→1, No→0                         |
| `dwh_create_dt` | DATETIME2    | —               | Audit column: GETDATE() at load time|

**Rows:** 37

---

### `silver.erp_loc_a101`

| Column          | Type         | Cleaned From | Transformation Applied                                   |
|----------------|--------------|--------------|-----------------------------------------------------------|
| `cid`           | NVARCHAR(20) | `CID`        | REPLACE('-','') → AW-00011000 becomes AW00011000          |
| `cntry`         | NVARCHAR(50) | `CNTRY`      | US/USA→United States, DE→Germany, NULL→Unknown            |
| `dwh_create_dt` | DATETIME2    | —            | Audit column: GETDATE() at load time                      |

**Rows:** 18,484

---

### `silver.erp_cust_az12`

| Column          | Type         | Cleaned From | Transformation Applied                                        |
|----------------|--------------|--------------|----------------------------------------------------------------|
| `cid`           | NVARCHAR(20) | `CID`        | Strip 'NAS' prefix → NASAW00011000 becomes AW00011000         |
| `bdate`         | DATE         | `BDATE`      | DD/MM/YYYY → DATE; future dates → NULL (16 rows)              |
| `gen`           | NVARCHAR(10) | `GEN`        | Male/M→Male, Female/F→Female, blank/NULL→N/A                  |
| `dwh_create_dt` | DATETIME2    | —            | Audit column: GETDATE() at load time                          |

**Rows:** 18,484

---

## Gold Layer

Business-ready views on top of Silver. No physical storage — always reflects the latest Silver state. Star schema pattern.

> 📌 **Figure 3 – Data Flow**
>
> ![Data Flow](docs/data-flow-diagram.png)
>
> *Place your data flow diagram here — showing the end-to-end movement of data from source files through Bronze → Silver → Gold and into reporting.*

---

### `gold.dim_customers`

**Purpose:** Unified customer profile — identity, demographics, location.

| Column                | Type         | Source                              | Description                                      |
|----------------------|--------------|-------------------------------------|--------------------------------------------------|
| `customer_key`        | INT          | `ROW_NUMBER() OVER (ORDER BY cst_id)` | **Surrogate PK** — referenced by fact_sales    |
| `customer_id`         | INT          | `crm_cust_info.cst_id`              | CRM natural key (integer)                        |
| `customer_number`     | NVARCHAR     | `crm_cust_info.cst_key`             | CRM business key (AW00011000)                    |
| `first_name`          | NVARCHAR     | `crm_cust_info.cst_firstname`       | First name, whitespace trimmed                   |
| `last_name`           | NVARCHAR     | `crm_cust_info.cst_lastname`        | Last name, whitespace trimmed                    |
| `country`             | NVARCHAR     | `erp_loc_a101.cntry`                | Country of residence. COALESCE to 'N/A'          |
| `marital_status`      | NVARCHAR     | `crm_cust_info.cst_marital_status`  | Married / Single / N/A                           |
| `gender`              | NVARCHAR     | CRM master, ERP fallback            | CRM takes priority; ERP used when CRM is 'N/A'  |
| `birth_date`          | DATE         | `erp_cust_az12.bdate`               | Date of birth from ERP                           |
| `customer_create_date`| DATE         | `crm_cust_info.cst_create_date`     | CRM account creation date                        |

**Rows:** 18,484  |  **Filter:** `WHERE cst_id IS NOT NULL`

---

### `gold.dim_products`

**Purpose:** Unified product catalogue — details and ERP category hierarchy. Active records only.

| Column                 | Type         | Source                          | Description                                    |
|-----------------------|--------------|---------------------------------|------------------------------------------------|
| `product_key`          | INT          | `crm_prd_info.prd_id`           | **Surrogate PK** — referenced by fact_sales    |
| `product_id`           | NVARCHAR     | `crm_prd_info.cat_id`           | Category-level product ID                      |
| `product_number`       | NVARCHAR     | `crm_prd_info.prd_sub_key`      | Sub-key used to join to sales transactions     |
| `product_name`         | NVARCHAR     | `crm_prd_info.prd_nm`           | Human-readable product name                    |
| `product_cost`         | DECIMAL      | `crm_prd_info.prd_cost`         | Standard cost (NULL replaced with 0 in Silver) |
| `product_line`         | NVARCHAR     | `crm_prd_info.prd_line`         | Road / Mountain / Other Sale / Touring / N/A   |
| `start_date`           | DATE         | `crm_prd_info.prd_start_dt`     | Version effective start date                   |
| `category`             | NVARCHAR     | `erp_px_cat_g1v2.cat`           | Top-level ERP category                         |
| `subcategory`          | NVARCHAR     | `erp_px_cat_g1v2.subcat`        | Sub-level ERP category                         |
| `maintenance_required` | BIT          | `erp_px_cat_g1v2.maintenance`   | 1 = Yes, 0 = No                                |

**Rows:** 197 (active only)  |  **Filter:** `WHERE prd_end_dt IS NULL`

---

### `gold.fact_sales`

**Purpose:** Grain = one sales order line. All measurable facts with surrogate FKs to both dimensions.

| Column         | Type         | Source                            | Description                                               |
|---------------|--------------|-----------------------------------|-----------------------------------------------------------|
| `customer_key` | INT          | `gold.dim_customers.customer_key` | **FK → dim_customers** (many-to-one)                      |
| `product_key`  | INT          | `gold.dim_products.product_key`   | **FK → dim_products**  (many-to-one)                      |
| `order_number` | NVARCHAR     | `crm_sales_details.sls_ord_num`   | Degenerate dimension — order identifier                   |
| `order_date`   | DATE         | `crm_sales_details.sls_order_dt`  | Date order was placed                                     |
| `ship_date`    | DATE         | `crm_sales_details.sls_ship_dt`   | Date order was shipped                                    |
| `due_date`     | DATE         | `crm_sales_details.sls_due_dt`    | Date order was due                                        |
| `sales_amount` | DECIMAL      | `crm_sales_details.sls_sales`     | Total line value (recalculated in Silver where corrupted) |
| `quantity`     | INT          | `crm_sales_details.sls_quantity`  | Units sold                                                |
| `unit_price`   | DECIMAL      | `crm_sales_details.sls_price`     | Price per unit (always positive after Silver cleaning)    |

**Rows:** 60,398

---

## Data Lineage

```
CRM  cust_info.csv       →  bronze.crm_cust_info   →  silver.crm_cust_info   ──┐
ERP  CUST_AZ12.csv       →  bronze.erp_cust_az12   →  silver.erp_cust_az12   ──┼──►  gold.dim_customers
ERP  LOC_A101.csv        →  bronze.erp_loc_a101    →  silver.erp_loc_a101    ──┘

CRM  prd_info.csv        →  bronze.crm_prd_info    →  silver.crm_prd_info    ──┐
ERP  PX_CAT_G1V2.csv     →  bronze.erp_px_cat_g1v2 →  silver.erp_px_cat_g1v2──┘──►  gold.dim_products

CRM  sales_details.csv   →  bronze.crm_sales_details→ silver.crm_sales_details──►   gold.fact_sales
                                                                                          │
                                                        gold.dim_customers  ◄────────────┤ customer_key
                                                        gold.dim_products   ◄────────────┘ product_key
```

---

## Naming Conventions

| Element          | Convention     | Example                   |
|-----------------|----------------|---------------------------|
| Schema names     | lowercase      | `bronze`, `silver`, `gold`|
| Table names      | snake_case     | `crm_cust_info`           |
| Column names     | snake_case     | `customer_key`            |
| Source prefix    | system_entity  | `crm_`, `erp_`            |
| Surrogate keys   | `_key` suffix  | `customer_key`            |
| Natural keys     | `_id` / `_number` | `customer_id`, `customer_number` |
| Audit column     | `dwh_create_dt`| present in all Silver tables |
| Date columns     | `_dt` / `_date`| `order_date`, `prd_start_dt` |
| Flag columns     | BIT 1/0        | `maintenance_required`    |
