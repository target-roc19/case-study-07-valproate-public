################################################################
# create_follow_up_table ---
# Aim:
# Create follow-up, intercurrent events and censoring reasons table
# (Tables 5.1.x and 5.2.x) for the main matched cohort across
# Estimand 1 and Estimand 2.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohortFup.parquet (father follow-up data)
# - data/D4_analytic_datasets/D4_StudyCohortFupChild.parquet (child follow-up data)
# - transformations/T4_statistical_analysis/metadata/fup_table_spec.csv
# Output: ---
# - data/D5_results/{deap_name}_Table5.1.x_Estimand{1,2}.csv (father follow-up & IE table)
# - data/D5_results/{deap_name}_Table5.2.x_Estimand{1,2}.csv (child follow-up & IE table)
################################################################

# ----------------------------
# SET UP ENVIRONMENT
# ----------------------------
if (!base::exists("lm", inherits = TRUE) ||
  !base::inherits(lm, "LoggerManager")) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("create_fup_tables.R")
  lm$start_capturing_prints()
}

picard::load_config()

logger::log_info("Starting: Table 5.1.x and 5.2.x follow-up and outcomes tables")

# ----------------------------
# LOAD CONFIG
# ----------------------------
logger::log_info("Reading config for follow-up tables")

config_project <- picard::load_config("configuration/config_project.yaml")
deap_name <- config_project$DEAP_configuration$name

# Extract config parameters
dir_d4 <- config_project$output$dir_d4
dir_d5 <- config_project$output$dir_d5

# load the functions needed
source("transformations/T4_statistical_analysis/source_code/functions/fn_fup_table.R")
source("transformations/T3_study_design/source_code/functions/follow_up_functions.R")

# ----------------------------
# LOAD TABLE SPEC METADATA
# ----------------------------
spec_path <- "transformations/T4_statistical_analysis/metadata/fup_table_spec.csv"
if (!file.exists(spec_path)) {
  stop("Follow-up table metadata not found: ", spec_path)
}

fup_table_spec <- data.table::fread(spec_path, na.strings = c("", "NA"))
required_cols <- c(
  "object", "estimand", "section", "row_order", "variable", "label"
)
if (!all(required_cols %in% names(fup_table_spec))) {
  stop(
    "Follow-up table metadata is missing required columns: ",
    paste(setdiff(required_cols, names(fup_table_spec)), collapse = ", ")
  )
}

# ----------------------------
# CREATE TABLES FOR EACH ESTIMAND
# ----------------------------
for (i_est in c(1, 2)) {
  # ----------------------------
  # LOAD DATA
  # ----------------------------
  logger::log_info("Loading father and child follow-up data")

  file_path_father <- file.path(dir_d4, "D4_StudyCohortFup.parquet")
  d4_fup_father <- picard::load(file_path_father)

  file_path_child <- file.path(dir_d4, "D4_StudyCohortFupChild.parquet")
  d4_fup_child <- picard::load(file_path_child)

  logger::log_info(paste("Father rows loaded:", nrow(d4_fup_father)))
  logger::log_info(paste("Child rows loaded:", nrow(d4_fup_child)))

  estimand_label <- paste0("Estimand ", i_est)

  logger::log_info(paste0(
    "Creating Table 5.1.", i_est, " and 5.2.", i_est, " for ", estimand_label
  ))

  # # test
  # d4_fup_father[person_id == "#ID-000001710#" & trial_id == 22, "treatment_stop_3_months_or_less"] <- as.Date("2011-10-29")

  #------------------------------
  # Father follow-up table
  #------------------------------
  logger::log_info(paste0("Creating Table 5.1.", i_est, " for ", estimand_label))

  father_ie_rows <- fup_table_spec[
    object == "d4_fup_father" & estimand == i_est & section == "ie"
  ][order(row_order)]
  father_cens_rows <- fup_table_spec[
    object == "d4_fup_father" & estimand == i_est & section == "cens"
  ][order(row_order)]

  if (nrow(father_ie_rows) == 0 || nrow(father_cens_rows) == 0) {
    stop("Missing father IE/censoring spec rows for estimand ", i_est)
  }

  # For each of the ie_vars, set their value to NA if they occur after the
  # follow-up end date (fup_end_date_est1 or fup_end_date_est2)
  for (ie_var in father_ie_rows$variable) {
    fup_end_date_var <- paste0("general_end_fup_estimand", i_est)
    d4_fup_father[get(ie_var) > get(fup_end_date_var), (ie_var) := NA]
  }

  fup_table_father <- build_fup_table(
    d = d4_fup_father,
    estimand = i_est,
    estimand_label = estimand_label,
    ie_vars = father_ie_rows$variable,
    ie_labels = father_ie_rows$label,
    cens_vars = as.list(father_cens_rows$variable),
    cens_labels = father_cens_rows$label
  )

  output_name_5_1 <- paste0(
    "D5_Table5.1.",
    i_est,
    "_Estimand",
    i_est,
    "_simple.csv"
  )
  picard::save(
    data = fup_table_father,
    file_path = dir_d5,
    file_name = output_name_5_1
  )

  logger::log_info(paste0("Saved Table 5.1.", i_est, ": ", output_name_5_1))

  #------------------------------
  # Child follow-up table
  #------------------------------
  logger::log_info(paste0("Creating Table 5.2.", i_est, " for ", estimand_label))

  child_ie_rows <- fup_table_spec[
    object == "d4_fup_child" & estimand == i_est & section == "ie"
  ][order(row_order)]
  child_cens_rows <- fup_table_spec[
    object == "d4_fup_child" & estimand == i_est & section == "cens"
  ][order(row_order)]

  if (nrow(child_cens_rows) == 0) {
    stop("Missing child censoring spec rows for estimand ", i_est)
  }

  # For each of the ie_vars, set their value to NA if they occur after the
  # follow-up end date (fup_end_date_est1 or fup_end_date_est2)
  for (ie_var in child_ie_rows$variable) {
    fup_end_date_var <- paste0("general_end_fup_estimand", i_est)
    d4_fup_child[get(ie_var) > get(fup_end_date_var), (ie_var) := NA]
  }

  fup_table_child <- build_fup_table(
    d = d4_fup_child,
    estimand = i_est,
    estimand_label = estimand_label,
    ie_vars = child_ie_rows$variable,
    ie_labels = child_ie_rows$label,
    cens_vars = as.list(child_cens_rows$variable),
    cens_labels = child_cens_rows$label,
    include_ie = FALSE
  )

  output_name_5_2 <- paste0(
    "D5_Table5.2.",
    i_est,
    "_Estimand",
    i_est,
    "_simple.csv"
  )
  picard::save(
    data = fup_table_child,
    file_path = dir_d5,
    file_name = output_name_5_2
  )

  logger::log_info(paste0("Saved Table 5.2.", i_est, ": ", output_name_5_2))

  #------------------------------
  # Table 5.3.x: Outcomes and Missing Data
  #------------------------------
  logger::log_info(paste0("Creating Table 5.3.", i_est, " for ", estimand_label))

  table_5_3 <- create_outcome_fup_table(
    d_child = d4_fup_child,
    estimand = i_est,
    n_dec = 2
  )

  output_name_5_3 <- paste0(
    "D5_Table5.3.",
    i_est,
    "_Estimand",
    i_est,
    ".csv"
  )

  picard::save(
    data = table_5_3,
    file_path = dir_d5,
    file_name = output_name_5_3
  )

  logger::log_info(paste0("Saved Table 5.3.", i_est, ": ", output_name_5_3))

  rm(output_name_5_1, output_name_5_2, output_name_5_3, table_5_3, fup_table_father, fup_table_child)
  gc()
}

# ----------------------------
# CLEAN ENVIRONMENT
# ----------------------------
logger::log_info("Completed: follow-up and outcomes tables for all estimands")

rm(d4_fup_father, d4_fup_child, fup_table_spec)
gc()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
