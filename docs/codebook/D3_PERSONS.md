## Metadata

| Table name                | D3_PERSONS |
| ------------------------- | ---------- |
| Description               | Person records with standardized sex, imputed date components, derived birth and death dates, and data-quality indicators. |
| Source                    | `D2_CDM/PERSONS`|
| Step                      | `transformations/T2_semantic_harmonization/source_code/process_persons.R` |
| Content                   | Processed records from the configured persons source table. |
| Population                | Persons retained after the documented birth-year, death-data consistency, death-before-birth, duplicate-ID, and sex filters. |
| Unit of Observation (UoO) | One row per retained `person_id`. |
| File format               | Parquet file (`D3_PERSONS.parquet`). |

## Codebook
| variable_in_output | variable(s) needed | retrieved | computed | format | rule_of_calculation | description | vocabulary |
| ------------------ | ------------------ | --------- | -------- | ------ | ------------------- | ----------- | ---------- |
| `person_id` | `PERSONS/person_id` | x | | character | Retained from the input; only the first row for each `person_id` is kept. | Key identifier | |
| `sex_at_instance_creation` | `PERSONS/sex_at_instance_creation` | x | | character | Keep `F` and `M`; replace other values with missing. Rows with missing sex are later removed. | Sex at instance creation | F, M |
| `imputed_birth_day` | `PERSONS/year_of_birth`, `PERSONS/day_of_birth` | | x | Boolean (TRUE/FALSE) | TRUE when `year_of_birth` is present and `day_of_birth` is missing; otherwise FALSE. | Whether the birth day was imputed | |
| `imputed_birth_month` | `PERSONS/year_of_birth`, `PERSONS/month_of_birth`, `PERSONS/day_of_birth` | | x | Boolean (TRUE/FALSE) | TRUE when `year_of_birth` is present and `month_of_birth` is missing; otherwise FALSE. | Whether the birth month was imputed | |
| `imputed_death_day` | `PERSONS/year_of_death`, `PERSONS/day_of_death` | | x | Boolean (TRUE/FALSE) | TRUE when `year_of_death` is present and `day_of_death` is missing; otherwise FALSE. | Whether the death day was imputed | |
| `imputed_death_month` | `PERSONS/year_of_death`, `PERSONS/month_of_death`, `PERSONS/day_of_death` | | x | Boolean (TRUE/FALSE) | TRUE when `year_of_death` is present and `month_of_death` is missing; otherwise FALSE. | Whether the death month was imputed | |
| `birth_date` | `PERSONS/year_of_birth`, `PERSONS/month_of_birth`, `PERSONS/day_of_birth` | | x | Date (YYYY-MM-DD) | Combine the year, month, and day when all are present; otherwise set to missing. | Date of birth | |
| `death_date` | `PERSONS/year_of_death`, `PERSONS/month_of_death`, `PERSONS/day_of_death` | | x | Date (YYYY-MM-DD) | Combine the year, month, and day when all are present; otherwise set to missing. | Date of death | |
| `missing_year_of_birth` | `PERSONS/year_of_birth` | | x | Boolean (TRUE/FALSE) | TRUE when `year_of_birth` is missing; otherwise FALSE. Rows where this is TRUE are removed. | Whether the birth year is missing | |
| `not_missing_year_death` | `PERSONS/year_of_death`, `PERSONS/day_of_death`, `PERSONS/month_of_death` | | x | Boolean (TRUE/FALSE) | FALSE when `year_of_death` is missing and either `day_of_death` or `month_of_death` is present; TRUE otherwise. Rows where this is FALSE are removed. | Death date components pass the script's missing-year check | |
| `death_before_birth` | `PERSONS/year_of_birth`, `PERSONS/month_of_birth`, `PERSONS/day_of_birth`, `PERSONS/year_of_death`, `PERSONS/month_of_death`, `PERSONS/day_of_death` | | x | Boolean (TRUE/FALSE) | TRUE when `death_date < birth_date`; missing comparisons are set to FALSE. Rows where this is TRUE are removed. | Whether death occurred before birth | |
| `missing_sex` | `PERSONS/sex_at_instance_creation` | | x | Boolean (TRUE/FALSE) | TRUE when sex is missing or not `F`/`M`; otherwise FALSE. Such rows are removed before output. | Whether sex is missing or invalid | |
| `year_of_birth` | `PERSONS/year_of_birth` | x | | integer | Convert the input value to integer; retained in output. | Year of birth | |
## Processing Steps

The script reads the configured persons table, standardizes sex and date components, derives dates and quality indicators, applies quality filters, and writes `D3_PERSONS.parquet`.

1. With the current configuration, read `main.PERSONS` from `data/D2_cdm/d2.duckdb`. Convert birth and death year/month/day columns to integers.
2. Keep `F` and `M` in `sex_at_instance_creation`; set other values to missing.
3. If the corresponding year is present and birth or death day is missing, set the imputation flag and impute the day as `16`. If the corresponding year is present and month is missing, set the imputation flag and impute month as `6`; if that month was imputed and day is `31`, set month to `5` instead.
4. Derive `missing_year_of_birth`, `not_missing_year_death`, and `missing_sex` according to the codebook rules. The death-year check is FALSE only when `year_of_death` is missing and at least one of `day_of_death` or `month_of_death` is present.
5. Create `birth_date` and `death_date` when all corresponding date components are present. Set `death_before_birth` TRUE when `death_date < birth_date`; missing comparisons are FALSE.
6. Remove rows with a missing birth year, `not_missing_year_death == FALSE`, `death_before_birth == TRUE`, a previously retained duplicate `person_id`, or missing sex. No age or study-period filter is applied.
7. Keep the documented output columns and save `D3_PERSONS.parquet`.

## Example

| person_id      | sex_at_instance_creation | imputed_birth_day | imputed_birth_month | imputed_death_day | imputed_death_month | birth_date | death_date | missing_year_of_birth | not_missing_year_death | death_before_birth | missing_sex | year_of_birth |
| -------------- | ------------------------ | ----------------- | ------------------- | ----------------- | ------------------- | ---------- | ---------- | --------------------- | ---------------------- | ------------------ | ----------- | ------------- |
| #ID-000000007# | F                        | FALSE             | FALSE               | FALSE             | FALSE               | 1943-01-01 | NA         | FALSE                 | TRUE                   | FALSE              | FALSE       | 1943          |
| #ID-000000009# | M                        | FALSE             | FALSE               | FALSE             | FALSE               | 2010-08-01 | NA         | FALSE                 | TRUE                   | FALSE              | FALSE       | 2010          |
| #ID-000000017# | M                        | FALSE             | FALSE               | FALSE             | FALSE               | 1965-04-01 | NA         | FALSE                 | TRUE                   | FALSE              | FALSE       | 1965          |
| #ID-000000032# | F                        | FALSE             | FALSE               | FALSE             | FALSE               | 1939-04-01 | NA         | FALSE                 | TRUE                   | FALSE              | FALSE       | 1939          |
| #ID-000000043# | M                        | FALSE             | FALSE               | FALSE             | FALSE               | 1985-04-01 | NA         | FALSE                 | TRUE                   | FALSE              | FALSE       | 1985          |
