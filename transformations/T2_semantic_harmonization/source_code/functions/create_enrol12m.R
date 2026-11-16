create_enrol12m <- function(
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

  con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Initial view
  DBI::dbExecute(
    con,
    glue::glue(
      "CREATE OR REPLACE VIEW D3_SPELLS AS
     SELECT *
     FROM read_parquet(
     '{d3_spells_dir}'
     )",
      partitions = paste0("'", existing_sub_concepts, "'", collapse = ", ")
    )
  )

  query <- picard::load_sql_query(file.path(
    config_project$create_complex_concepts$sql,
    "calculate_enrolment_12m.sql"
  ))
  query <- glue::glue(query)
  tryCatch(
    {
      DBI::dbExecute(
        con,
        glue::glue(
          "COPY (
            {query}
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
  # validation <- validate_output(
  #   connection = con,
  #   complex_concept_name = params$complex_concept_name,
  #   output_directory = params$output_dir,
  #   simple_concept_table = "D3_SPELLS"
  # )

  # logger::log_info(crayon::cyan(
  #   '\nCounts:\n',
  #   paste(
  #     capture.output(print(t(validation$counts), sep = ":"))[-1],
  #     collapse = '\n'
  #   )
  # ))
}
