## Metadata

| Table name                | D4_StudyCohort_IPTW                                                                                  |
| ------------------------- | ---------------------------------------------------------------------------------------------------- |
| Description               | Dataset consisting of IPT weights for the sequential trials male cohort                              |
| Source                    | `D4_StudyCohort_Covariates`; `ransformations/T4_statistical_analysis/metadata/psmodel_variables.csv` |
| Step                      | `transformations/T4_statistical_analysis/source_code/compute_d4_StudyCohort_IPTW.R`                  |
| Content                   | Propensity scores and IP weights for each male-trial unit                                            |
| Population                | Selected study cohort (exposed and control units) allocated to trials.                               |
| Unit of Observation (UoO) | One row per person_id and T0 (multiple T0 per person possible); i.e., male-trial units               |

## Codebook

| variable name          | Description                                                                                                                       | variable(s) needed                 | retrieved | computed | format    | rule_of_calculation                                                                                                                | vocabulary       |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- | --------- | -------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| person_id              | D4_StudyCohort_Covariates/person_id                                                                                               | D4_StudyCohortCovariates/person_id | x         |          | Character |                                                                                                                                    |                  |
| T0                     | D4_StudyCohort_Covariates/T0                                                                                                      | D4_StudyCohortCovariates/T0        | x         |          | Date      |                                                                                                                                    |                  |
| group                  | Group identifier: EXPOSED and CONTROL                                                                                             | D4_StudyCohortCovariates/group     | x         |          | Character |                                                                                                                                    | EXPOSED, CONTROL |
| group_binary           | Binary version of group (exposed = 1, control = 0)                                                                                | group                              |           | x        | Integer   | IF group == "EXPOSED" THEN 1 ELSE 0                                                                                                | 0, 1             |
| p_score                | Predicted probability of exposure from the PS model (fitted.values)                                                               |                                    |           | x        | Numeric   | Predicted probability from logistic regression: P(group_binary = 1 conditional on covariates)                                      |                  |
| include_after_trimming | indicator variable; if trimming of the propensity scores applied, should this individual be selected into the final cohort or not | p_score, ps_trim_bounds            |           | x        | Logical   | IF ps_trim_bounds given: TRUE if p_score \>= lower AND p_score \<= upper, else FALSE.<br />If no trimming: TRUE for all.           |                  |
| raw_iptw               | Inverse probability of treatment weights (raw/untruncated). Computed according to protocol (ATE weights)                          | p_score, group_binary              |           | x        | Numeric   | IF group_binary == 1, 1 / p_score else 1 / (1 - p_score)                                                                           |                  |
| stabilized_iptw        | Stabilized version of raw_iptw (multiply by marginal probability of being assigned to the group you are assigned to)              | p_score, group_binary              |           | x        | Numeric   |                                                                                                                                    |                  |
| stabilized_trunc_iptw  | Truncated stabilized IPTW (truncated at 1st and 99th percentile)                                                                  | stabilized_iptw                    |           | x        | Numeric   | Per group: values below 1st percentile set to P1; values above 99th percentile set to P99. Percentiles computed within each group. |                  |

## Processing Steps

The transformation estimates treatment weights for each person-trial unit in the selected cohort. It first obtains the propensity score model-based probability of exposure, then applies the configured trimming rule (no trimming in this case) before calculating the raw and stabilized weights. Finally, it truncates the stabilized values within treatment group at the configured percentiles (0.01 and 0.99) and writes the propensity score and different weight version columns (stabilized, stabilized truncated, raw)

1. Extract predicted probabilities of exposed group membership from the estimated propensity score model, which is a logistic regression model conditional on all covariates and using splines for calendar time, as described in function T4_statistical_analysis/source_cocde/functions/fit_ps_model.R
2. The function has functionality to perform trimming, which was not applied in this case study. If trimming of propensity score were to be rquired, it is possible to input lower and upper bound of propensity score values (provided by a config_project.ymal parameter. If supplied, it selects only units who have `p_score` within the trimming bounds and records in `include_after_trimming` who meets these criteria.
3. Compute raw IPT weights from `p_score` for individuals with `include_after_trimming == TRUE`(all in this case study). IPTW-ATE weights given by `A*(1/p_score) + (1-A)*(1/1-p_score)`.
4. Compute stabilized IPT weights using marginal probability of actual treatment assignment, by by `A*(sum(A == 1)/nrow(StudyCohort)) * iptw_raw + (1-A)*(sum(A == 0)/nrow(StudyCohort))*iptw_raw`
5. Calculate truncated stabilized IPT weights; compute 1st and 99th percentile; all values lower than 1st percentile get set to 1st percentile, all values higher than 99th percentile get set to 99th percentile.

## Example

| person_id      | T0         | group   | group_binary | p_score | include_after_trimming | raw_iptw | stabilized_iptw | stabilized_trunc_iptw |
| -------------- | ---------- | ------- | ------------ | ------- | ---------------------- | -------- | --------------- | --------------------- |
| #ID-000000002# | 2011-10-14 | EXPOSED | 1            | 0.535   | TRUE                   | 1.871    | 0.935           | 0.935                 |
| #ID-000000002# | 2011-11-01 | EXPOSED | 1            | 0.535   | TRUE                   | 1.871    | 0.935           | 0.935                 |
| #ID-000000002# | 2011-12-01 | EXPOSED | 1            | 0.540   | TRUE                   | 1.852    | 0.926           | 0.926                 |
| #ID-000000002# | 2012-01-01 | EXPOSED | 1            | 0.545   | TRUE                   | 1.836    | 0.918           | 0.918                 |
| #ID-000000002# | 2012-02-01 | EXPOSED | 1            | 0.553   | TRUE                   | 1.809    | 0.905           | 0.905                 |
