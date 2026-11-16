## Metadata


| Table name                | D3_ANCHORED_VARIABLES_child                                                                        |
| ------------------------- | -------------------------------------------------------------------------------------------------- |
| Description               | Child anchored study-variable observations                                                         |
| Source                    | D3_CONCEPTS.parquet, D4_StudyCohortChild.parquet, anchoring_window_metadata.csv                    |
| Step                      | Anchoring study variables: transformations/T3_study_design/source_code/create_anchored_variables.R |
| Content                   | Long-format values observed in the configured time windows around each child anchor                |
| Population                | Children in the anchored study cohort                                                              |
| Unit of Observation (UoO) | anchor row, variable, and observation date                                                         |

## Codebook


| variable_in_output | variable(s) needed              | retrieved | computed | format    | rule_of_calculation                       | description                                 | vocabulary |
| ------------------ | ------------------------------- | --------- | -------- | --------- | ----------------------------------------- | ------------------------------------------- | ---------- |
| anchor_row_id      | D4 child anchor row             | x         | -        | integer   |                                           | Anchor-row identifier                       | -          |
| person_id          | D4 child cohort/person_id       | x         | -        | character |                                           | Child person identifier                     | -          |
| T0                 | D4 child cohort/T0              | x         | -        | date      |                                           | Start of follow-up and covariate assessment | YYYY-MM-DD |
| window_name        | configuration window definition | -         | x        | character | Name of the configured observation window | Observation window containing the value     | -          |
| value              | source concept result           | x         | -        | character |                                           | Observed study-variable value               | -          |
| date               | source observation date         | x         | -        | date      |                                           | Date on which the value was observed        | YYYY-MM-DD |
| n                  | source record count             | x         | -        | integer   |                                           | Number of contributing records              | >= 0       |
| variable_id        | study-variable definition       | x         | -        | character |                                           | Study-variable identifier                   | SV_*       |

## Processing Steps

This dataset supplies child-level covariates at the study-defined anchor points. The transformation reads `D4_StudyCohortChild`, the anchoring-window metadata, and partitioned `D3_CONCEPTS` records, then selects concept observations within each configured child window. It retains the observed value, date, and number of contributing records and writes one long-format row per anchor, variable, and selected observation to `D3_ANCHORED_VARIABLES_child_parquet`.

## Example


| anchor_row_id | person_id      | T0         | window_name | value | date       | n   | variable_id |
| ------------- | -------------- | ---------- | ----------- | ----- | ---------- | --- | ----------- |
| 1026          | #ID-000001082# | 2013-12-01 | risk        | true  | 2014-10-13 | 1   | SV_MAJORCA  |
