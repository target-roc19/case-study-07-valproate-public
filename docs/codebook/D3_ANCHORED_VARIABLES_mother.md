## Metadata


| Table name                | D3_ANCHORED_VARIABLES_mother                                                                       |
| ------------------------- | -------------------------------------------------------------------------------------------------- |
| Description               | Mother anchored study-variable observations                                                        |
| Source                    | D3_CONCEPTS.parquet, D4_StudyCohortChild.parquet, anchoring_window_metadata.csv                    |
| Step                      | Anchoring study variables: transformations/T3_study_design/source_code/create_anchored_variables.R |
| Content                   | Long-format values observed in the configured time windows around each mother anchor               |
| Population                | Mothers in the anchored study cohort                                                               |
| Unit of Observation (UoO) | anchor row, variable, and observation date                                                         |

## Codebook


| variable_in_output | variable(s) needed              | retrieved | computed | format    | rule_of_calculation                       | description                                 | vocabulary |
| ------------------ | ------------------------------- | --------- | -------- | --------- | ----------------------------------------- | ------------------------------------------- | ---------- |
| anchor_row_id      | D4 mother anchor row            | x         | -        | integer   |                                           | Anchor-row identifier                       | -          |
| person_id          | D4 mother cohort/person_id      | x         | -        | character |                                           | Mother person identifier                    | -          |
| T0                 | D4 mother cohort/T0             | x         | -        | date      |                                           | Start of follow-up and covariate assessment | YYYY-MM-DD |
| window_name        | configuration window definition | -         | x        | character | Name of the configured observation window | Observation window containing the value     | -          |
| value              | source concept result           | x         | -        | character |                                           | Observed study-variable value               | -          |
| date               | source observation date         | x         | -        | date      |                                           | Date on which the value was observed        | YYYY-MM-DD |
| n                  | source record count             | x         | -        | integer   |                                           | Number of contributing records              | >= 0       |
| variable_id        | study-variable definition       | x         | -        | character |                                           | Study-variable identifier                   | SV_*       |

## Processing Steps

This dataset supplies maternal covariates linked to the child-trial records. The transformation reads the child cohort linkage, maternal anchoring-window metadata, and partitioned `D3_CONCEPTS` records, then evaluates the configured windows around the relevant birth and conception anchors. It retains the matching concept value, date, and contributing-record count and writes the long-format result to `D3_ANCHORED_VARIABLES_mother_parquet`.

## Example


| anchor_row_id | person_id      | T0         | window_name | value | date       | n   | variable_id           |
| ------------- | -------------- | ---------- | ----------- | ----- | ---------- | --- | --------------------- |
| 426           | #ID-000002931# | 2013-10-01 | lookback    | TRUE  | 2013-01-15 | 2   | SV_NEUROPSYCHAECONCOM |
| 1756          | #ID-000001507# | 2014-05-01 | lookback    | TRUE  | 2014-04-19 | 5   | SV_NEUROPSYCHAECONCOM |
| 1602          | #ID-000001777# | 2013-12-01 | lookback    | TRUE  | 2013-06-04 | 2   | SV_NEUROPSYCHAECONCOM |
| 802           | #ID-000003241# | 2010-03-30 | lookback    | true  | 2009-12-29 | 1   | SV_OBESITY_MOTHER     |
| 538           | #ID-000003339# | 2010-03-30 | lookback    | true  | 2009-12-29 | 1   | SV_OBESITY_MOTHER     |
