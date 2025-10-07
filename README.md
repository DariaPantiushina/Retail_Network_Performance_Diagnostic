# Retail Network Performance Diagnostic

**Business context**: The company is a large retail chain operating more than 500 stores. Management is concerned that some stores not only show weak performance, but also drag down the overall profitability of their respective regions.

**Task**: to analyze performance data to uncover key patterns and explain the drivers of regional and store-level variation.

**Clarifying questions**:

1) Anomalies: how should we handle potential anomalies such as returns, test transactions, or AOV outliers, which may introduce noise into the regression?

2) Normalization: should we normalize or scale results by regional factors such as average income and population size to ensure comparability across regions?

3) Significance testing: are the observed differences between groups statistically significant and stable, or could they be explained by random noise in the data?

## Data Mart Schema

The architecture of the data mart includes **four layers**:

1. stg_ (**Staging**): includes light data cleaning (data type conversions, removal of explicit duplicates, etc.).

- **stg_regions_case_clean**(region, population, avg_income);
  
- **stg_stores_case_clean**(store_id, city, region, opening_date);

- **stg_sales_case_clean**(store_id, date, revenue, transactions)

2. dim_ (**Dimensions**): contains reference tables for consistent dimension data.

- **dim_regions_case**(region_id, region, population, avg_income);

- **dim_stores_case**(store_id, city, region_id, opening_date);

- **dim_date_case**(date_id, year, quarter, month, day, weekday)

3. fact_ (**Facts**): contains fact tables with transactional data.

- **fact_sales_case**(store_id, date_id, revenue, transactions)

4. marts_ (**Analytics Marts**): contains aggregated summary tables for reporting and visualization.

- **marts_sales_region_month**(region, year, month, total_revenue, total_transactions, stores_count);

- **marts_avgcheck_ci_region_last90**(region, avg_check, std_error, ci_lower, ci_upper);

- **marts_sales_cohort_region**(region, region_group, cohort_month, sales_month, avg_revenue);

- **marts_sales_region_last90**(region, region_group, total_revenue, total_transactions, avg_check) 

## SQL & Python Analysis
