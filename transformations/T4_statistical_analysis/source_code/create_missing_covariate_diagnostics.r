################################################################
# create_missing_covariate_diagnostics ---
# Aim:
# Create Table 11 (missing covariate diagnostics) using D3_Eligibility
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D3_study_variables/D3_Eligibility.fst
#
# Output: ---
# - data/D5_results/D5_Missing_Covariate_Diagnostics.csv
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
  lm$start_script("Creating D5 Missing Covariate Diagnostics")
  lm$start_capturing_prints()
}

## Audit setup ---
if (exists("audit_start")) {
  picard::audit_start(file_name = "create_missing_covariate_diagnostics")
}

logger::log_info("Start of the create_missing_covariate_diagnostics script.")

## Config loading ---

picard::load_config()

base::source(file.path("transformations", "T4_statistical_analysis", "source_code", "functions", "fn_missing_covariates_diagnostics.R"))

## Load functions ---

# Load input datasets ---
d4_cohort <- picard::load(
  file_path = config_project$create_missing_covariate_diagnostics$input$cohort_dir,
  file_name = config_project$create_missing_covariate_diagnostics$input$cohort_file
)

if (config_project$create_missing_covariate_diagnostics$test_mode == TRUE) {
  logger::log_warn("Testing mode: Randomly assigning eligibility for exposed and control groups, and generating random BMI values with missingness")
  # Randomly set 50% of exposed as TRUE, the rest as FALSE
  set.seed(123) # for reproducibility
  d4_cohort[, group := sample(c("EXPOSED", "CONTROL"), .N, replace = TRUE)]

  # Generate BMI values with some missingness
  d4_cohort <- d4_cohort[, SV_BMI := rnorm(n = .N, mean = 29, sd = 2)]
  # Introduce 30% missingness
  d4_cohort[sample(.N, .N * 0.3), SV_BMI := NA]
}

# Make sure SV_BMI is numeric
d4_cohort[, SV_BMI := as.numeric(SV_BMI)]

bmi_table <- compute_bmi_diagnostics(d4_cohort, digits = 1)
# Save Table 1
logger::log_info("Saving BMI diagnostics table.")

picard::save(
  data = bmi_table,
  file_path = config_project$create_missing_covariate_diagnostics$output$dir_d5,
  file_name = config_project$create_missing_covariate_diagnostics$output$file_name
)


rm(d4_cohort, bmi_table)
gc()
