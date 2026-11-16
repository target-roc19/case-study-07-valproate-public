-- order all prescriptions by person_id, date, and duration
CREATE TEMP TABLE treatment_episodes AS
WITH RECURSIVE
    ordered_prescriptions AS (
        SELECT
            person_id,
            CAST(date AS DATE) AS start_episode,
            CAST(presc_duration AS INTEGER) AS presc_duration,
            ROW_NUMBER() OVER (
                PARTITION BY
                    person_id
                ORDER BY
                    CAST(date AS DATE),
                    CAST(presc_duration AS INTEGER)
            ) AS rn
        FROM
            prescription_duration
        WHERE
            person_id IS NOT NULL
            AND date IS NOT NULL
            AND presc_duration IS NOT NULL
            AND CAST(presc_duration AS INTEGER) >= 0
    ),
    -- create treatment windows by iterating through ordered prescriptions and extending 
    -- the end date if the next prescription starts before the current end date
    expanded_windows AS (
        SELECT
            person_id,
            rn,
            start_episode,
            presc_duration,
            start_episode + (presc_duration || ' days')::INTERVAL AS end_episode
        FROM
            ordered_prescriptions
        WHERE
            rn = 1
        UNION ALL
        SELECT
            nxt.person_id,
            nxt.rn,
            nxt.start_episode,
            nxt.presc_duration,
            CASE
                WHEN nxt.start_episode < prv.end_episode THEN nxt.start_episode + (
                    (
                        nxt.presc_duration + date_diff(
                            'day',
                            nxt.start_episode,
                            CAST(prv.end_episode AS DATE)
                        )
                    ) || ' days'
                )::INTERVAL
                ELSE nxt.start_episode + (nxt.presc_duration || ' days')::INTERVAL
            END AS end_episode
        FROM
            expanded_windows prv
            INNER JOIN ordered_prescriptions nxt ON nxt.person_id = prv.person_id
            AND nxt.rn = prv.rn + 1
    ),
    -- identify gaps of more than 30 days between treatment windows to define new treatment spells
    gap_flags AS (
        SELECT
            person_id,
            start_episode,
            CAST(end_episode AS DATE) AS end_episode,
            CASE
                WHEN LAG (CAST(end_episode AS DATE)) OVER (
                    PARTITION BY
                        person_id
                    ORDER BY
                        start_episode,
                        rn
                ) IS NULL THEN 1
                WHEN start_episode > LAG (CAST(end_episode AS DATE)) OVER (
                    PARTITION BY
                        person_id
                    ORDER BY
                        start_episode,
                        rn
                ) + INTERVAL '31 days' THEN 1
                ELSE 0
            END AS new_spell_flag
        FROM
            expanded_windows
    ),
    -- 
    spell_numbered AS (
        SELECT
            person_id,
            start_episode,
            end_episode,
            SUM(new_spell_flag) OVER (
                PARTITION BY
                    person_id
                ORDER BY
                    start_episode,
                    end_episode ROWS BETWEEN UNBOUNDED PRECEDING
                    AND CURRENT ROW
            ) AS spell_id
        FROM
            gap_flags
    ),
    -- aggregate treatment windows into treatment spells by taking the min start date and max end date for each spell_id, 
    -- and extend the end date by 30 days to account for residual effects of treatment
    concatenated_spells AS (
        SELECT
            person_id,
            MIN(start_episode) AS start_episode,
            MAX(end_episode) + INTERVAL '30 days' AS end_episode
        FROM
            spell_numbered
        GROUP BY
            person_id,
            spell_id
    ),
    -- pair each spell with the next spell start per person
    spells_with_next AS (
        SELECT
            person_id,
            CAST(start_episode AS DATE) AS start_episode,
            CAST(end_episode AS DATE) AS end_episode,
            LEAD (CAST(start_episode AS DATE)) OVER (
                PARTITION BY
                    person_id
                ORDER BY
                    CAST(start_episode AS DATE),
                    CAST(end_episode AS DATE)
            ) AS next_start_episode
        FROM
            concatenated_spells
    ),
    -- output TRUE rows for treatment episodes and FALSE rows for explicit gaps
    treatment_switches AS (
        SELECT
            person_id,
            TRUE AS value,
            start_episode,
            end_episode,
            '{complex_concept_name}' AS concept_id
        FROM
            spells_with_next
        UNION ALL
        SELECT
            person_id,
            FALSE AS value,
            CAST(end_episode + INTERVAL '1 day' AS DATE) AS start_episode,
            CAST(next_start_episode - INTERVAL '1 day' AS DATE) AS end_episode,
            '{complex_concept_name}' AS concept_id
        FROM
            spells_with_next
        WHERE
            next_start_episode IS NOT NULL
            AND CAST(end_episode + INTERVAL '1 day' AS DATE) <= CAST(next_start_episode - INTERVAL '1 day' AS DATE)
    ),
    -- trim treatment switches to study period
    trimmed_switches AS (
        SELECT
            person_id,
            value,
            CASE
                WHEN start_episode < DATE('{start_study_date}') THEN DATE('{start_study_date}')
                ELSE start_episode
            END AS start_episode,
            CASE
                WHEN end_episode > DATE('{end_study_date}') THEN DATE('{end_study_date}')
                ELSE end_episode
            END AS end_episode,
            concept_id
        FROM
            treatment_switches
        WHERE
            end_episode >= DATE('{start_study_date}')
            AND start_episode <= DATE('{end_study_date}')
    ),
    ranked_switches AS (
        SELECT
            person_id,
            value,
            start_episode,
            end_episode,
            concept_id,
            ROW_NUMBER() OVER (
                PARTITION BY
                    person_id
                ORDER BY
                    start_episode,
                    end_episode,
                    value DESC
            ) AS rn_asc,
            ROW_NUMBER() OVER (
                PARTITION BY
                    person_id
                ORDER BY
                    start_episode DESC,
                    end_episode DESC,
                    value ASC
            ) AS rn_desc
        FROM
            trimmed_switches
        WHERE
            start_episode <= end_episode
    ),
    before_first_false AS (
        SELECT
            person_id,
            FALSE AS value,
            DATE('{start_study_date}') AS start_episode,
            CAST(start_episode - INTERVAL '1 day' AS DATE) AS end_episode,
            concept_id
        FROM
            ranked_switches
        WHERE
            rn_asc = 1
            AND start_episode > DATE('{start_study_date}')
    ),
    after_last_false AS (
        SELECT
            person_id,
            FALSE AS value,
            CAST(end_episode + INTERVAL '1 day' AS DATE) AS start_episode,
            DATE('{end_study_date}') AS end_episode,
            concept_id
        FROM
            ranked_switches
        WHERE
            rn_desc = 1
            AND end_episode < DATE('{end_study_date}')
    ),
    treatment_switches_completed AS (
        SELECT
            person_id,
            value,
            start_episode,
            end_episode,
            concept_id
        FROM
            ranked_switches
        UNION ALL
        SELECT
            person_id,
            value,
            start_episode,
            end_episode,
            concept_id
        FROM
            before_first_false
        WHERE
            start_episode <= end_episode
        UNION ALL
        SELECT
            person_id,
            value,
            start_episode,
            end_episode,
            concept_id
        FROM
            after_last_false
        WHERE
            start_episode <= end_episode
    )
SELECT
    CAST(person_id AS VARCHAR) AS person_id,
    value,
    start_episode,
    end_episode,
    concept_id
FROM
    treatment_switches_completed
ORDER BY
    person_id,
    start_episode,
    value DESC;
