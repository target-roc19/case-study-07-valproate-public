## Metadata

| Table name                | D5_PS_Coef_<cohort, model>                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Coefficient estimates and diagnostics from the final logistic propensity-score model. The `<cohort, model>` suffix identifies the population and model represented by the output, including male treatment IPTW, combined mother-father-child treatment IPTW, and principal-stratum membership IPSMW models.                                                                                                                                                                                         |
| Source                    | Treatment IPTW, male cohort: `data/D4_analytic_datasets/D4_StudyCohort_Covariates.parquet`; combined treatment IPTW, mother-father-child cohort: `data/D4_analytic_datasets/D4_StudyCohort_Covariates_Combined_Mother_Father_ChildCohort.parquet`; IPSMW: `data/D4_analytic_datasets/D4_StudyCohort_Covariates.parquet`. Model metadata: `transformations/T4_statistical_analysis/metadata/psmodel_variables.csv`, `psmodel_variables_mother.csv`, and `pstratummodel_variables.csv`, as applicable. |
| Step                      | Treatment IPTW: `transformations/T4_statistical_analysis/source_code/compute_d4_StudyCohort_IPTW.R`; combined treatment IPTW uses the same step; IPSMW: `transformations/T4_statistical_analysis/source_code/compute_ipsmw.R`. Shared/helper implementation: `transformations/T4_statistical_analysis/source_code/functions/compute_d4_StudyCohort_IPTW_function.R` for treatment IPTW and `transformations/T4_statistical_analysis/source_code/functions/fn_compute_ipsmw.R` for IPSMW.             |
| Content                   | One row per coefficient in the final model, with the coefficient estimate, standard error, z statistic, p-value, and exponentiated estimate. The exact terms and values depend on the selected cohort and model.                                                                                                                                                                                                                                                                                     |
| Population                | Depends on the suffix: male treatment cohort; combined mother father child treatment cohort; or males units assessed for conception within three years for the IPSMW model.                                                                                                                                                                                                                                                                                                                          |
| Unit of Observation (UoO) | Model term, including the intercept and expanded categorical levels.                                                                                                                                                                                                                                                                                                                                                                                                                                 |

## Codebook

| Variable name | Description                                              | Format    | Vocabulary | Variables from source used for the variable | Principles for coding                                                    |
| ------------- | -------------------------------------------------------- | --------- | ---------- | ------------------------------------------- | ------------------------------------------------------------------------ |
| coefficient   | Final model term name                                    | Character |            | Final model coefficient row names           | Model term name, including the intercept and expanded categorical levels |
| estimate      | Point estimate of the coefficient                        | Numeric   |            | `summary(model_final)$coefficients[,1]`     |                                                                          |
| std_error     | Standard error                                           | Numeric   |            | `summary(model_final)$coefficients[,2]`     |                                                                          |
| z_score       | z value for significance test                            | Numeric   |            | `summary(model_final)$coefficients[,3]`     |                                                                          |
| p_value       | P-value for significance test                            | Numeric   | [0, 1]     | `summary(model_final)$coefficients[,4]`     |                                                                          |
| exp_estimate  | Exponential of the estimate, representing the odds ratio | Numeric   | > 0        | `estimate`                                  | `exp(estimate)`                                                          |

## Processing Steps

This objects store the model cofficients resulting from fitting a propensity score model (IPTW for males and IPTW for children using mother and paternal covariates in sensitivity analysis), and a principal stratum model (for sensitivity analysis)

1. Read the configured cohort covariates and model-variable metadata. For treatment IPTW, this may be the male cohort or the combined mother-father-child cohort; for IPSMW, use the principal-stratum covariates and `pstratummodel_variables.csv`.
2. Fit the initial logistic model, apply the configured model-building described in the ModelBuilding codebooks and model-fitting functions, and refit after excluding problematic variables when required.
3. Extract `summary(model_final)$coefficients`, retaining the estimate, standard error, z statistic, and p-value for every final model term.
4. Calculate `exp_estimate = exp(estimate)` and save one row per term, including the intercept and expanded categorical levels.

## Cohort and Model Differences

The codebook structure and output columns are shared across all three variants. The following differences are specific to each suffix:

| Variant                                           | Model outcome                                                                                                   | Cohort and inputs                                                                                                                                                                                                                              | Producing implementation                                                     |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `D5_PS_Coef_<male, IPTW>`                         | Treatment group (`EXPOSED` versus `CONTROL`)                                                                    | Male/father cohort; `D4_StudyCohort_Covariates.parquet`; `psmodel_variables.csv`                                                                                                                                                               | `compute_d4_StudyCohort_IPTW.R` and `compute_d4_StudyCohort_IPTW_function.R` |
| `D5_PS_Coef_<combined mother-father-child, IPTW>` | Treatment group (`EXPOSED` versus `CONTROL`)                                                                    | Child-cohort units with combined mother and father covariates; `D4_StudyCohort_Covariates_Combined_Mother_Father_ChildCohort.parquet`; combined treatment-model metadata, including `psmodel_variables.csv` and `psmodel_variables_mother.csv` | `compute_d4_StudyCohort_IPTW.R` and `compute_d4_StudyCohort_IPTW_function.R` |
| `D5_PS_Coef_<principal stratum, IPSMW>`           | Conception within three years among exposed units, used to derive principal-stratum membership scores and IPSMW | Cohort units assessed for conception within three years; `D4_StudyCohort_Covariates.parquet`; `pstratummodel_variables.csv`                                                                                                                    | `compute_ipsmw.R` and `fn_compute_ipsmw.R`                                   |

## Example

| coefficient               | estimate | std_error | z_score | p_value | exp_estimate |
| ------------------------- | -------- | --------- | ------- | ------- | ------------ |
| (Intercept)               | -0.029   | 0.140     | -0.203  | 0.839   | 0.972        |
| SV_AGE_FATHER_CAT18_27    | -0.191   | 0.107     | -1.791  | 0.073   | 0.826        |
| SV_AGE_FATHER_CAT38_47    | -0.041   | 0.101     | -0.410  | 0.682   | 0.959        |
| SV_AGE_FATHER_CAT48_55    | 0.043    | 0.188     | 0.229   | 0.819   | 1.044        |
| SV_PSYCHIATRIC_FATHERTRUE | -0.128   | 0.287     | -0.445  | 0.656   | 0.880        |

The example is illustrative of the shared schema; coefficient terms and estimates vary by cohort and model.
