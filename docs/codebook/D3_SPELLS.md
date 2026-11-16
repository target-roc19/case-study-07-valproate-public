## Metadata

| Table name                | D3_SPELLS |
| ------------------------- | ---------- |
| Description               | Person-level observation spells, merged across overlaps and gaps of up to 180 days, with boundaries adjusted to available birth and death dates. |
| Source                    | `D2_CDM/OBSERVATION_PERIODS` and `D3_PERSONS` |
| Step                      | `transformations/T2_semantic_harmonization/source_code/process_observation_periods.R` |
| Content                   | Valid continuous observation periods with person demographics and spell-date quality flags. |
| Population                | Observation spells that can be joined to `D3_PERSONS` and have non-missing start/end dates with start strictly before end. |
| Unit of Observation (UoO) | One row per person spell. A person can have multiple spells. |
| File format               | Parquet file (`D3_SPELLS.parquet`). |

## Codebook
| variable_in_output | variable(s) needed | retrieved | computed | format | rule_of_calculation | description | vocabulary |
| ------------------ | ------------------ | --------- | -------- | ------ | ------------------- | ----------- | ---------- |
| person_id | `OBSERVATION_PERIODS/person_id`, `D3_PERSONS/person_id` | x | - | character | Used to form spells from observation periods and join each spell to `D3_PERSONS`. | Person identifier | - |
| start_spell | `OBSERVATION_PERIODS/person_id`, `OBSERVATION_PERIODS/op_start_date`, `OBSERVATION_PERIODS/op_end_date`, `D3_PERSONS/birth_date` | - | x | date | For each person, merge overlapping observation periods and periods with gaps of at most 180 days; use the earliest start date in each merged spell. If earlier than `birth_date`, replace it with `birth_date`. | Spell start date | YYYY-MM-DD |
| end_spell | `OBSERVATION_PERIODS/person_id`, `OBSERVATION_PERIODS/op_start_date`, `OBSERVATION_PERIODS/op_end_date`, `D3_PERSONS/death_date` | - | x | date | For each person, merge overlapping observation periods and periods with gaps of at most 180 days; use the latest end date in each merged spell. Missing end dates are imputed to `end_study_date` under the script's conditions; if later than `death_date`, replace with `death_date`. | Spell end date | YYYY-MM-DD |
| year_of_birth | `D3_PERSONS/year_of_birth` | x | - | integer | Copied from `D3_PERSONS`. | Year of birth | YYYY |
| sex_at_instance_creation | `D3_PERSONS/sex_at_instance_creation` | x | - | character | Copied from `D3_PERSONS`. | Sex recorded at instance creation | M, F |
| birth_date | `D3_PERSONS/birth_date` | x | - | date | Copied from `D3_PERSONS`; used to adjust `start_spell` when the spell begins before birth. | Date of birth | YYYY-MM-DD |
| death_date | `D3_PERSONS/death_date` | x | - | date | Copied from `D3_PERSONS`; used to adjust `end_spell` when the spell ends after death. | Date of death when available | YYYY-MM-DD |
| with_start_and_end | `D3_SPELLS/start_spell`, `D3_SPELLS/end_spell` | - | x | boolean | TRUE when both spell dates are non-missing. Only TRUE rows are retained. | Whether both spell dates are available | |
| start_before_end | `D3_SPELLS/start_spell`, `D3_SPELLS/end_spell` | - | x | boolean | TRUE when `start_spell < end_spell` (strictly); only TRUE rows are retained. | Whether the spell start precedes its end | |
## Processing Steps

This step creates observation spells from `D2_CDM/OBSERVATION_PERIODS` in the configured D2 database and joins them to `D3_PERSONS`. It merges periods per person when they overlap or are separated by no more than 180 days, adjusts spell boundaries to birth and death dates, retains only spells with both dates present and `start_spell < end_spell`, and writes `D3_SPELLS.parquet`.

1. Load `D3_PERSONS.parquet` and `OBSERVATION_PERIODS` from `data/D2_cdm/d2.duckdb`
2. For observation periods with `op_start_date < end_study_date` and a missing `op_end_date`, set `op_end_date` to `end_study_date`. Remove rows where both dates are missing; replace any remaining missing end dates with `end_study_date` before creating spells.
3. Group observation periods by `person_id`, merging overlapping periods and those whose next start is no later than 180 days after the previous maximum end. Set `start_spell` to the earliest start and `end_spell` to the latest end in each merged period.
4. Join spells to observation periods by `person_id` and `num_spell`, then join to `D3_PERSONS` by `person_id`. Adjust `start_spell` up to `birth_date` if it is earlier; adjust `end_spell` down to `death_date` if it is later. If an end date is still missing while the start is before `end_study_date`, set the end to `end_study_date`.
5. Set `with_start_and_end` when both dates are present and `start_before_end` when `start_spell < end_spell`. Retain only rows where both flags are TRUE, select the documented output columns, remove duplicate rows, and save `D3_SPELLS.parquet`.


## Example

| person_id      | start_spell | end_spell  | year_of_birth | sex_at_instance_creation | birth_date | death_date | with_start_and_end | start_before_end |
| -------------- | ----------- | ---------- | ------------- | ------------------------ | ---------- | ---------- | ------------------ | ---------------- |
| #ID-000000001# | 1964-10-22  | 2022-12-31 | 1957          | M                        | 1957-02-01 | NA         | TRUE               | TRUE             |
| #ID-000000002# | 1970-07-22  | 2022-12-31 | 1969          | M                        | 1969-08-01 | NA         | TRUE               | TRUE             |
| #ID-000000003# | 1963-12-19  | 2022-12-31 | 1956          | M                        | 1956-08-01 | NA         | TRUE               | TRUE             |
| #ID-000000004# | 1980-07-16  | 2022-12-31 | 1970          | M                        | 1970-08-01 | NA         | TRUE               | TRUE             |
| #ID-000000005# | 1972-01-30  | 2022-12-31 | 1961          | F                        | 1961-11-01 | NA         | TRUE               | TRUE             |
