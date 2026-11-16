## Metadata

| Table name                | D4_StudyCohort_IPSMW\_`<Main/Supplementary>`                                                                               |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Description               | Person-level principal stratum scores and inverse probability of stratum membership weights (IPSMW).                       |
| Source                    | D4_StudyCohortCovariates; D4StudyCohortChild, transformations/T4_statistical_analysis/metadata/pstratummodel_variables.csv |
| Step                      | transformations/T4_statistical_analysis/source_code/compute_ipsmw.R                                                        |
| Content                   | Principal stratum score for controls and IPSMW for sensitivity analysis of estimand 1                                      |
| Population                | Males exposed and Levetiracetam, assigned to trials                                                                        |
| Unit of Observation (UoO) | One row per person_id, T0 and trial (each trial has one T0, one person can be part of multiple trials, one row per male)   |

## Codebook

| variable name             | Description                                                                                       | variable(s) needed                        | retrieved | computed | format                                  | rule_of_calculation                                                                                                                                    | vocabulary       |
| ------------------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------- | --------- | -------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------- |
| person_id                 | Person identifier                                                                                 | D4_StudyCohort::person_id                 | x         |          | Character                               |                                                                                                                                                        |                  |
| T0                        | Start of follow-up                                                                                | D4_StudyCohort::T0                        | x         |          | Date                                    |                                                                                                                                                        |                  |
| group                     | Group indicator                                                                                   | D4_StudyCohort::group                     | x         |          | Character                               |                                                                                                                                                        | EXPOSED, CONTROL |
| conception_within_3_years | Conception within 3 years indicator                                                               | D4_StudyCohort::conception_within_3_years | x         |          | Logical                                 |                                                                                                                                                        | TRUE, FALSE      |
| psm_score                 | Predicted probability of belonging to the conceiver exposed stratum (predicted for controls only) | IPSMW model                               |           | x        | Numeric                                 | predicted probabilities for controls that father a livebirth; set to NA for exposed                                                                    |                  |
| ipsmw_raw                 | Inverse probability of stratum membership weight                                                  | psm_score, group                          |           | x        | Numeric                                 | case_when(conception_within_3years & exposed == 1, conception_within_3years & control == psm_score/1-psm_score, conception_within_3_years == FALSE, 0) |                  |
| psm_score_all             | Principal stratum model                                                                           | psm_score                                 | -         | numeric  | Retain combined principal-stratum score | Combined principal-stratum score for sensitivity analysis                                                                                              |                  |

## Processing Steps

1. Load the child-cohort covariates and the configured principal-stratum variable metadata, then fit the logistic model among exposed units using conception within three years as the outcome.
2. Predict principal-stratum scores for the eligible control units and retain the combined score for both exposed and control records.
3. Convert the predicted scores into `ipsmw_raw`, after assigning zero to controls without the conception outcome and one to exposed units with conception, using an ad hoc function stored in 'fn_compute_ipsmw.R'
4. Save the person-level scores and weights to `D4_StudyCohort_IPSMW.parquet`; the coefficient and model-building diagnostics are written to the corresponding D5 CSV outputs.

## Example

| person_id      | T0         | group   | conception_within_3_years | psm_score_all | psm_score | ipsmw_raw |
| -------------- | ---------- | ------- | ------------------------- | ------------- | --------- | --------- |
| #ID-000000002# | 2011-10-14 | EXPOSED | TRUE                      | 0.688         | 0.688     | 1         |
| #ID-000000002# | 2011-11-01 | EXPOSED | TRUE                      | 0.688         | 0.688     | 1         |
| #ID-000000002# | 2011-12-01 | EXPOSED | TRUE                      | 0.678         | 0.678     | 1         |
| #ID-000000002# | 2012-01-01 | EXPOSED | TRUE                      | 0.667         | 0.667     | 1         |
| #ID-000000002# | 2012-02-01 | EXPOSED | TRUE                      | 0.643         | 0.643     | 1         |
