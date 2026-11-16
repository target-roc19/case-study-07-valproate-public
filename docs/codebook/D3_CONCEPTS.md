## Metadata

| Table name                | concept_table (in D3_concepts.db)                                                                                                                                                                                                                                                   |
| ------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Concept table specific for the study. This database has the records related to each concept used in the study.                                                                                                                                                                      |
| Source                    | D2_CDM,D3_SPELLS, dap_specific_codelist_<cdm_tab>.parquet, RWEBRIDGE:`concept_preprocessing.csv ` , RWEBRIDGE:`concept_meaning.csv `                                                                                     |
| Step                      | transformations/T2_semantic_harmonization/create_simple_concepts.R, transformations/T2_semantic_harmonization/create_complex_concepts.R                                                                                                                                             |
| Content                   | Records from D2_CDM categorized in `concept_id`.                                                                                                                                                                                                                                    |
| Population                | All population selected within the `D3_SPELLS` table, for this study is the older adults                                                                                                                                                                                            |
| Unit of Observation (UoO) | All records that can be categorized on `concept_id`. Thus, we have one row per record categorized by one or more concept ids (it is possible that the same record is categorized in different concepts). Only exclude records before the `since_when_data_complete` date defined in D2_CDM/INSTANCE table |
| File format               | Parquet file organised in a Parquet Hive with '`concept_id`' as the partition variable.                                                                                                                                                                                             |

## Codebook
| variable_in_output | variable(s) needed                                                                                                       | retrieved | computed | format | rule_of_calculation  | description                                                                                                | vocabulary                                 |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------ | --------- | -------- | ------ | -------------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| person_id          | D2_CDM/<cdm_table>/person_id, D3_SPELLS/person_id                                                                        | x         |          | string |                      | Unique person identifier                                                                                   |                                            |
| ori_table          | D2_CDM/<cdm_table>/table                                                                                                 | x         |          | string |                      | Origin table name (CDM)                                                                                    | EVENTS, VACCINES, MEDICAL_OBSERVATIONS,... |
| unique_id          | D2_CDM/<cdm_table>/unique_id                                                                                             | x         |          | string |                      | A Universally Unique Identifier (UUID) is a 128-bit number, displayed as a 36-character hexadecimal string |                                            |
| concept_id         | dap_specific_codelist_<cdm_table>/concept_id, dap_specific_concept_map/concept_id, preprocessing_concepts.csv/concept_id | x         |          | string |                      | Concept name assigned from the study codelists and concept map                                             |                                            |
| coding_system      | codelist_<cdm_table>/coding_system                                                                                       | x         |          | string |                      | Coding system used for identifying the code                                                                |                                            |
| code               | codelist_<cdm_table>/code                                                                                                | x         |          | string |                      | Code matched to the study codelist                                                                         |                                            |
| date               | D2_CDM/<cdm_table>/<date column>, dap_specific_concept_map/keep_date_column                                              | x         |          | date   |                      | Date on which the code and coding system were recorded                                                     |                                            |
| value              | D2_CDM/<cdm_table>/<value column>, dap_specific_concept_map/keep_value_column                                            |           | x        | string | see processing steps | Numeric, boolean, or categorical value retained for the concept                                            | INT,TRUE/FALSE,CAT                         |
## Creation of simple concepts

| Step number                       | Actions                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Step 1                            | Assign `since_when_data_complete` as D2_CDM / INSTANCE table `since_when_data_complete` column value                                                                                                                                                                                                                                                                                                                                                                 |
| Use of dap_specific_codelists     |                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Step 2                            | Import DAP_SPECIFIC codelists to the database for each CDM table that has a dap_specific_codelist (from now in this explanation <add_cdm_table_name_here>_codelist). Select rows where match_status = 'MATCHED', apply unique by `code`, `coding_system` and `concept_id`                                                                                                                                                            |
| Step 3                            | Create temporal table for each CDM table with concept information select records that fall after the 'date column' > `since_when_data_complete`. the value column is defined as TRUE when using the codelist.                                                                                                                                                                                                                          |
|                                   | **If events_codelist available** For EVENTS: For `events_code` apply upper. Then, events.event_code = event_free_text IF event_record_vocabulary = 'FREE_TEXT ELSE events.event_code = events.code event_code                                                                                                                                                                                                                        |
|                                   | **If medicines_codelist available** For MEDICINES: apply upper to medicines.code = upper("medicinal_product_atc_code") medicines.coding_system = "PRODCODEID" WHEN DAP == CPRD else "ATC", medicines.date =`medicines.date_prescription` WHEN `medicines.date_dispensing` IS NULL ELSE `medicines.date_dispensing                                                                                                                    |
|                                   | **If vaccines_codeslist available** For VACCINES:vaccines.code ` = upper(`vaccines.vx_type `) WHEN `vaccines.vx_atc ` IS NULL OR vx_atc = ' ' ELSE upper(vaccines.x_atc) , vaccines.date` = `vaccines.vx_record_date` WHEN `vaccines.vx_admin_date` IS NULL ELSE vaccines.vx_admin_date vaccines.coding_system `= 'VX_TYPE' WHEN`vaccines.vx_atc `IS NULL OR`vaccinesvx_atc `= ' ' ELSE 'VX_ATC'                                     |
|                                   | **If procedures_codeslist available** For PROCEDURES: For `procedure_code` apply upper                                                                                                                                                                                                                                                                                                                                               |
| Step 4                            | Delete records from the temporal table that date is empty                                                                                                                                                                                                                                                                                                                                                                            |
| Step 5                            | Apply join between DAP specific codelist and temporal CDM table                                                                                                                                                                                                                                                                                                                                                                      |
|                                   | - For EVENTS: events.event_code = events_codelist.code AND events.event_record_vocabulary = events_codelist.`coding_system`                                                                                                                                                                                                                                                                                                          |
|                                   | - For MEDICINES: medicines.code = medicines_codelist.code AND medicines.`coding_system` = t2.`coding_system`                                                                                                                                                                                                                                                                                                                         |
| Step 6                            | Add results in concept_table with the column names as described above                                                                                                                                                                                                                                                                                                                                                                |
| Use of `dap_specific_concept_map` |                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Step 7                            | Using the RWEBRIDGE::`dap_specific_concept_map` table, records that follow the combination of values in the `expected_value_X` column within the cdm column names defined in the `column_name_X`. <br /><br />Select the **date** of the concept as: CDM column defined in the `keep_date_column_name`, date >= `start_look_back`. <br />Select the **value** of the concept as: CDM column defined in the `keep_value_column_name`. |
| Step 8                            | Add results in concept_table with the column names as described above                                                                                                                                                                                                                                                                                                                                                                |

## Creation of complex concepts

In this process, we generate ALL possible records related to each of the new concepts (aka complex concepts) during the person's medical history. So, when applicable, we keep all combinations of records (e.g., BMI calculated from height and weight).

We will select the final record used for the analysis during the anchoring process. This process is applied on the D4_StudyVariables_Anchored

Each row in `concept_preprocessing.csv` selects a function and its input sub-concepts. The functions are described below.

### `is_between_18_and_50`

Creates age-status change records directly from `D3_SPELLS`, using each person's birth date: `FALSE` at birth, `TRUE` on the 18th birthday, and `FALSE` on the 51st birthday.

### `create_or`

Reads records whose `concept_id` is one of the configured sub-concepts and writes them under the new complex `concept_id`. It preserves the other record fields, including `value`, and retains the input records as separate rows.

### `create_or_true`

Reads records for the configured sub-concepts, writes them under the new complex `concept_id`, and replaces each `value` with `TRUE`.

### `create_majorca_cat`

Reads EUROCAT records and uses the configured sub-concept name as a EUROCAT column (case-insensitive via lowercasing). For each record where that column is non-null, it creates a `TRUE` concept record for the child, dated at the child's birth date. The source category value is not carried into the output.

### `create_treatment_episodes`

Uses prescription dates and durations for the configured treatment concept to construct treatment periods. Overlapping prescription windows are extended, and windows are combined into one treatment spell unless the next prescription starts more than 31 days after the previous window ends. Each spell is extended by 30 days, then emitted as `TRUE`; explicit gaps between spells are emitted as `FALSE`. Periods are clipped to the configured study dates. People with no treatment episode receive a `FALSE` period covering the study period.

### `create_death`

Creates one `DEATH` record for each non-null `D3_SPELLS.death_date`, with `date` set to the death date and `value = TRUE`. `ori_table` is `D3_SPELLS`; `unique_id`, `code`, and `coding_system` are null.

### `create_obesity`

Creates `TRUE` records for BMI values greater than 30 and for records in `L_OBESITY_COV`, rewriting their `concept_id` to the configured obesity concept. The current implementation hard-codes these two inputs rather than using the configured sub-concept list to determine which concepts to include.

### `apply_concept_meaning`

Joins records for the configured sub-concepts to the `concept_meaning` metadata by sub-concept `concept_id`. It writes the matching meaning into `value` and assigns the new complex `concept_id`. If multiple matching sub-concepts are present for a person, multiple rows are retained and a warning is logged.

### `create_enrol12m`

Uses `D3_SPELLS` to identify continuous-enrolment spells lasting at least 12 months, including spells that start at birth. It writes `TRUE` at the eligible spell start (at the start date for a birth-starting spell, otherwise one year after the spell starts) and `FALSE` the day after the spell ends. Spells shorter than 12 months are omitted.


---


## Processing Steps

The T2 concept-processing scripts load CDM records, D3 spells, RWE-BRIDGE codelists, and the concept map. They harmonize source codes, assign study concept identifiers, retain relevant dates and values, and write concept records partitioned by concept_id.


## Example

| ori_table            | unique_id | person_id      | code          | coding_system | value | date       | concept_id |
| -------------------- | --------- | -------------- | ------------- | ------------- | ----- | ---------- | ---------- |
| MEDICAL_OBSERVATIONS | <raw>     | #ID-000000001# | dap_spec_id-1 | dap_spec_id-1 | 23.400  | 2000-01-01 | AD_BMI     |
| MEDICAL_OBSERVATIONS | <raw>     | #ID-000000001# | dap_spec_id-1 | dap_spec_id-1 | 26.100  | 2000-12-31 | AD_BMI     |
| MEDICAL_OBSERVATIONS | <raw>     | #ID-000000001# | dap_spec_id-1 | dap_spec_id-1 | 23.900  | 2001-12-31 | AD_BMI     |
| MEDICAL_OBSERVATIONS | <raw>     | #ID-000000001# | dap_spec_id-1 | dap_spec_id-1 | 24    | 2002-12-31 | AD_BMI     |
| MEDICAL_OBSERVATIONS | <raw>     | #ID-000000001# | dap_spec_id-1 | dap_spec_id-1 | 26.300  | 2003-12-31 | AD_BMI     |
