# Retail Network Performance Diagnostic

**Business context**: The company is a large retail chain operating more than 500 stores. Management is concerned that some stores not only show weak performance, but also drag down the overall profitability of their respective regions.

**Task**: to analyze performance data to uncover key patterns and explain the drivers of regional and store-level variation.

**Clarifying questions**:

1) Anomalies: how should we handle potential anomalies such as returns, test transactions, or AOV outliers, which may introduce noise into the regression?

2) Normalization: should we normalize or scale results by regional factors such as average income and population size to ensure comparability across regions?

3) Significance testing: are the observed differences between groups statistically significant and stable, or could they be explained by random noise in the data?

**Hypotheses**:

1) Regions with lower income and smaller populations tend to exhibit constrained demand potential (verification via **linear regression**);
   
2) Demand structure: regional demand profiles differ - some markets are frequency-driven, while others are value- or price-driven with higher average checks. Verification through 1) **factor analysis**: revenue = transactions × AOV, 2) **Principal Component Analysis (PCA)** on standardized features {total_transactions, avg_check} to assess whether one principal component explains most of the variation in revenue;

3) Store life cycle: new stores grow at different rates - verification via **cohort analysis**;

4) Even within a single region, stores exhibit substantial performance differences, reflecting managerial and operational factors (verification: **mixed-effects** regression (revenue ~ avg_income + store_age + (1|region))  

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

The collected aggregates and results of the statistical analysis are provided in the following files: ["stg_dim_fact_marts_analysis"](sql/stg_dim_fact_marts_analysis.sql) & ["stat_analysis"](python/analysis.ipynb):

1) AOV by region + confidence interval;

2) Regional differences: ANOVA + post-hoc test (Tukey HSD);

3) Regression: Evaluating household income as a factor influencing AOV. The model specification is: AOV ~ avg_income + population + store_age;

4) Modeling within regions to capture managerial and operational heterogeneity;

5) Cohort analysis: store-age cohorts compared by growth rate across regions;

6) Revenue = traffic × AOV → helps pinpoint whether issues come from traffic or average check;
   
7) Principal Component Analysis (PCA) based on transaction frequency and average check → reveals distinct market types:

- regions with high PC2 values are price-driven (revenue primarily driven by higher checks),

- while those with low PC2 values are volume-driven (revenue driven by transaction frequency).

## Creating a Dashboard in Power BI

["Dashboard"](power_bi/dashboard.pdf) structure includes the following key blocks:

1) KPI Blocks: Total Revenue, Total Transactions;

2) Bar Charts: Top 10 Regions with the Highest Average Check (AOV + CI) - leading regions: Bavaria, North Holland, Île-de-France; Top 10 Regions with the Lowest Average Check (AOV + CI) - lagging regions: West Pomerania, Hauts-de-France, Podkarpackie;

3) Scatter Plot: "Total Revenue by Total Transactions and Average Check" - shows the relationship between transaction volume and average check across regions;

4) Cohort Line Charts: "Average Revenue: Cohort Analysis by Store Age & Region Group" - segmented into three region groups (Depressed, Moderate, Rich), showing average revenue trends by cohort month (2024-01 to 2024-12)

## Findings & Business Insights & Recommendations
