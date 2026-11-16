## Metadata

| Table name                | D5_PS_ModelBuilding                                                                                                                                                                                                                                                               |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | File that describes the model building procedure for a propensity score model;<br />starting from an initial list of variables to be included in the model, <br />describing if each variable meets different data quality and/or data driven criteria to be included as relevant |
| Source                    | `data/D4_analytic_datasets/D4_StudyCohortCovariates.parquet`; `transformations/T4_statistical_analysis/metadata/psmodel_variables.csv`                                                                                                                                            |
| Step                      | `transformations/T4_statistical_analysis/source_code/compute_d4_StudyCohort_IPTW.R`; `transformations/T4_statistical_analysis/source_code/functions/compute_d4_StudyCohort_IPTW_function.R`                                                                                       |
| Content                   | Summarizes for each variable type data quality criteria such as missing pct, nonzero variance and whether the variable was included                                                                                                                                               |
| Population                | Candidate variables to be included in a propensity score model                                                                                                                                                                                                                    |
| Unit of Observation (UoO) | NA (row per variable)                                                                                                                                                                                                                                                             |

## Codebook

| Variable name    | Description                                                                                                                                                                                | Source used for the variable                                           | format    | rule_of_calculation                 | vocabulary       |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------- | --------- | ----------------------------------- | ---------------- |
| variable_id      | All candidate variables for PS models                                                                                                                                                      | transformations/T4_statistical_analysis/metadata/psmodel_variables.csv | Character |                                     |                  |
| var_type         | Variable type                                                                                                                                                                              | psmodel_variables.csv                                                  | Character |                                     | NUM; CAT; TF     |
| force_in         | does the ps_variables_metadata specify to force this variable into the model regardless of any data driven criteria.<br />only relevant when data driven criteria are used                 | psmodel_variables.csv                                                  | TF        |                                     |                  |
| force_out        | does the ps_variables_metadata specify to force this variable out of the model regardless of meeting data driven inclusion criteria.<br />only relevant when data driven criteria are used | psmodel_variables.csv                                                  | TF        |                                     |                  |
|                  |                                                                                                                                                                                            |                                                                        |           |                                     |                  |
| missing_pct      | Missing value percentage for the variable across all individuals                                                                                                                           | D4_StudyCohort_Covariates                                              | Numeric   | 100 \* sum(is.na(var)) / nrow(data) | \[0, 100\]       |
| nonzero_variance | does the variable have non-zero variance (i.e., not all individuals have the same covariate value in the cohort)                                                                           | D4_StudyCohort_Covariates                                              | TF        |                                     |                  |
| include_r1       | Whether the candidate variable is included in the initial model; i.e., should pass all of the data quality and data-driven inclusion criteria                                              | model fit round 1                                                      | TF        |                                     |                  |
| included_r2      | If variable meets all criteria to be included in the final propensity model                                                                                                                | fit_issue_r1, n_unique, pct_missing                                    | TF        |                                     |                  |
| reason_excluded  | Reason for exclusion; NA if included_r2 == TRUE                                                                                                                                            | fit_issue_r1, n_unique, pct_missing                                    | Character |                                     | Processing Steps |

## Processing Steps

1. Load `psmodel_variables.csv` to identify candidate variables for the PS model
2. For each candidate variable, compute data quality checks: count unique non-NA values (`nonzero_variance`), compute missing percentage (`missing_pct`). Since the code was programmed without data-access, this was needed to potentially avoid issues in data source.
3. Fit initial PS model (Round 1) with all variables passing data quality checks (`include_r1 = TRUE`). Check for fit issues (large SE, non-convergence) and record in `reason_excluded`
4. If fit issues found: exclude problematic variables (`included_r2 = FALSE`), refit model (Round 2). If no issues, Round 2 equals Round 1 and all R1 variables have `included_r2 = TRUE`. Returns output of this iterative process.



## Example

| variable_id           | var_type | force_in | force_out | missing_pct | nonzero_variance | include_r1 | included_r2 | reason_excluded |
| --------------------- | -------- | -------- | --------- | ----------- | ---------------- | ---------- | ----------- | --------------- |
| SV_AGE_FATHER_CAT     | CAT      | TRUE     | FALSE     | 0           | TRUE             | TRUE       | TRUE        | NA              |
| SV_CALENDAR_TIME_INT  | NUM      | TRUE     | FALSE     | 0           | TRUE             | TRUE       | TRUE        | NA              |
| SV_PSYCHIATRIC_FATHER | TF       | TRUE     | FALSE     | 0           | TRUE             | TRUE       | TRUE        | NA              |
| SV_OBESITY            | TF       | TRUE     | FALSE     | 0           | TRUE             | TRUE       | TRUE        | NA              |
| SV_MILDLIVERDYS       | TF       | FALSE    | TRUE      | 0           | FALSE            | FALSE      | FALSE       | force_out       |
