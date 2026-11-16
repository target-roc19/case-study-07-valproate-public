################################################################
# impute_bw_outcomes ---
# Aim:
# Create best/worst-case follow-up data for estimand 1 by assuming
# event_estimand1 values for records with non-administrative censoring.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohortFup_<Main>.RDS
# - data/D4_analytic_datasets/D4_StudyCohortCovariates_<Main>.RDS
#
# Output: ---
# - data/D4_analytic_datasets/D4_StudyCohort_FUP_BW_<Main>_BW.RDS
################################################################

# Initial setup ---
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("impute_bw_outcomes.R")
  lm$start_capturing_prints()
}

# Config loading ---
picard::load_config()
imp_cfg <- config_project$impute_outcome
dir_d4 <- config_project$outputs$dir_d4

picard::audit_start(
  file_name = "impute_bw_outcomes",
  deap_name = config_project$DEAP_configuration$name
)

logger::log_info(glue::glue("Processing study cohort child follow up object"))

fup <- picard::load(
  file_path = dir_d4,
  file_name = glue::glue("{imp_cfg$input$fup_file}.{imp_cfg$input$ext}")
)
fup_keep <- c("person_id", "T0", "trial_id", "father_id", "child_id", "group", "event_estimand1", "outcome_missing_estimand1", "general_end_fup_estimand1")

bw_dt <- fup[, ..fup_keep]

bw_dt[, event_estimand1_observed := as.integer(event_estimand1)]

impute_index <- which(bw_dt$outcome_missing_estimand1 == TRUE)
logger::log_info(glue::glue("missing outcome rows for best/worst scenarios: {length(impute_index)}"))

if (length(impute_index) == 0L) {
  logger::log_error("No missing outcome rows found. Cannot create scenarios.")
  stop()
}

# Create best best scenario (event_estimand1 = 0 for both exposed and control)
bb <- data.table::copy(bw_dt)
bb[impute_index, event_estimand1 := 0L]
bb[, bw_scenario := "bb"]
bb[, bw_id := 3] # As table 13 in table shell

# Create worst scenario (event_estimand1 = 1)
ww <- data.table::copy(bw_dt)
ww[impute_index, event_estimand1 := 1L]
ww[, bw_scenario := "ww"]
ww[, bw_id := 4] # As table 13 in table shell

# best exposed and worst control scenario (event_estimand1 = 0 for exposed, 1 for control)
impute_exposed_index <- which(bw_dt$outcome_missing_estimand1 == TRUE & bw_dt$group == "EXPOSED")
impute_control_index <- which(bw_dt$outcome_missing_estimand1 == TRUE & bw_dt$group == "CONTROL")
bw <- data.table::copy(bw_dt)
bw[impute_exposed_index, event_estimand1 := 0L]
bw[impute_control_index, event_estimand1 := 1L]
bw[, bw_scenario := "bw"]
bw[, bw_id := 1] # As table 13 in table shell

# worst exposed and best control scenario (event_estimand1 = 1 for exposed, 0 for control)
wb <- data.table::copy(bw_dt)
wb[impute_exposed_index, event_estimand1 := 1L]
wb[impute_control_index, event_estimand1 := 0L]
wb[, bw_scenario := "wb"]
wb[, bw_id := 2] # As table 13 in table shell

# Combine both scenarios
output_dt <- data.table::rbindlist(list(bb, bw, wb, ww), use.names = TRUE)

# We can skip this since we use a fixed offset of log(8 years)
output_dt[outcome_missing_estimand1 == TRUE & event_estimand1 == 1L, fup_d_estimand1 := general_end_fup_estimand1]
output_dt[, fup_length_days_estimand1 := as.numeric(difftime(fup_d_estimand1, T0, units = "days") + 1)]
output_dt[, fup_length_months_estimand1 := fup_length_days_estimand1 / config_values$month_length]

picard::save(
  data = output_dt,
  file_path = dir_d4,
  file_name = glue::glue("{imp_cfg$output$fup_bw_file}.{imp_cfg$output$ext}")
)

rm(fup, bw_dt, bb, bw, wb, ww, output_dt)
gc()

picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
