################################################################
# create_imputation_diagnostics ---
# Aim:
# Create a table of imputation diagnostics for the imputed outcomes for estimand 1.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohortFupChildMI.parquet (child follow-up data)
# Output: ---
# - data/D5_results/D5_Table12.csv (imputation diagnostics table)
################################################################

# Initial setup ---
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("create_imputation_diagnostics.R")
  lm$start_capturing_prints()
}

# Config loading ---
picard::load_config()
imp_cfg <- config_project$impute_outcome
dir_d4 <- config_project$outputs$dir_d4
dir_d5 <- config_project$outputs$dir_d5

picard::audit_start(
  file_name = "create_imputation_diagnostics",
  deap_name = config_project$DEAP_configuration$name
)

# Load required functions ---
source("transformations/T3_study_design/source_code/functions/impute_estimand_function.R")
source("transformations/T4_statistical_analysis/source_code/functions/fn_imputation_diagnostics.R")

logger::log_info(glue::glue("Processing study cohort child follow up object"))

# Load data ---
# Load imputed follow-up data
logger::log_info("Loading imputed follow-up data.")
imp_estimand1 <- picard::load(
  file_path = dir_d4,
  file_name = glue::glue("{imp_cfg$output$fup_mi_file}.{imp_cfg$output$ext}")
)

# event_estimand1 to integer
imp_estimand1[, event_estimand1 := as.integer(as.character(event_estimand1))]

# Create outcome imputation diagnostics table ---
logger::log_info("Creating imputation diagnostics table.")
imp_table_estimand1 <- fn_imputation_diagnostics(
  data = imp_estimand1,
  missing_col = "outcome_missing_estimand1",
  observed_col = "event_estimand1_observed",
  imputed_col = "event_estimand1",
  impute_id = "imputation_id",
  group_col = "group",
  exposed_val = "EXPOSED",
  control_val = "CONTROL"
)

# Save the output dataset with imputed outcomes
picard::save(
  data = imp_table_estimand1,
  file_path = dir_d5,
  file_name = glue::glue("{imp_cfg$table_output$table_name}.{imp_cfg$table_output$ext}")
)

rm(imp_estimand1, imp_table_estimand1)
gc()

picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
