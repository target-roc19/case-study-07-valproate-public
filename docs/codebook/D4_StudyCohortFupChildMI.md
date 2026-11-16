## Metadata


| Table name                | D4_StudyCohortFup<Main, Supplement>_MI                                                                                                                                                                                                                |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Multiple-imputation follow-up dataset for Estimand 1 and Estimand 2. For rows with non-administrative censoring,`event_estimand1` and `event_estimand2` are imputed using baseline covariates; follow-up is extended to `general_end_fup_estiman1/2`. |
| Source                    | D4_StudyCohortFupChild; D4_StudyCohortCovariates; config_values                                                                                                                                                                                       |
| Step                      | transformations/T3_study_design/source_code/impute_outcomes.R                                                                                                                                                                                         |
| Content                   | Long-format output: each person_id/T0 row is repeated once per imputation (`imputation_id` from 1 to m). Contains imputed values for both Estimand 1 and Estimand 2.                                                                                  |
| Population                | Selected study cohort (Main mode)                                                                                                                                                                                                                     |
| Unit of Observation (UoO) | person_id, T0, imputation_id                                                                                                                                                                                                                          |

## Step Summary

1. Load D4 follow-up data and baseline covariates for Main mode.
2. Join tables by person_id, T0
3. For rows with `outcome_missing_estimand1 == TRUE`, set `event_estimand1` to missing.
4. For rows with `outcome_missing_estimand2 == TRUE`, set `event_estimand2` to missing.
5. Run `mice` multiple imputation (`method = "logreg"`) for both `event_estimand1` and `event_estimand2` independently using:
   - `group`
   - `SV_AGE_FATHER_CAT`
   - `SV_CALENDAR_TIME_INT`
   - `SV_PSYCHIATRIC_FATHER`
   - `SV_OBESITY`
   - `SV_MILDLIVERDYS`
   - `SV_ASM_PREVIOUS`
   - `SV_TERATOGENIC_FATHER`
   - `SV_ALCOHOL_ABUSE`
   - `SV_SMOKING_FATHER`
6. Build long output with one copy per imputation (`imputation_id = 1..m`).
7. For imputed non-admin rows (both estimands):
   - Set `fup_d_estimand1 = general_end_fup_estimand1` and `fup_d_estimand2 = general_end_fup_estimand2`
   - Recompute follow-up lengths:
     - `fup_length_days_estimand1` and `fup_length_days_estimand2`
     - `fup_length_months_estimand1` and `fup_length_months_estimand2`

## Codebook
| variable_in_output          | variable(s) needed                                    | retrieved | computed | format    | rule_of_calculation                                                                     | description                                        | vocabulary       |
| --------------------------- | ----------------------------------------------------- | --------- | -------- | --------- | --------------------------------------------------------------------------------------- | -------------------------------------------------- | ---------------- |
| person_id                   | D4_StudyCohortFupChild/person_id                      | x         |          | character |                                                                                         | Person identifier                                  |                  |
| T0                          | D4_StudyCohortFupChild/T0                             | x         |          | date      |                                                                                         | Time-zero                                          |                  |
| group                       | D4_StudyCohortFupChild/group                          | x         |          | character |                                                                                         | EXPOSED or CONTROL                                 | EXPOSED, CONTROL |
| imputation_id               | config_project/impute_outcomes/model/n_imputations    |           | x        | integer   | 1..`n_imputations`                                                                      | Imputation replicate index (long format)           | 1..m             |
| outcome_missing_estimand1   | outcome_missing_estimand1                             | x         |          | logical   |                                                                                         | Indicator of missing outcome for Estimand 1        |                  |
| event_estimand1_observed    | event_estimand1 (input FUP)                           | x         |          | integer   |                                                                                         | Observed Estimand 1 event before MI (audit column) | 0,1              |
| event_estimand1             | event_estimand1_observed + MI model                   |           | x        | integer   | Keep observed values for non-missing; impute for outcome_missing_estimand1 == TRUE      | Estimand 1 event indicator after MI                | 0,1              |
| general_end_fup_estimand1   | D4_StudyCohortFupChild/general_end_fup_estimand1      | x         |          | date      |                                                                                         | General follow-up end date for Estimand 1          |                  |
| fup_d_estimand1             | fup_d_estimand1, general_end_fup_estimand1            |           | x        | date      | If outcome_missing_estimand1 == TRUE, set to general_end_fup_estimand1; otherwise input | Estimand 1 follow-up end date after MI handling    |                  |
| fup_length_days_estimand1   | fup_d_estimand1, T0                                   |           | x        | integer   | `fup_d_estimand1 - T0 + 1`                                                              | Follow-up duration (days) for Estimand 1           |                  |
| fup_length_months_estimand1 | fup_length_days_estimand1, config_values/month_length |           | x        | numeric   | `fup_length_days_estimand1 / month_length`                                              | Follow-up duration (person-months) for Estimand 1  |                  |
| outcome_missing_estimand2   | outcome_missing_estimand2                             | x         |          | logical   |                                                                                         | Indicator of missing outcome for Estimand 2        |                  |
| event_estimand2_observed    | event_estimand2 (input FUP)                           | x         |          | integer   |                                                                                         | Observed Estimand 2 event before MI (audit column) | 0,1              |
| event_estimand2             | event_estimand2_observed + MI model                   |           | x        | integer   | Keep observed values for non-missing; impute for outcome_missing_estimand2 == TRUE      | Estimand 2 event indicator after MI                | 0,1              |
| general_end_fup_estimand2   | D4_StudyCohortFupChild/general_end_fup_estimand2      | x         |          | date      |                                                                                         | General follow-up end date for Estimand 2          |                  |
| fup_d_estimand2             | fup_d_estimand2, general_end_fup_estimand2            |           | x        | date      | If outcome_missing_estimand2 == TRUE, set to general_end_fup_estimand2; otherwise input | Estimand 2 follow-up end date after MI handling    |                  |
| fup_length_days_estimand2   | fup_d_estimand2, T0                                   |           | x        | integer   | `fup_d_estimand2 - T0 + 1`                                                              | Follow-up duration (days) for Estimand 2           |                  |
| fup_length_months_estimand2 | fup_length_days_estimand2, config_values/month_length |           | x        | numeric   | `fup_length_days_estimand2 / month_length`                                              | Follow-up duration (person-months) for Estimand 2  |                  |
| trial_id | D4_StudyCohortChild/trial_id | x | - | integer |  | Sequential trial identifier | - |
| child_id | D4_StudyCohortChild/child_id | x | - | character |  | Child identifier | - |
| father_id | D4_StudyCohortChild/father_id | x | - | character |  | Father identifier | - |
| date_of_birth | D4_StudyCohortChild/date_of_birth | x | - | date |  | Child date of birth | YYYY-MM-DD |
| pyr_estimand1 | fup_length_days_estimand1 | - | x | numeric | Divide follow-up days by 365.25 | Estimand 1 person-years | >= 0 |
| pyr_estimand2 | fup_length_days_estimand2 | - | x | numeric | Divide follow-up days by 365.25 | Estimand 2 person-years | >= 0 |
| child_age_at_endfup_est1 | date_of_birth, fup_d_estimand1 | - | x | numeric | Calculate age at Estimand 1 follow-up end | Child age at end of Estimand 1 follow-up | years |
| child_age_at_endfup_est2 | date_of_birth, fup_d_estimand2 | - | x | numeric | Calculate age at Estimand 2 follow-up end | Child age at end of Estimand 2 follow-up | years |
| SV_AGE_FATHER_CAT | baseline covariates | x | - | categorical |  | Father age category | - |
| SV_PSYCHIATRIC_FATHER | baseline covariates | x | - | categorical |  | Father psychiatric history | TRUE, FALSE |
| SV_OBESITY | baseline covariates | x | - | categorical |  | Father obesity indicator | TRUE, FALSE |
| SV_TERATOGENIC_FATHER | baseline covariates | x | - | categorical |  | Father teratogenic exposure | TRUE, FALSE |
| SV_ALCOHOL_ABUSE | baseline covariates | x | - | categorical |  | Father alcohol-abuse indicator | TRUE, FALSE |
| SV_SMOKING_FATHER | baseline covariates | x | - | categorical |  | Father smoking indicator | TRUE, FALSE |
| SV_CALENDAR_TIME_INT | baseline covariates | x | - | numeric |  | Calendar time index | - |
## Notes

1. This table is intended for multi-estimand MI-based analyses (Estimand 1 and Estimand 2).
2. Output is long format by design to preserve per-imputation records.
3. `event_estimand1_observed` and `event_estimand2_observed` are kept to enable diagnostics and sensitivity checks against imputed values.
4. Both estimands are imputed independently using the same predictor variables and the same random seed to ensure reproducibility.

## Example (Long Format)

| person_id      | T0         | trial_id | child_id       | father_id      | date_of_birth | event_estimand1 | outcome_missing_estimand1 | general_end_fup_estimand1 | pyr_estimand1    | event_estimand2 | outcome_missing_estimand2 | general_end_fup_estimand2 | pyr_estimand2    | child_age_at_endfup_est1 | child_age_at_endfup_est2 | group   | SV_AGE_FATHER_CAT | SV_PSYCHIATRIC_FATHER | SV_OBESITY | SV_TERATOGENIC_FATHER | SV_ALCOHOL_ABUSE | SV_SMOKING_FATHER | SV_CALENDAR_TIME_INT | event_estimand1_observed | event_estimand2_observed | imputation_id | fup_d_estimand1 | fup_length_days_estimand1 | fup_length_months_estimand1 | fup_d_estimand2 | fup_length_days_estimand2 | fup_length_months_estimand2 |
| -------------- | ---------- | -------- | -------------- | -------------- | ------------- | --------------- | ------------------------- | ------------------------- | ---------------- | --------------- | ------------------------- | ------------------------- | ---------------- | ------------------------ | ------------------------ | ------- | ----------------- | --------------------- | ---------- | --------------------- | ---------------- | ----------------- | -------------------- | ------------------------ | ------------------------ | ------------- | --------------- | ------------------------- | --------------------------- | --------------- | ------------------------- | --------------------------- |
| #ID-000003565# | 2011-10-14 | 22       | #ID-000003565# | #ID-000000002# | 2012-09-11    | 0               | FALSE                     | 2020-09-11                | 8.003 | 0               | FALSE                     | 2020-09-11                | 8.003 | 8                        | 8                        | EXPOSED | 38_47             | FALSE                 | FALSE      | TRUE                  | FALSE            | FALSE             | 21                   | 0                        | 0                        | 1             | 2020-09-11      | 3256                      | 106.965            | 2020-09-11      | 3256                      | 106.965            |
| #ID-000003565# | 2011-11-01 | 23       | #ID-000003565# | #ID-000000002# | 2012-09-11    | 0               | FALSE                     | 2020-09-11                | 8.003 | 0               | FALSE                     | 2020-09-11                | 8.003 | 8                        | 8                        | EXPOSED | 38_47             | FALSE                 | FALSE      | TRUE                  | FALSE            | FALSE             | 21                   | 0                        | 0                        | 1             | 2020-09-11      | 3238                      | 106.373            | 2020-09-11      | 3238                      | 106.373            |
| #ID-000003565# | 2011-12-01 | 24       | #ID-000003565# | #ID-000000002# | 2012-09-11    | 0               | FALSE                     | 2020-09-11                | 8.003 | 0               | FALSE                     | 2020-09-11                | 8.003 | 8                        | 8                        | EXPOSED | 38_47             | FALSE                 | FALSE      | TRUE                  | FALSE            | FALSE             | 22                   | 0                        | 0                        | 1             | 2020-09-11      | 3208                      | 105.388              | 2020-09-11      | 3208                      | 105.388              |
| #ID-000003665# | 2012-01-01 | 25       | #ID-000003665# | #ID-000000002# | 2015-03-23    | NA              | TRUE                      | 2013-11-24                | NA               | NA              | TRUE                      | 2012-05-11                | NA               | -1.325        | -2.864        | EXPOSED | 38_47             | FALSE                 | FALSE      | TRUE                  | FALSE            | FALSE             | 23                   | NA                       | NA                       | 1             | 2013-11-24      | 694                       | 22.799            | 2012-05-11      | 132                       | 4.336            |
| #ID-000003665# | 2012-02-01 | 26       | #ID-000003665# | #ID-000000002# | 2015-03-23    | NA              | TRUE                      | 2013-11-24                | NA               | NA              | TRUE                      | 2012-05-11                | NA               | -1.325        | -2.864        | EXPOSED | 38_47             | FALSE                 | FALSE      | TRUE                  | FALSE            | FALSE             | 25                   | NA                       | NA                       | 1             | 2013-11-24      | 663                       | 21.781            | 2012-05-11      | 101                       | 3.318            |

## Processing Steps

impute_outcomes.R reads child follow-up and baseline covariates, fits the configured multiple-imputation models for missing estimand outcomes, creates one long-format copy per imputation, and recalculates follow-up dates and durations for imputed records.
