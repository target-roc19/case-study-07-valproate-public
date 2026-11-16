# ---------------------------------------------------------------
# Step: compute_ipsmw
#
# Input:
#   D4_StudyCohort_Main(.parquet)
#   D4_StudyCohort_Supplementary(.parquet)
#   D4_StudyCohort_FUP_Main/Supplementary(.parquet)
#   metadata/ipsmw_variables.csv
#
# Output:
#   D4_StudyCohort_IPSMW_Main/Supplementary.parquet
#   D5_PS_Coef_IPSMW_Main/Supplementary.csv
#   D5_PS_ModelBuilding_IPSMW_Main/Supplementary.csv
#   D4_StudyCohort_FUP_Main/Supplementary.parquet (updated with compliant_exposed)
# ---------------------------------------------------------------

if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("compute_ipsmw.R")
  lm$start_capturing_prints()
}

# Load helper utilities used by this orchestration script.
source(file.path(
  "transformations",
  "T4_statistical_analysis",
  "source_code",
  "functions",
  "fit_ps_model.R"
))

source(file.path(
  "transformations",
  "T4_statistical_analysis",
  "source_code",
  "functions",
  "fn_compute_ipsmw.R"
))


# Load project configuration specifying analyses and estimands.
config_project <- picard::load_config("configuration/config_project.yaml")
compute_ipsmw_config <- config_project$compute_ipsmw

## Audit setup ---
picard::audit_start(
  file_name = "compute_ipsmw"
)
logger::log_info("Start of the compute_ipsmw script.")

# IPSMW is estimated for estimand 1 only
input_dir_d4 <- compute_ipsmw_config$input$dir_d4
cohort_file <- compute_ipsmw_config$input$cohort_file
metadata_file <- compute_ipsmw_config$metadata$ipsmw_variables_file
output_dir_d4 <- compute_ipsmw_config$output$dir_d4
output_dir_d5 <- compute_ipsmw_config$output$dir_d5

# Metadata controls model covariate selection and factor handling.
ipsmw_variables <- data.table::fread(metadata_file, sep = ";")

# Load input data for this analysis.
cohort_data <- picard::load(input_dir_d4, cohort_file)


# Core computation: derive compliance, fit model on exposed, predict control
# principal stratum scores, and compute IPSMW.

res <- compute_ipsmw(
    cohort_data = cohort_data,
    ps_variables = ipsmw_variables,
    compliance_col = "conception_within_3_years",
  )

  # Save person-level IPSMW dataset.
picard::save(
    data = res$D4_StudyCohort_IPSMW,
    file_path = output_dir_d4,
    file_name = compute_ipsmw_config$output$ipsmw_cohort_file)
  

  # Save model coefficient summaries.
  picard::save(
    data = res$D5_PS_Coef_IPSMW,
    file_path = output_dir_d5,
    file_name = "D5_PS_Coef_IPSMW.csv")
  

  # Save variable screening/model-building diagnostics.
  picard::save(
    data = res$D5_PS_ModelBuilding_IPSMW,
    file_path = output_dir_d5,
    file_name = "D5_PS_ModelBuilding_IPSMW.csv")
  

  logger::log_info(paste(
    "Finished | IPSMW rows:",
    nrow(res$D4_StudyCohort_IPSMW)
  ))


# Clean the environment
objects_to_remove <- c(
  "cohort_data", "res",
  "ipsmw_variables"
)

rm(list = intersect(objects_to_remove, ls()))
gc()

# Close logs
picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}

logger::log_info("End of the compute_ipsmw script.")
