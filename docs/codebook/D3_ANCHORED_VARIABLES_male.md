## Metadata


| Table name                | D3_ANCHORED_VARIABLES_male                                                                         |
| ------------------------- | -------------------------------------------------------------------------------------------------- |
| Description               | Male anchored study-variable observations                                                          |
| Source                    | D3_CONCEPTS.parquet, D4_StudyCohort.parquet, anchoring_window_metadata.csv                         |
| Step                      | Anchoring study variables: transformations/T3_study_design/source_code/create_anchored_variables.R |
| Content                   | Long-format values observed in the configured time windows around each male anchor                 |
| Population                | Males in the anchored study cohort                                                                 |
| Unit of Observation (UoO) | anchor row, variable, and observation date                                                         |

## Codebook


| variable_in_output | variable(s) needed              | retrieved | computed | format    | rule_of_calculation                       | description                                 | vocabulary |
| ------------------ | ------------------------------- | --------- | -------- | --------- | ----------------------------------------- | ------------------------------------------- | ---------- |
| anchor_row_id      | D4 male anchor row              | x         | -        | integer   |                                           | Anchor-row identifier                       | -          |
| person_id          | D4 male cohort/person_id        | x         | -        | character |                                           | Male person identifier                      | -          |
| T0                 | D4 male cohort/T0               | x         | -        | date      |                                           | Start of follow-up and covariate assessment | YYYY-MM-DD |
| window_name        | configuration window definition | -         | x        | character | Name of the configured observation window | Observation window containing the value     | -          |
| value              | source concept result           | x         | -        | character |                                           | Observed study-variable value               | -          |
| date               | source observation date         | x         | -        | date      |                                           | Date on which the value was observed        | YYYY-MM-DD |
| n                  | source record count             | x         | -        | integer   |                                           | Number of contributing records              | >= 0       |
| variable_id        | study-variable definition       | x         | -        | character |                                           | Study-variable identifier                   | SV_*       |

## Processing Steps

This dataset supplies male baseline and risk-window covariates for each sequential-trial anchor. The transformation reads `D4_StudyCohort`, the anchoring-window metadata, and partitioned `D3_CONCEPTS` records, then applies the configured lookback and risk windows around each trial time zero. Matching concept values, dates, and contributing-record counts are written in long format to `D3_ANCHORED_VARIABLES_male_parquet`.

## Example


| anchor_row_id | person_id      | T0         | window_name | value | date       | n   | variable_id      |
| ------------- | -------------- | ---------- | ----------- | ----- | ---------- | --- | ---------------- |
| 8547          | #ID-000000653# | 2011-05-01 | lookback    | TRUE  | 2011-04-24 | 1   | SV_ALCOHOL_ABUSE |
| 8007          | #ID-000000604# | 2010-11-01 | lookback    | TRUE  | 2010-01-02 | 1   | SV_ALCOHOL_ABUSE |
| 8037          | #ID-000000604# | 2011-01-01 | lookback    | TRUE  | 2010-01-02 | 1   | SV_ALCOHOL_ABUSE |
| 8022          | #ID-000000604# | 2010-12-01 | lookback    | TRUE  | 2010-01-02 | 1   | SV_ALCOHOL_ABUSE |
| 7992          | #ID-000000604# | 2010-10-06 | lookback    | TRUE  | 2010-01-02 | 1   | SV_ALCOHOL_ABUSE |
