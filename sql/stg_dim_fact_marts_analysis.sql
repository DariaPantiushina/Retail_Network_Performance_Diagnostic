-------------------------------------------------------
-- 01_stg
-------------------------------------------------------
DROP TABLE IF EXISTS marts.marts_sales_region_month;
DROP TABLE IF EXISTS marts.marts_avgcheck_ci_region_last90;
DROP TABLE IF EXISTS marts.marts_sales_cohort_region;
DROP TABLE IF EXISTS marts.marts_sales_region_last90;
DROP TABLE IF EXISTS fact.fact_sales_case;
DROP TABLE IF EXISTS dim.dim_date_case;
DROP TABLE IF EXISTS dim.dim_stores_case;
DROP TABLE IF EXISTS dim.dim_regions_case;
DROP TABLE IF EXISTS stg.sales_case;
DROP TABLE IF EXISTS stg.stores_case;
DROP TABLE IF EXISTS stg.regions_case;
DROP TABLE IF EXISTS stg.stg_sales_case;
DROP TABLE IF EXISTS stg.stg_stores_case;
DROP TABLE IF EXISTS stg.stg_regions_case;
DROP TABLE IF EXISTS stg.stg_sales_case_clean;
DROP TABLE IF EXISTS stg.stg_stores_case_clean;
DROP TABLE IF EXISTS stg.stg_regions_case_clean;

CREATE TABLE stg.regions_case (
  region        VARCHAR(255) PRIMARY KEY,
  population    BIGINT NOT NULL,
  avg_income    DECIMAL(10,2) NOT NULL
);
	
CREATE TABLE stg.stores_case (
  store_id      BIGINT PRIMARY KEY,
  city          VARCHAR(255) NOT NULL,
  region        VARCHAR(255) NOT NULL,
  opening_date  DATE NOT NULL,
  CONSTRAINT fk_stores_region
    FOREIGN KEY (region) REFERENCES stg.regions_case(region)
);

CREATE TABLE stg.sales_case (
  store_id      BIGINT NOT NULL,
  date          DATE NOT NULL,
  revenue       DECIMAL(12,2) NOT NULL,
  transactions  INT NOT NULL,
  PRIMARY KEY (store_id, date),
  CONSTRAINT fk_sales_store
    FOREIGN KEY (store_id) REFERENCES stg.stores_case(store_id),
  CONSTRAINT chk_transactions_nonneg CHECK (transactions >= 0),
  CONSTRAINT chk_revenue_nonneg CHECK (revenue >= 0)
);

-------------------------------------------------------
-------------------------------------------------------

CREATE TABLE stg.stg_regions_case_clean AS
SELECT DISTINCT
    TRIM(region) AS region,
    population::BIGINT AS population,
    ROUND(avg_income::NUMERIC, 2) AS avg_income
FROM stg.regions_case
WHERE region IS NOT NULL
  AND population > 0
  AND avg_income >= 0;

ALTER TABLE stg.stg_regions_case_clean ADD PRIMARY KEY (region);

-------------------------------------------------------

CREATE TABLE stg.stg_stores_case_clean AS
SELECT DISTINCT
    store_id::BIGINT AS store_id,
    TRIM(city) AS city,
    TRIM(region) AS region,
    opening_date::DATE AS opening_date
FROM stg.stores_case
WHERE store_id IS NOT NULL
  AND region IS NOT NULL;

ALTER TABLE stg.stg_stores_case_clean ADD PRIMARY KEY (store_id);

-------------------------------------------------------

CREATE TABLE stg.stg_sales_case_clean AS
SELECT DISTINCT
    store_id::BIGINT AS store_id,
    date::DATE AS date,
    ROUND(revenue::NUMERIC, 2) AS revenue,
    transactions::INT AS transactions
FROM stg.sales_case
WHERE revenue >= 0
  AND transactions >= 0;

ALTER TABLE stg.stg_sales_case_clean ADD PRIMARY KEY (store_id, date);

-------------------------------------------------------
-- 02_dim
-------------------------------------------------------

CREATE TABLE dim.dim_regions_case (
    region_id     SERIAL PRIMARY KEY,
    region        VARCHAR(255) UNIQUE,
    population    BIGINT,
    avg_income    NUMERIC(10,2)
);

-- 
CREATE TABLE dim.dim_stores_case (
    store_id      BIGINT PRIMARY KEY,
    city          VARCHAR(255),
    region_id     INT REFERENCES dim.dim_regions_case(region_id),
    opening_date  DATE
);

--
CREATE TABLE dim.dim_date_case (
    date_id       DATE PRIMARY KEY,
    year          INT,
    quarter       INT,
    month         INT,
    day           INT,
    weekday       INT
);

-------------------------------------------------------
-- 03_fact 
-------------------------------------------------------
CREATE TABLE fact.fact_sales_case (
    store_id      BIGINT NOT NULL REFERENCES dim.dim_stores_case(store_id),
    date_id       DATE NOT NULL REFERENCES dim.dim_date_case(date_id),
    revenue       NUMERIC(12,2),
    transactions  INT,
    PRIMARY KEY (store_id, date_id)
);

-------------------------------------------------------
-- 04_marts
-------------------------------------------------------
CREATE TABLE marts.marts_sales_region_month (
    region              VARCHAR(255),
    year                INT,
    month               INT,
    total_revenue       NUMERIC(18,2),
    total_transactions  BIGINT,
    stores_count        INT
);

-------------------------------------------------------
-- 05_ETL
-------------------------------------------------------

-- dim_region
INSERT INTO dim.dim_regions_case (region, population, avg_income)
SELECT region, population, avg_income
FROM stg.stg_regions_case_clean
ON CONFLICT (region) DO UPDATE
SET population = EXCLUDED.population,
    avg_income = EXCLUDED.avg_income;

-- dim_store
INSERT INTO dim.dim_stores_case (store_id, city, region_id, opening_date)
SELECT 
    s.store_id,
    s.city,
    r.region_id,
    s.opening_date
FROM stg.stg_stores_case_clean s
JOIN dim.dim_regions_case r ON s.region = r.region
ON CONFLICT (store_id) DO UPDATE
SET city = EXCLUDED.city,
    region_id = EXCLUDED.region_id,
    opening_date = EXCLUDED.opening_date;

-- dim_date (calendar generation 2015-2030)
INSERT INTO dim.dim_date_case (date_id, year, quarter, month, day, weekday)
SELECT 
    d::DATE,
    EXTRACT(YEAR FROM d)::INT,
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(MONTH FROM d)::INT,
    EXTRACT(DAY FROM d)::INT,
    EXTRACT(ISODOW FROM d)::INT
FROM generate_series('2015-01-01'::DATE, '2030-12-31'::DATE, '1 day') d
ON CONFLICT (date_id) DO NOTHING;

-------------------------------------------------------
-------------------------------------------------------

-- fact
INSERT INTO fact.fact_sales_case (store_id, date_id, revenue, transactions)
SELECT 
    s.store_id,
    s.date,
    s.revenue,
    s.transactions
FROM stg.stg_sales_case_clean s
JOIN dim.dim_stores_case ds ON s.store_id = ds.store_id
JOIN dim.dim_date_case dd ON s.date = dd.date_id
ON CONFLICT (store_id, date_id) DO UPDATE
SET revenue = EXCLUDED.revenue,
    transactions = EXCLUDED.transactions;

-------------------------------------------------------
-------------------------------------------------------

-- marts
TRUNCATE TABLE marts.marts_sales_region_month;
INSERT INTO marts.marts_sales_region_month
SELECT 
    dr.region,
    dd.year,
    dd.month,
    SUM(fs.revenue) AS total_revenue,
    SUM(fs.transactions) AS total_transactions,
    COUNT(DISTINCT fs.store_id) AS stores_count
FROM fact.fact_sales_case fs
JOIN dim.dim_stores_case ds ON fs.store_id = ds.store_id
JOIN dim.dim_regions_case dr ON ds.region_id = dr.region_id
JOIN dim.dim_date_case dd ON fs.date_id = dd.date_id
GROUP BY dr.region, dd.year, dd.month;

-------------------------------------------------------
-- 06_analysis
-------------------------------------------------------

-- 1) AOV by region + Confidence Interval (CI)

DROP TABLE IF EXISTS marts.marts_avgcheck_ci_region_last90;
CREATE TABLE marts.marts_avgcheck_ci_region_last90 AS
WITH max_date_cte AS (
    SELECT MAX(date_id) AS max_date
    FROM fact.fact_sales_case
)
SELECT 
    dr.region,
    AVG(fs.revenue::NUMERIC / NULLIF(fs.transactions, 0)) AS avg_check,
    STDDEV(fs.revenue::NUMERIC / NULLIF(fs.transactions, 0)) / SQRT(COUNT(*)) AS std_error,
    AVG(fs.revenue::NUMERIC / NULLIF(fs.transactions, 0)) 
        - 1.96 * (STDDEV(fs.revenue::NUMERIC / NULLIF(fs.transactions, 0)) / SQRT(COUNT(*))) AS ci_lower,
    AVG(fs.revenue::NUMERIC / NULLIF(fs.transactions, 0)) 
        + 1.96 * (STDDEV(fs.revenue::NUMERIC / NULLIF(fs.transactions, 0)) / SQRT(COUNT(*))) AS ci_upper
FROM fact.fact_sales_case fs
JOIN dim.dim_stores_case ds ON fs.store_id = ds.store_id
JOIN dim.dim_regions_case dr ON ds.region_id = dr.region_id
CROSS JOIN max_date_cte md
WHERE fs.date_id >= md.max_date - INTERVAL '90 day'
GROUP BY dr.region
ORDER BY avg_check DESC;

-- 2) Average Revenue: Cohort Analysis by Store Age & Region Group

DROP TABLE IF EXISTS marts_sales_cohort_region;
CREATE TABLE marts.marts_sales_cohort_region AS
WITH max_date_cte AS (
    SELECT MAX(date_id) AS max_date
    FROM fact.fact_sales_case
)
SELECT 
    dr.region,
    CASE 
        WHEN dr.avg_income >= 45000 THEN 'Rich'
        WHEN dr.avg_income <= 26000 THEN 'Depressed'
        ELSE 'Moderate'
    END AS region_group,
    DATE_TRUNC('month', ds.opening_date)::DATE AS cohort_month,
    DATE_TRUNC('month', fs.date_id)::DATE AS sales_month,
    AVG(fs.revenue) AS avg_revenue
FROM fact.fact_sales_case fs
JOIN dim.dim_stores_case ds ON fs.store_id = ds.store_id
JOIN dim.dim_regions_case dr ON ds.region_id = dr.region_id
CROSS JOIN max_date_cte md
WHERE fs.date_id >= md.max_date - INTERVAL '1 year'
GROUP BY dr.region, region_group, cohort_month, sales_month
ORDER BY dr.region, cohort_month, sales_month;

-- 3) Decomposition of "revenue = traffic × AOV"

DROP TABLE IF EXISTS marts.marts_sales_region_last90;
CREATE TABLE marts.marts_sales_region_last90 AS
WITH max_date_cte AS (
    SELECT MAX(date_id) AS max_date
    FROM fact.fact_sales_case
)
SELECT 
    dr.region,
    CASE 
        WHEN dr.avg_income >= 45000 THEN 'Rich'
        WHEN dr.avg_income <= 26000 THEN 'Depressed'
        ELSE 'Moderate'
    END AS region_group,
    SUM(fs.revenue) AS total_revenue,
    SUM(fs.transactions) AS total_transactions,
    SUM(fs.revenue)::NUMERIC / NULLIF(SUM(fs.transactions), 0) AS avg_check
FROM fact.fact_sales_case fs
JOIN dim.dim_stores_case ds ON fs.store_id = ds.store_id
JOIN dim.dim_regions_case dr ON ds.region_id = dr.region_id
CROSS JOIN max_date_cte md
WHERE fs.date_id >= md.max_date - INTERVAL '90 day'
GROUP BY dr.region, region_group
ORDER BY dr.region;

-- 4) Regression: household income as an AOV Factor (SQL + Python)

WITH max_date_cte AS (
    SELECT MAX(date_id) AS max_date
    FROM fact.fact_sales_case
)
SELECT 
    dr.region,
    CASE
        WHEN ds.opening_date >= md.max_date - INTERVAL '1 year'
        THEN 'new'
        ELSE 'old'
    END AS store_age,
    AVG(fs.revenue::NUMERIC / NULLIF(fs.transactions, 0)) AS avg_check,
    dr.avg_income,
    dr.population
FROM fact.fact_sales_case fs
JOIN dim.dim_stores_case ds ON fs.store_id = ds.store_id
JOIN dim.dim_regions_case dr ON ds.region_id = dr.region_id
CROSS JOIN max_date_cte md
WHERE fs.date_id >= md.max_date - INTERVAL '90 day'
GROUP BY dr.region, store_age, dr.avg_income, dr.population
ORDER BY dr.region, store_age;

-- 5) Modeling within a region: managerial and operational differences (SQL + Python)

WITH max_date_cte AS (
    SELECT MAX(date_id) AS max_date
    FROM fact.fact_sales_case
)
SELECT
    fs.revenue,
    dr.avg_income,
    CASE
        WHEN ds.opening_date >= md.max_date - INTERVAL '1 year'
        THEN 'new'
        ELSE 'old'
    END AS store_age,
    dr.region
FROM fact.fact_sales_case fs
JOIN dim.dim_stores_case ds ON fs.store_id = ds.store_id
JOIN dim.dim_regions_case dr ON ds.region_id = dr.region_id
CROSS JOIN max_date_cte md
WHERE fs.date_id >= md.max_date - INTERVAL '90 day';