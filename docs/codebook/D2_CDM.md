## Metadata

| Table name                | D2_CDM                                                                                                                                                                                                                                                                                  |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Database with all CDM tables available in the Data instance. The tables are edited so they include Unique Identifier for each records, table source and row ID. Moreover, records with missing `person_id` are deleted and repeated records are deleted for all table except MEDICINES. |
| Source                    | CDM data instance, PERSONS, VACCINES, MEDICINES, OBSERVATION_PERIODS, MEDICAL_OBSERVATIONS, EVENTS, SURVEY_OBSERVATIONS, SURVEY_ID, VISIT_OCCURRENCE, PROCEDURES                                                                                                                        |
| Step                      | transformations/T2_semantic_harmonization/`set_db.R`                                                                                                                                                                                                                                    |
| Content                   | CDM records from Data instance. One table within the Database per CDM table                                                                                                                                                                                                             |
| Population                | All population (all the records form the data instance, unless they have been excluded if repeated)                                                                                                                                                                                     |
| Unit of Observation (UoO) | One row per record if `person_id` it is not missing, otherwise delete                                                                                                                                                                                                                   |
| File format               | DuckDb database (d2.duckdb)                                                                                                                                                                                                                                                                   |

## Codebook

| variable_in_output | variable(s) needed               | retrieved | computed | format          | rule_of_calculation                 | description                                                                                                | vocabulary |
| ------------------ | -------------------------------- | --------- | -------- | --------------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------- | ---------- |
| `ori_table`        | D2_CDM/<source_table>/table_name |           | x        | String          | Add the name of the table of origin | Name of the CDM table source                                                                               |            |
| `unique_id`        | D2_CDM/<source_table>/unique_id  |           | x        | string          | Add an id number as an UUID         | A Universally Unique Identifier (UUID) is a 128-bit number, displayed as a 36-character hexadecimal string |            |
| \<CDM column 1\>   | cdm:CDM column 1                 | x         |          | string/int/date |                                     | Other CDM columns from the specific CDM table                                                              |            |
| ...                | ...                              | ...       | ...      | ...             | ...                                 | ...                                                                                                        |            |
| \<CDM column N\>   | cdm:CDM column N                 | x         |          | string/int/date |                                     | Other CDM columns from the specific CDM table                                                              |            |

## Processing Steps

| Step number | Action                                                                                      |
| ----------- | :------------------------------------------------------------------------------------------ |
| Step 1      | Import all csv files from the CDM to the database                                           |
| Step 2      | For each database, delete duplicates using all columns of the table, except MEDICINES table |
| Step 3      | Delete rows that miss `person_id`                                                           |
| Step 4      | Add the `ori_table` and `unique_id` columns to each table                                   |
| Step 5      | Save the number of rows per table                                                           |

## Example

| ori_table | unique_id                            | person_id      | day_of_birth | month_of_birth | year_of_birth | day_of_death | month_of_death | year_of_death | sex_at_instance_creation | race | country_of_birth | quality  |
| --------- | ------------------------------------ | -------------- | ------------ | -------------- | ------------- | ------------ | -------------- | ------------- | ------------------------ | ---- | ---------------- | -------- |
| PERSONS   | 2f7377fb-acc0-4714-8460-efff3b626050 | #ID-000000007# | 1            | 1              | 1943          | NA           | NA             | NA            | F                        | NA   | NA               | reliable |
| PERSONS   | 6596934d-5f8b-4f7a-b402-be2a0aec0b5a | #ID-000000009# | 1            | 8              | 2010          | NA           | NA             | NA            | M                        | NA   | South Asia       | reliable |
| PERSONS   | 38c950b7-d7e8-401c-b735-f7b250935f2f | #ID-000000017# | 1            | 4              | 1965          | NA           | NA             | NA            | M                        | NA   | South Asia       | reliable |
| PERSONS   | 76d4ad67-bdd2-4c58-a265-5a5faa85120c | #ID-000000032# | 1            | 4              | 1939          | NA           | NA             | NA            | F                        | NA   | Spain            | reliable |
| PERSONS   | c3ac5454-13b3-4e43-a098-307837d46a22 | #ID-000000043# | 1            | 4              | 1985          | NA           | NA             | NA            | M                        | NA   | Eastern Europe   | reliable |
