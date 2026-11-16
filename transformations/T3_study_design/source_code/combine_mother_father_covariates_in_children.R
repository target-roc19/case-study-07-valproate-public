# ---------------------------------------------------------------
#
# Input:  D4_StudyCohort_Covariates
#         D4_StudyCohort_Covariates_Mother

# Output: combined covariates for mother and father in children
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
  lm$start_script("combine_mother_father_covariates_in_children.R")
  lm$start_capturing_prints()
}

logger::log_info("[combine_mother_father_covariates_in_children] - START")

# --- Config loading ---
picard::load_config()

config_combine_covariates <- config_project$combine_mother_father_covariates_in_children

# Load covariates and merge father and mother covariates
d4_covariates_males <- picard::load(config_combine_covariates$input$d4_covariates)
d4_covariates_mothers <- picard::load(config_combine_covariates$input$d4_covariates_mother)

# Compute d4_covariates_fathers

d4_covariates_fathers <- d4_covariates_males[conception_within_3_years == TRUE]

if(!identical(d4_covariates_mothers$person_id, d4_covariates_mothers$mother_id)){
  logger::log_error("The person_id column in d4_covariates_mothers does not match the mother_id column.")
} else {
  d4_covariates_mothers[, person_id := NULL]  # Remove person_id column to avoid confusion
}

if(nrow(d4_covariates_fathers) != nrow(d4_covariates_mothers)){
  logger::log_warn(paste("Number of rows in d4_covariates_fathers (", nrow(d4_covariates_fathers), ") 
  does not match number of rows in d4_covariates_mothers (", nrow(d4_covariates_mothers), ")."))
}

logger::log_info(paste('Column names present in both covariate mothers and covariate fathers:',
                       paste(intersect(colnames(d4_covariates_mothers), colnames(d4_covariates_fathers)), collapse = ", ")))


# Rename person_id to father_id in d4_covariates_fathers to avoid confusion
data.table::setnames(d4_covariates_fathers, "person_id", "father_id")

# Combine father and mother covariates into object
d4_covariates_combined <- data.table::merge.data.table(
  d4_covariates_fathers,
  d4_covariates_mothers,
  by = c("father_id", "T0", "trial_id", "group")
)

# Log number of rows
logger::log_info(paste("Number of rows in combined covariates:", nrow(d4_covariates_combined)))

if(nrow(d4_covariates_combined) != nrow(d4_covariates_mothers)){
  logger::log_error(paste("Number of rows in d4_covariates_combined (", nrow(d4_covariates_combined), ") 
  does not match number of rows in 
  d4_covariates_mothers (", nrow(d4_covariates_mothers), ")."))
}


# Add a person_id column to d4_covariates_combined to be used in compute_d4_studycohort_iptw
d4_covariates_combined[, person_id := child_id]

# Save combined covariates 
picard::save(
  data = d4_covariates_combined,
  file_path = config_combine_covariates$output$dir_d4,
  file_name = config_combine_covariates$output$file_name
)

# clean up environment
rm(d4_covariates_males, d4_covariates_fathers, d4_covariates_mothers, d4_covariates_combined)

logger::log_info("[combine_mother_father_covariates_in_children] - SUCCEED")

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
