WITH
    base AS (
        SELECT
            person_id,
            birth_date,
            start_spell,
            end_spell,
            CASE
                WHEN birth_date = start_spell THEN 1
                ELSE 0
            END AS start_at_birth,
            (end_spell - start_spell) AS length_spell_days
        FROM
            D3_SPELLS
    ),
    eligible AS (
        SELECT
            person_id,
            start_at_birth,
            CASE
                WHEN start_at_birth = 0 THEN (start_spell + INTERVAL '1 year')::date
                ELSE start_spell
            END AS start_spell_adj,
            (end_spell + INTERVAL '1 day')::date AS end_spell_adj
        FROM
            base
        WHERE
            start_at_birth = 1
            OR length_spell_days > 365
    ),
    long_events AS (
        SELECT
            person_id,
            start_spell_adj AS date,
            TRUE AS value
        FROM
            eligible
        UNION ALL
        SELECT
            person_id,
            end_spell_adj AS date,
            FALSE AS value
        FROM
            eligible
    )
SELECT
    person_id,
    NULL AS ori_table,
    NULL AS unique_id,
    'ENROLLED_12M' AS concept_id,
    NULL AS coding_system,
    NULL  AS code,
    date,
    value
FROM
    long_events
WHERE
    date IS NOT NULL
