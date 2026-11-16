SELECT
    person_id,
    ori_table,
    unique_id,
    '{complex_concept_name}' AS concept_id,
    coding_system,
    code,
    date,
    'M' || month(date) || '_' || year(date) AS value
FROM
    "{complex_concept_name}"
