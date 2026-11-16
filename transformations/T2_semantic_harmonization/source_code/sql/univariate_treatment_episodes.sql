WITH
    persons_missing_episodes AS (
        SELECT
            person_id
        FROM
            all_persons
        WHERE
            person_id NOT IN (
                SELECT DISTINCT
                    person_id
                FROM
                    treatment_episodes
            )
    ),
    episode_missing AS (
        SELECT
            person_id,
            FALSE AS value,
            DATE('{start_study_date}') AS start_episode,
            DATE('{end_study_date}') AS end_episode,
            CAST('{complex_concept_name}' AS VARCHAR) AS concept_id
        FROM
            persons_missing_episodes
    ),
    all_episodes AS (
        SELECT
            person_id,
            value,
            start_episode,
            end_episode,
            concept_id
        FROM
            treatment_episodes
        UNION ALL
        SELECT
            person_id,
            value,
            start_episode,
            end_episode,
            concept_id
        FROM
            episode_missing
    )
SELECT
    *
FROM
    all_episodes
