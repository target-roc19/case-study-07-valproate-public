#' Create a new complex concept by applying OR logic to existing concept
#'  partitions in a Hive-style directory structure.
#'
#' @param input_dir Input directory containing partitioned parquet files.
#' @param output_dir Output directory where the new partition will be written.
#' @param complex_concept_name Name of the new complex concept
#'  to create (used as partition value).
#' @param sub_concept_ids Character vector of sub_concept_ids to include
#'  in the OR logic (matched against existing partitions).
#'
#' @returns Invisibly returns a list summarizing the operation,
#'  including matched partitions and output path.
create_majorca_cat <- function(
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

  # Open DuckDB connection
  con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  dir_d2_db <- config_project$create_complex_concepts$dir_d2_db

  # attach to d2.duckdb and create table EUROCAT in current connection
  DBI::dbExecute(
      con,
      glue::glue("ATTACH '{dir_d2_db}' AS d2_db (READ_ONLY);")
    )
  
  sub_concept_id <- tolower(params$sub_concept_ids)
   
   DBI::dbExecute(
    con,
    glue::glue(
      "CREATE OR REPLACE VIEW {params$complex_concept_name} AS
        SELECT DISTINCT
          NULL AS unique_id,
          'EUROCAT' AS ori_table,
          euro.person_id_child AS person_id,
          TRUE AS value,
          CAST(STRPTIME(euro.birth_date, '%Y%m%d') AS DATE) AS date,
          '{params$complex_concept_name}' AS concept_id
        FROM d2_db.ConcePTION.EUROCAT euro
        WHERE euro.{sub_concept_id} IS NOT NULL"
    )
  )
    
  DBI::dbExecute(
    con,
    glue::glue(
      "COPY (
        SELECT * EXCLUDE (concept_id),
          '{params$complex_concept_name}' AS concept_id
        FROM {params$complex_concept_name}
      ) TO '{params$output_dir}'
      (FORMAT PARQUET,  PARTITION_BY (concept_id), APPEND)"
    )
  )

  # Checking rows affected
  counts <- get_counts(
    connection = con,
    complex_concept_name = params$complex_concept_name,
    output_directory = params$output_dir
  )

  DBI::dbExecute(con, "DETACH DATABASE d2_db;")
  
  logger::log_info(crayon::cyan(
    'Counts:\n',
    paste(capture.output(print(t(counts), sep = ":"))[-1], collapse = '\n')
  ))
}
