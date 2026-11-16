# ---------------------------------------------------------------
# Step: compute_d4_StudyCohort_IPTW
#
# Input:  D4_StudyCohort_Covariates
#         D4_StudyCohort_Covariates_Mother
#         psmodel_variables.csv
#         psmodel_variables_mother.csv
#
# Output: D4_StudyCohort_IPTW
#         D4_StudyCohort_IPTW_combined_mother_faher
#         D5_PS_Coef.csv
#         D5_PS_Coef_combined_mother_father.csv
#         D5_PS_ModelBuilding.csv
#         D5_PS_ModelBuilding_combined_mother_father.csv
#
# Orchestrator script to generate a propensity score model and compute IPTW.
# ---------------------------------------------------------------

# --- Initial setup of the environment ----
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("compute_d4_StudyCohort_IPTW.R")
  lm$start_capturing_prints()
}

logger::log_info("[compute_d4_StudyCohort_IPTW] - START")

# --- Config loading ---
picard::load_config()

config_compute_iptw <- config_project$compute_d4_StudyCohort_IPTW

# --- Source functions ---
# First function fit_ps_model.R is used to fit the propensity score model and compute the propensity scores
source(file.path(
  'transformations',
  'T4_statistical_analysis',
  'source_code',
  "functions",
  "fit_ps_model.R"
))
# Second function compute_d4_StudyCohort_IPTW_function.R is used to compute the IPTW weights 
source(file.path(
 'transformations',
 'T4_statistical_analysis',
  'source_code',
  "functions",
  "compute_d4_StudyCohort_IPTW_function.R"
))

# --- Read inputs ---


## Test mode
covariates_path <- if (isTRUE(config_compute_iptw$test_mode)) {
  config_compute_iptw$synthetic_data
} else {
  config_compute_iptw$d4_covariates
}

# Load library
library(splines)

logger::log_info(paste( "Reading D4_StudyCohort_Covariates from:",covariates_path))

# Load male covariates and combined covariates
d4_covariates_males <- picard::load(covariates_path)
d4_covariates_combined <- picard::load(config_compute_iptw$d4_covariates_combined)
logger::log_info("Reading Propensity Score metadata males and female")
ps_variables_males <- picard::load(config_compute_iptw$ps_variables, sep = ";")
ps_variables_mother <- picard::load(config_compute_iptw$ps_variables_mother, sep = ";")
ps_variables_combined <- rbind(ps_variables_males, ps_variables_mother)


# --- Create IPTW weights cohort object for males
iptw_cohort_males <- compute_d4_studycohort_iptw(
  d4_covariates = d4_covariates_males,
  ps_variables = ps_variables_males,
  ps_trim_bounds = config_compute_iptw$ps_trim_bounds,
  ps_truncation_bounds = config_compute_iptw$ps_truncation_bounds,
  se_threshold = config_compute_iptw$se_threshold
)

# --- Create IPTW weights cohort objects for combined mother and father cohort

iptw_cohort_combined <- compute_d4_studycohort_iptw(
  d4_covariates = d4_covariates_combined,
  ps_variables = ps_variables_combined,
  ps_trim_bounds = config_compute_iptw$ps_trim_bounds,
  ps_truncation_bounds = config_compute_iptw$ps_truncation_bounds,
  se_threshold = config_compute_iptw$se_threshold
)

if(all(d4_covariates_combined$person_id == d4_covariates_combined$child_id))
  iptw_cohort_combined$D4_StudyCohort_IPTW <- data.table::merge.data.table(
  x = iptw_cohort_combined$D4_StudyCohort_IPTW,
  y = d4_covariates_combined[, .(person_id, father_id, mother_id, child_id, T0, group)], 
  by = c("person_id", "T0", "group"),
  all.x = TRUE,
  all.y = TRUE
)
# Add child id, father id, and mother id to 

# --- Save outputs ---
# D4 (analytic dataset): 
picard::save(
  data = iptw_cohort_males$D4_StudyCohort_IPTW,
  file_path = config_compute_iptw$output_d4,
  file_name = paste0(config_compute_iptw$output_d4_iptw, '.parquet')
)
picard::save(
  data = iptw_cohort_combined$D4_StudyCohort_IPTW,
  file_path = config_compute_iptw$output_d4,
  file_name = paste0(config_compute_iptw$output_d4_iptw, config_compute_iptw$suffix_combined_cohort, '.parquet')
)

# D5 PS coef
picard::save(
  data = iptw_cohort_males$D5_PS_Coef,
  file_path = config_compute_iptw$output_d5,
  file_name = paste0(config_compute_iptw$output_d5_PS_Coef, '.csv')
)

picard::save(
  data = iptw_cohort_combined$D5_PS_Coef,
  file_path = config_compute_iptw$output_d5,
  file_name = paste0(config_compute_iptw$output_d5_PS_Coef, config_compute_iptw$suffix_combined_cohort, '.csv')
)

# D5 PS model building
picard::save(
  data = iptw_cohort_males$D5_PS_ModelBuilding,
  file_path = config_compute_iptw$output_d5,
  file_name = paste0(config_compute_iptw$output_d5_PS_ModelBuilding, '.csv')
)

picard::save(
  data = iptw_cohort_combined$D5_PS_ModelBuilding,
  file_path = config_compute_iptw$output_d5,
  file_name = paste0(config_compute_iptw$output_d5_PS_ModelBuilding, config_compute_iptw$suffix_combined_cohort, '.csv')
)

# Log number of rows in the output datasets
logger::log_info(paste("D4_StudyCohort_IPTW (males):", nrow(iptw_cohort_males$D4_StudyCohort_IPTW), "rows"))
logger::log_info(paste("D4_StudyCohort_IPTW (combined mother and father):", nrow(iptw_cohort_combined$D4_StudyCohort_IPTW), "rows"))

rm(d4_covariates_combined, d4_covariates_males, iptw_cohort_males, iptw_cohort_combined, ps_variables_males, ps_variables_mother, ps_variables_combined)

logger::log_info("[compute_d4_StudyCohort_IPTW] - SUCCEED")

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
