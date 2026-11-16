################################################################
# combine_weights ---
# Aim:
# Combine weights for the study cohort.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohort_IPTW.parquet
# - data/D4_analytic_datasets/D4_StudyCohort_IPSMW.parquet
# - data/D4_analytic_datasets/D4_StudyCohort_IPTW_Mother.parquet
# - data/D4_analytic_datasets/D4_StudyCohort_IPTW_MotherFather.parquet
# Output: ---
# - data/D4_analytic_datasets/D4_StudyCohort_CombinedWeights.parquet
################################################################

# Initial setup ---
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("combine_weights.R")
  lm$start_capturing_prints()
}

# Config loading ---
picard::load_config()
combine_config <- config_project$combine_weights
dir_d4 <- config_project$combine_weights$input$dir_d4

picard::audit_start(
  file_name = "combine_weights",
  deap_name = config_project$DEAP_configuration$name
)

# ---------------------------------------------
# Load and combine father IPTW and IPSMW weights
# ---------------------------------------------

# Load IPTW and IPSMW weights ---
logger::log_info("Loading IPTW and IPSMW weights for the study cohort.")

iptw_weights_mothers <- picard::load(
  file_path = dir_d4,
  file_name = combine_config$input$d4_iptw_mothers
)

ipsmw_weights_males <- picard::load(
  file_path = dir_d4,
  file_name = combine_config$input$d4_ipwsm_male
)

# Combined weights into a single data.table
combined_weights <- data.table::merge.data.table(
  x = iptw_weights_mothers,
  y = ipsmw_weights_males,
  by = c("person_id", "T0", "group"),
  all.x = TRUE,
  all.y = FALSE
)

# Check that combined weights has the same number of rows as iptw_weights_mothers
if (nrow(combined_weights) != nrow(iptw_weights_mothers)) {
  logger::log_warn("The number of rows in combined_weights does not match the number of rows in iptw_weights_mothers. Please check")
}


# Take product between IPTW and IPSMW weights to create a combined weight
logger::log_info("Adding `iptw_ipsmw = raw_iptw * ipsmw_raw`.")
combined_weights[, iptw_ipsmw := raw_iptw * ipsmw_raw]
logger::log_info("Adding `stabilized_iptw_ipsmw = stabilized_iptw * ipsmw_raw`.")
combined_weights[, stabilized_iptw_ipsmw := stabilized_iptw * ipsmw_raw]
logger::log_info("Adding `stabilized_trunc_iptw_ipsmw = stabilized_trunc_iptw * ipsmw_raw`.")
combined_weights[, stabilized_trunc_iptw_ipsmw := stabilized_trunc_iptw * ipsmw_raw]


# Save the output dataset with imputed outcomes
picard::save(
  data = combined_weights,
  file_path = dir_d4,
  file_name = "D4_StudyCohort_CombinedWeights.parquet"
)

rm(ipsmw_weights_males, iptw_weights_mothers, combined_weights)
gc()

picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
