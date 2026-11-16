#' Create treatment duration of more than 91 days
#'
#' @param input_dir Input directory containing partitioned parquet files.
#' @param output_dir Output directory where the new partition will be written.
#' @param complex_concept_name Name of the new complex concept
#'  to create (used as partition value).
#' @param sub_concept_ids Character vector of sub_concept_ids to include in the
#'   creation of the new complex concept.
#' @param use_test_data Logical flag. If TRUE, uses an in-memory test
#'   `prescription_duration` table instead of joining MEDICINES.
#'
#' @returns NULL
#'
#' @examples
create_treatment_episodes <- function(
  input_dir,
  output_dir,
  complex_concept_name = NULL,
  sub_concept_ids = NULL,
  use_test_data = FALSE
) {
  # Normalise inputs
  params <- normalise_inputs(
    input_dir = input_dir,
    output_dir = output_dir,
    complex_concept_name = complex_concept_name,
    sub_concept_ids = sub_concept_ids
  )
  # Validate inputs
  validate_inputs(
    input_dir = params$input_dir,
    complex_concept_name = params$complex_concept_name,
    sub_concept_ids = params$sub_concept_ids
  )
  # Clean output directory
  ensure_clean_output_directory(params$output_dir, params$complex_concept_name)

  # Getting existing sub_concept_ids
  existing_sub_concepts <- prepare_sub_concept_ids(
    sub_concept_ids = params$sub_concept_ids,
    input_directory = params$input_dir
  )

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Initial view
  DBI::dbExecute(
    con,
    glue::glue(
      "CREATE OR REPLACE VIEW {params$complex_concept_name} AS
     SELECT *
     FROM read_parquet(
     '{params$input_dir}/**/*.parquet',
     hive_partitioning = true,
     union_by_name     = true)
     WHERE concept_id IN ({partitions})",
      partitions = paste0("'", existing_sub_concepts, "'", collapse = ", ")
    )
  )

  if (isTRUE(use_test_data)) {
    DBI::dbExecute(
      con,
      "CREATE OR REPLACE TEMP TABLE temp_prescription_duration AS
        SELECT *
        FROM (
          VALUES
            (1, DATE '2024-01-10', 30),
            (1, DATE '2024-02-05', 28),
            (1, DATE '2024-04-20', 60),
            (2, DATE '2024-03-01', 14),
            (2, DATE '2024-03-20', 30),
            (2, DATE '2024-05-25', 15),
            (3, DATE '2024-01-01', 90),
            (3, DATE '2024-04-15', 30),
            (3, DATE '2024-06-20', 30),
            (4, DATE '2024-02-12', 7),
            (4, DATE '2024-03-18', 7),
            (4, DATE '2024-06-01', 14),
            (5, DATE '2024-01-25', 28),
            (5, DATE '2024-02-20', 21),
            (5, DATE '2024-03-01', 45)
        ) AS t(person_id, date, presc_duration)"
    )

    DBI::dbExecute(
      con,
      "CREATE OR REPLACE VIEW prescription_duration AS
        SELECT
          NULL AS unique_id,
          person_id,
          date,
          presc_duration
        FROM temp_prescription_duration"
    )
  } else {
    dir_d2_db <- config_project$create_complex_concepts$dir_d2_db

    # attach to d2.duckdb and obtain presc_duration from MEDICINES table
    DBI::dbExecute(
      con,
      glue::glue("ATTACH '{dir_d2_db}' AS d2_db (READ_ONLY);")
    )

    DBI::dbExecute(
      con,
      glue::glue(
        "CREATE OR REPLACE VIEW prescription_duration AS
          SELECT
            t1.unique_id,
            t1.person_id,
            t1.date,
            t2.presc_duration_days AS presc_duration
          FROM {params$complex_concept_name} t1
          INNER JOIN d2_db.main.MEDICINES t2
          ON t1.unique_id = t2.unique_id"
      )
    )
  }

  # Execute main query
  tryCatch(
    {
      query <- picard::load_sql_query(
        file.path(config_t2$sql_dir, "treatment_episodes.sql")
      )
      query <- glue::glue(
        query,
        complex_concept_name = params$complex_concept_name,
        start_study_date = config_values$start_study_date,
        end_study_date = config_values$end_study_date
      )

      DBI::dbExecute(con, query)

      # Register person_ids from D3_SPELLS parquet directly into DuckDB ---
      logger::log_info("Registering person_ids from D3_SPELLS parquet into DuckDB.")
      D3_spells_dir <- file.path(config_project$create_complex_concepts$spells_dir)
      DBI::dbExecute(
        con,
        glue::glue(
          "CREATE OR REPLACE TEMP TABLE all_persons AS
           SELECT *
           FROM read_parquet('{D3_spells_dir}')"
        )
      )

      query <- picard::load_sql_query(
        file.path(config_t2$sql_dir, "univariate_treatment_episodes.sql")
      )

      query <- glue::glue(
        query,
        complex_concept_name = params$complex_concept_name,
        start_study_date = config_values$start_study_date,
        end_study_date = config_values$end_study_date
      )

      # Export results to partitioned parquet
      DBI::dbExecute(
        con,
        glue::glue(
          "COPY (
            {query}
          ) TO '{params$output_dir}'
          (FORMAT PARQUET, PARTITION_BY (concept_id), APPEND)"
        )
      )
    },
    error = function(e) {
      rlang::abort(
        glue::glue(
          "SQL script failed for '{params$complex_concept_name}':\n
            {conditionMessage(e)}"
        ),
        class = "duckdb_copy_error"
      )
    }
  )

  # Checking rows affected
  counts <- get_counts(
    connection = con,
    complex_concept_name = params$complex_concept_name,
    output_directory = params$output_dir
  )

  logger::log_info(crayon::cyan(
    "Counts:\n",
    paste(capture.output(print(t(counts), sep = ":"))[-1], collapse = "\n")
  ))
}
