## Metadata

| Table name                | D3_FatherChild |
| ------------------------- | -------------- |
| Description               | Child linkage records with father, mother, date of birth, pregnancy identifier, and estimated conception date. |
| Source                    | `D2_CDM/PERSON_RELATIONSHIPS`, `D2_CDM/SURVEY_ID`, `D2_CDM/SURVEY_OBSERVATIONS`, and `D3_PERSONS`. |
| Step                      | `transformations/T2_semantic_harmonization/source_code/process_child_linkage.R` |
| Content                   | Links children to the first recorded registered father and birth mother, adds the child's date of birth, links the child and mother through a shared survey ID, and adds an estimated conception date when available. |
| Population                | Children with at least one `registered_father` or `birth_mother` relationship. The script applies no study-period birth-date restriction. |
| Unit of Observation (UoO) | Intended as one row per child; non-unique relationship, survey-ID, or matching observation records can result in multiple rows per child. |

## Codebook
| variable_in_output | variable(s) needed | retrieved | computed | format | rule_of_calculation | description | vocabulary |
| ------------------ | ------------------ | --------- | -------- | ------ | ------------------- | ----------- | ---------- |
| father_id | `PERSON_RELATIONSHIPS/person_id`, `PERSON_RELATIONSHIPS/related_id`, `PERSON_RELATIONSHIPS/meaning_of_relationship` | x | | character | Keep `meaning_of_relationship == "registered_father"`; grouped by `person_id` as child, take the first matching `related_id`. | Father identifier | |
| child_id | `PERSON_RELATIONSHIPS/person_id`, `PERSON_RELATIONSHIPS/meaning_of_relationship` | x | | character | Use `person_id` as the child key; only children with a `registered_father` or `birth_mother` relationship are included. | Child identifier | |
| date_of_birth | `D3_PERSONS/person_id`, `D3_PERSONS/birth_date` | x | | date | Match `D3_PERSONS/person_id` to `child_id`; use `birth_date` | Child date of birth | |
| pregnancy_id | `D3_FatherChild/father_id`, `D3_FatherChild/date_of_birth` | | x | integer | Order rows by `father_id`, `date_of_birth`, `child_id`; assign `data.table::rleid(father_id, date_of_birth)`. Rows with the same consecutive father/date pair share an ID; IDs increase across the ordered output. | Pregnancy/group identifier based on father and date of birth | |
| estimated_conception_date | `SURVEY_ID/person_id`, `SURVEY_ID/survey_id`, `SURVEY_ID/survey_meaning`; `SURVEY_OBSERVATIONS/survey_id`, `SURVEY_OBSERVATIONS/person_id`, `SURVEY_OBSERVATIONS/so_source_table`, `SURVEY_OBSERVATIONS/so_meaning`, `SURVEY_OBSERVATIONS/so_source_column`, `SURVEY_OBSERVATIONS/so_source_value` | x | | date | Link child and mother using a shared `SURVEY_ID/survey_id`; select observations where `so_source_table == "PREGNANCY_COHORT"`, `so_meaning == "birth_registry_mother"`, and `so_source_column == "pregnancy_start_date"`; parse `so_source_value` as `%Y%m%d` | Estimated conception date | |
| mother_id | `PERSON_RELATIONSHIPS/person_id`, `PERSON_RELATIONSHIPS/related_id`, `PERSON_RELATIONSHIPS/meaning_of_relationship`, `SURVEY_ID/person_id`, `SURVEY_ID/survey_id`, `SURVEY_ID/survey_meaning` | x | | character | Keep `meaning_of_relationship == "birth_mother"`; grouped by `person_id` as child, take the first matching `related_id`. Link the resulting mother to the child by matching child and mother records on `survey_id`. | Mother identifier | |
## Processing steps

1. Load `PERSON_RELATIONSHIPS.csv` and keep rows where `meaning_of_relationship` is `registered_father` or `birth_mother`. Group by `person_id` as `child_id`; for each child, take the first related ID matching each relationship type as `father_id` or `mother_id`.
2. Left join `D3_PERSONS.parquet` on `child_id == person_id` and take `birth_date` as `date_of_birth`.
3. From `SURVEY_ID.csv`, make child records from rows with `survey_meaning == "birth_registry_child"` and mother records from rows with `survey_meaning == "birth_registry_mother"`. Inner join these on `survey_id`, then left join the result to child linkage on both `child_id` and `mother_id`.
4. From `SURVEY_OBSERVATIONS.csv`, keep rows where `so_source_table == "PREGNANCY_COHORT"`, `so_meaning == "birth_registry_mother"`, and `so_source_column == "pregnancy_start_date"`. Parse `so_source_value` as a `%Y%m%d` date and left join by `survey_id` and `mother_id == person_id` to create `estimated_conception_date`.
5. Order by `father_id`, `date_of_birth`, and `child_id`; assign `pregnancy_id` using `data.table::rleid(father_id, date_of_birth)`. No birth-date study-period filter is applied. Joins can create multiple output rows if their matching source keys are not unique.

## Example

| father_id | child_id | date_of_birth | pregnancy_id | estimated_conception_date | mother_id |
| --- | --- | --- | --- | --- | --- |
| #ID-000000001# | #ID-000002604# | 1974-12-01 | 1 | 1974-03-03 | #ID-000002611# |
| #ID-000000002# | #ID-000000361# | 1931-01-01 | 2 | 1930-04-03 | #ID-000000222# |
| #ID-000000002# | #ID-000003565# | 2012-09-11 | 3 | 2011-12-13 | #ID-000003465# |
| #ID-000000002# | #ID-000003665# | 2015-03-23 | 4 | 2014-06-23 | #ID-000003465# |
| #ID-000000003# | #ID-000001561# | 1967-12-01 | 5 | 1967-03-03 | #ID-000002877# |

