## Metadata

| Table name                | D5_PS_ModelBuilding_IPSMW                                                                                                                             |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Data-quality and model-fitting decisions for candidate variables in the principal-stratum membership model used for IPSMW.                            |
| Source                    | data/D4_analytic_datasets/D4_StudyCohortCovariates.parquet;<br /> transformations/T4_statistical_analysis/metadata/pstratummodel_variables.csv        |
| Step                      | transformations/T4_statistical_analysis/source_code/compute_ipsmw.R; transformations/T4_statistical_analysis/source_code/functions/fn_compute_ipsmw.R |
| Content                   | Summarizes for each variable type data quality criteria such as missing pct, nonzero variance and whether the variable was included                   |
| Population                | Candidate variables for the IPSMW principal-stratum model.                                                                                            |
| Unit of Observation (UoO) | NA (one row per variable)                                                                                                                             |

## Codebook

| Variable name    | Description                                                         | Source used for the variable                                                 | format    | rule_of_calculation                                     | vocabulary |
| ---------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------- | --------- | ------------------------------------------------------- | ---------- |
| variable_id      | Candidate variable identifier                                       | transformations/T4_statistical_analysis/metadata/pstratummodel_variables.csv | Character |                                                         |            |
| var_type         | Variable type                                                       | transformations/T4_statistical_analysis/metadata/pstratummodel_variables.csv | Character |                                                         |            |
| force_in         | Force variable into the model                                       | transformations/T4_statistical_analysis/metadata/pstratummodel_variables.csv | Logical   |                                                         |            |
| force_out        | Force variable out of the model                                     | transformations/T4_statistical_analysis/metadata/pstratummodel_variables.csv | Logical   |                                                         |            |
| exists_in_data   | Whether the candidate variable is available in the IPSMW input data | data/D4_analytic_datasets/D4_StudyCohortCovariates.parquet                   | Logical   |                                                         |            |
| missing_pct      | Missing percentage across candidate-data rows                       | data/D4_analytic_datasets/D4_StudyCohortCovariates.parquet                   | Numeric   |                                                         |            |
| nonzero_variance | Whether the variable has more than one non-missing value            | data/D4_analytic_datasets/D4_StudyCohortCovariates.parquet                   | Logical   |                                                         |            |
| include_r1       | Whether the variable is included in the initial model               | model fit round 1                                                            | Logical   | Passes configured data-quality criteria or is forced in |            |
| included_r2      | Whether the variable is included in the final model                 | model fit round 2                                                            | Logical   | Remains after fit checks and refitting                  |            |
| reason_excluded  | Reason for exclusion; NA when included                              | model fit diagnostics                                                        | Character |                                                         |            |

## Processing Steps

1. Load `pstratum_variables.csv` to identify candidate variables for the PS model

2. For each candidate variable, compute data quality checks: count unique non-NA values (`nonzero_variance`), compute missing percentage (`missing_pct`). Since the code was programmed without data-access, this was needed to potentially avoid issues in data source.

3. Fit initial PS model (Round 1) with all variables passing data quality checks (`include_r1 = TRUE`). Check for fit issues (large SE, non-convergence) and record in `reason_excluded`

4. If fit issues found: exclude problematic variables (`included_r2 = FALSE`), refit model (Round 2). If no issues, Round 2 equals Round 1 and all R1 variables have `included_r2 = TRUE`. Returns output of this iterative process.

## Example

| variable_id           | var_type | force_in | force_out | exists_in_data | missing_pct | nonzero_variance | include_r1 | included_r2 | reason_excluded |
| --------------------- | -------- | -------- | --------- | -------------- | ----------- | ---------------- | ---------- | ----------- | --------------- |
| SV_AGE_FATHER_CAT     | CAT      | TRUE     | FALSE     | TRUE           | 0           | TRUE             | TRUE       | TRUE        | NA              |
| SV_CALENDAR_TIME_INT  | NUM      | TRUE     | FALSE     | TRUE           | 0           | TRUE             | TRUE       | TRUE        | NA              |
| SV_PSYCHIATRIC_FATHER | TF       | TRUE     | FALSE     | TRUE           | 0           | TRUE             | TRUE       | TRUE        | NA              |
| SV_OBESITY            | TF       | TRUE     | FALSE     | TRUE           | 0           | TRUE             | TRUE       | TRUE        | NA              |
| SV_MILDLIVERDYS       | TF       | FALSE    | TRUE      | TRUE           | 0           | FALSE            | FALSE      | FALSE       | force_out       |
