create_death <- function(
  input_dir,
  output_dir,
  complex_concept_name = NULL,
  sub_concept_ids = NULL
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

  # Open DuckDB connection
  picard::load_config()
  d3_spells_dir <- config_project$create_simple_concepts$d3_spells

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Initial view
  DBI::dbExecute(
    con,
    glue::glue(
      "CREATE OR REPLACE VIEW {params$complex_concept_name} AS
     SELECT *
     FROM read_parquet(
     '{d3_spells_dir}'
     )",
      partitions = paste0("'", existing_sub_concepts, "'", collapse = ", ")
    )
  )
  tryCatch(
    {
      DBI::dbExecute(
        con,
        glue::glue(
          "COPY (
            SELECT 
              'D3_SPELLS' AS ori_table, 
              NULL AS unique_id,
              person_id,
              NULL AS code, 
              NULL AS coding_system,
              CAST(TRUE AS VARCHAR) AS value,
              death_date AS date, 
              '{params$complex_concept_name}' AS concept_id
            FROM {params$complex_concept_name}
            WHERE death_date IS NOT NULL
          ) TO '{params$output_dir}'
          (FORMAT PARQUET,  PARTITION_BY (concept_id), APPEND)"
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

  # # Checking rows affected
  counts <- get_counts(
    connection = con,
    complex_concept_name = params$complex_concept_name,
    output_directory = params$output_dir
  )
  logger::log_info(crayon::cyan(
    'Counts:\n',
    paste(capture.output(print(t(counts), sep = ":"))[-1], collapse = '\n')
  ))
}
