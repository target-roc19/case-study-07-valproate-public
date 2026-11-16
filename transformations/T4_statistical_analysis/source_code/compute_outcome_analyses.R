################################################################
# outcome_analysis_lookup ---
# Aim:
# Compute the D4 Cohort Analytic Lookup table by estimating incidence rates
# and risk ratios (Poisson or log-binomial) per outcome table row, combining
# descriptive and comparative measures into a single lookup table for downstream
# reporting.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohortFupChild.csv
# - data/D4_analytic_datasets/D4_PS_Weights_IPTW.csv
# - data/D4_analytic_datasets/D4_PS_Weights_IPCW.csv
# - data/D4_analytic_datasets/D4_PS_Weights_IPSMW.csv
# - transformations/common_configuration/outcome_analysis_types.csv
#
# Output: ---
# - data/D5_results/D5_CohortAnalyticLookup.csv
################################################################

# Initial setup ---
## Script logger ---
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("outcome_analysis_lookup")
  lm$start_capturing_prints()
}

logger::log_info("[Cohort Analytic Lookup] - START")

# ---------------------------------------------------------------------------
# Script body — config loading, I/O, audit (skipped when sourced for tests)
# Runs only when the picard LoggerManager (lm) is present, i.e., inside the
# pipeline runner. Sourcing from tests or interactively defines only the
# functions above.
# ---------------------------------------------------------------------------

## testing setup --
picard::load_config()
cfg <- config_project$outcome_analysis_lookup

## Audit setup ---
picard::audit_start(
  file_name = "outcome_analysis_lookup",
  deap_name = config_project$DEAP_configuration$name
)
dir_d4 <- config_project$outputs$dir_d4
dir_d5 <- config_project$outputs$dir_d5

dir_metadata <- file.path(config_t4$T4$root, config_t4$T4$metadata)
dir_function <- file.path(config_t4$T4$root, config_t4$T4$functions)

# if (!(base::exists("lm", inherits = TRUE) && base::inherits(lm, "LoggerManager"))) {
#   stop("LoggerManager (lm) is not defined. This script should be run within the pipeline runner.")
# }

## Load functions ---
source(file.path(dir_function, "cohort_analytic_lookup_functions.R"))
source(file.path(dir_function, "format_outcome_tables_functions.R"))

## Load metadata ---
# subset to enabled rows only
# update metadata when sensitivity analysis MI and BW are ready
outcome_analysis_types <- picard::load(
  file_path = dir_metadata,
  file_name = cfg$metadata$outcome_analysis_types
)[enabled == TRUE]

outcome_parameter_lookup <- picard::load(
  file_path = dir_metadata,
  file_name = cfg$metadata$outcome_parameter_lookup
)
## Load inputs ---
logger::log_info("Loading FUP and weight datasets.")
fup_files <- outcome_analysis_types$source_fup |> unique()
fup_datasets <- setNames(lapply(
  fup_files,
  function(filename) {
    picard::load(
      file_path = dir_d4,
      file_name = glue::glue("{filename}.{cfg$input$ext}")
    )
  }
), fup_files)

weight_files <- outcome_analysis_types$source_weight |> unique()
weight_files <- setdiff(weight_files, "")
weight_datasets <- setNames(lapply(
  weight_files,
  function(filename) {
    picard::load(
      file_path = dir_d4,
      file_name = glue::glue("{filename}.{cfg$input$ext}")
    )
  }
), weight_files)

## Run ---
logger::log_info("Running 5 cohort analysis")

D5_CohortAnalyticLookup_list <- iter_cohort_analytic_lookup(
  fup_datasets             = fup_datasets,
  weight_datasets          = weight_datasets,
  outcome_analysis_types   = outcome_analysis_types,
  aesi_name                = cfg$aesi_name,
  aesi_label               = cfg$aesi_label,
  scale_IR                 = cfg$scale_IR,
  n_bootstrap              = cfg$n_bootstrap,
  seed                     = cfg$seed,
  resample_col             = cfg$resample_col
)
logger::log_success("Completed 5 cohort analytic lookup.")

## Save unpooled results for reference
D5_CohortAnalyticLookup_unpooled <- data.table::rbindlist(D5_CohortAnalyticLookup_list, fill = TRUE, use.names = TRUE, idcol = "analysis_index")
picard::save(
  D5_CohortAnalyticLookup_unpooled,
  file_path = dir_d5,
  file_name = glue::glue("{cfg$output$name}_unpooled.{cfg$output$ext}")
)

## Pooling results for multiple imputations
D5_CohortAnalyticLookup_list_pooled <- pool_cohort_analytic_lookup(
  lookup_list = D5_CohortAnalyticLookup_list,
  outcome_analysis_types = outcome_analysis_types
)

D5_CohortAnalyticLookup <- data.table::rbindlist(
  Filter(function(x) data.table::is.data.table(x) && nrow(x) > 0L, D5_CohortAnalyticLookup_list_pooled),
  fill = TRUE,
  use.names = TRUE,
  idcol = "analysis_index"
)

## Save output ---
picard::save(
  data      = D5_CohortAnalyticLookup,
  file_path = dir_d5,
  file_name = glue::glue("{cfg$output$name}.{cfg$output$ext}")
)

## Create tables ---

# Create table 8 and 9 (pooled results; analysis index 1 and 2 from direct list output) ---
table8 <- create_table8(D5_CohortAnalyticLookup, outcome_parameter_lookup[1, ], use_boot_ci = FALSE)
table9 <- create_table9(D5_CohortAnalyticLookup, outcome_parameter_lookup[2, ], use_boot_ci = FALSE)
table8_boot <- create_table8(D5_CohortAnalyticLookup, outcome_parameter_lookup[1, ], use_boot_ci = TRUE)
table9_boot <- create_table9(D5_CohortAnalyticLookup, outcome_parameter_lookup[2, ], use_boot_ci = TRUE)

# Table 9.1 Description of Poisson regression model parameters
# <TBD>

## Create table 13 (BW scenarios; analysis index 4 from direct list output) ---
bw_lookup <- D5_CohortAnalyticLookup_list[["1b"]]
table13 <- create_table13(bw_lookup, use_boot_ci = FALSE)
table13_boot <- create_table13(bw_lookup, use_boot_ci = TRUE)

# Also save BW lookup table for reference
picard::save(
  data      = D5_CohortAnalyticLookup_list[["1b"]],
  file_path = dir_d5,
  file_name = glue::glue("{cfg$output$name}BW.{cfg$output$ext}")
)

## Save output ---
picard::save(
  data      = table8,
  file_path = dir_d5,
  file_name = glue::glue("D5_{cfg$output$table8_name}.{cfg$output$ext}")
)
picard::save(
  data      = table9,
  file_path = dir_d5,
  file_name = glue::glue("D5_{cfg$output$table9_name}.{cfg$output$ext}")
)
picard::save(
  data      = table13,
  file_path = dir_d5,
  file_name = glue::glue("D5_{cfg$output$table13_name}.{cfg$output$ext}")
)

# Save bootstrapped CI tables for reference
picard::save(
  data      = table8_boot,
  file_path = dir_d5,
  file_name = glue::glue("D5_{cfg$output$table8_name}_boot.{cfg$output$ext}")
)
picard::save(
  data      = table9_boot,
  file_path = dir_d5,
  file_name = glue::glue("D5_{cfg$output$table9_name}_boot.{cfg$output$ext}")
)
picard::save(
  data      = table13_boot,
  file_path = dir_d5,
  file_name = glue::glue("D5_{cfg$output$table13_name}_boot.{cfg$output$ext}")
)

## Cleanup ---
rm(
  fup_datasets, weight_datasets,
  outcome_analysis_types,
  outcome_parameter_lookup,
  D5_CohortAnalyticLookup_list,
  D5_CohortAnalyticLookup_list_pooled,
  D5_CohortAnalyticLookup,
  table8, table9, table13,
  cfg
)
gc()

logger::log_info("[Cohort Analytic Lookup] - SUCCEED")

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}

logger::log_info("End of the outcome_analysis_lookup script.")
