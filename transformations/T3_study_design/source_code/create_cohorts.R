# ---------------------------------------------------------------
# Step: create_d4_studycohort
#
# Input:  D3_ELIGIBILITY (data/D3_study_variables/)
#         D3_FatherChild (data/D3_study_variables/)
# Output: D4_StudyCohort (data/D4_analytic_datasets/)
#
# Selects eligible exposed/control individuals from D3_ELIGIBILITY
# and creates the study cohort with treatment group assignment.
# ---------------------------------------------------------------
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("create_cohorts")
  lm$start_capturing_prints()
}

logger::log_info("Starting: create_d4_studycohort")

# ----------------------------
# Load configuration files
# ----------------------------

## Config loading from yaml files
config_project <- picard::load_config("configuration/config_project.yaml")
config_T3 <- picard::load_config("configuration/config_T3.yaml")

## Audit setup ---
picard::audit_start(
  file_name = "create_cohorts",
  deap_name = config_project$DEAP_configuration$name
)

# --- Source function ---
source(file.path(config_T3$T3$root, config_T3$T3$functions, "create_d4_cohort_function.R"))
source(file.path(config_T3$T3$root, config_T3$T3$functions, "add_child_to_d4_studycohort_function.R"))
source(file.path(config_T3$T3$root, config_T3$T3$functions, "create_d4_child_cohort.R"))


# ----------------------------
# Load data
# ----------------------------

# --- Read input ---
logger::log_info("Reading D3_ELIGIBILITY")

# Read input data (does not exist yet, will be created in the previous step)
d3_eligibility <- picard::load(
  file_path = config_project$create_cohort$input$dir_d3,
  file_name = config_project$create_cohort$input$input_file_name
)

# Convert variables from POSIXct to Date format
variable_types <- lapply(d3_eligibility, class)
for (var_name in names(variable_types)) {
  if ("POSIXct" %in% variable_types[[var_name]]) {
    logger::log_info(paste("Converting variable", var_name, "from POSIXct to Date format"))
    d3_eligibility[, (var_name) := as.Date(get(var_name))]
  }
}

# For testing we will change cases into eligible cases
if (config_project$create_cohort$test_mode == TRUE) {
  logger::log_warn("Testing mode: Randomly assigning eligibility for exposed and control groups")
  # Randomly set 50% of exposed as TRUE, the rest as FALSE
  set.seed(123) # for reproducibility
  d3_eligibility[, eligible_exposed := sample(c(TRUE, FALSE), .N, replace = TRUE)]
  # if an individual is exposed they cannot be control, so change to TRUE all controls that are not exposed
  d3_eligibility[, eligible_control := ifelse(eligible_exposed == FALSE, TRUE, FALSE)]
}

# ----------------------------
# Create Study Cohort
# ----------------------------

# Set to TRUE if you want to perform bootstrapping, otherwise set to FALSE
bootstrapping <- config_project$create_cohort$bootstrapping

if (bootstrapping) {
  logger::log_info("Bootstrapping enabled: creating bootstrap samples")
  n_bootstrap_samples <- config_project$create_cohort$n_bootstrap_samples
  bootstrap_results <- list()

  for (i in 1:n_bootstrap_samples) {
    logger::log_info(paste("Creating bootstrap sample", i))
    bootstrap_results[[i]] <- create_d4_studycohort(d3_eligibility, bootstrap = bootstrapping, current.boot.id = i)
  }
  ## TO-DO: Add code to combine bootstrap samples and/or results
} else {
  logger::log_info("Bootstrapping disabled: creating study cohort without bootstrapping")
  # --- Create D4 study cohort ---
  d4_studycohort <- create_d4_studycohort(d3_eligibility)
}

logger::log_info(paste("D4_StudyCohort:", nrow(d4_studycohort), "rows"))

# ---------------------------------------------------------------
# Add additional variables to D4 study cohort (male-trial units)
# ---------------------------------------------------------------

# Load D3_FatherChild
d3_father_child <- picard::load(
  file_path = config_project$create_cohort$input$dir_d3,
  file_name = "D3_FatherChild.parquet"
)

# Add child-related variables to D4 study cohort
# This function will add the following variables to the D4 study cohort:
# - earliest_conception_date: The earliest estimated conception date for each person_id.
# - first_date_of_birth: The first date of birth for each person_id.
# - conception_within_3_years: A boolean variable indicating whether the earliest conception date is within 3 years after T0.
# - livebirth_within_3_years_9_months: A boolean variable indicating whether the first date of birth is within 3.75 years after T0 and the earliest conception date is within 3 years after T0.
d4_studycohort <- add_child_to_d4_studycohort(d4_studycohort, d3_father_child)

# check uniqueness of T0 per cohort
dup_start <- d4_studycohort[, .N, by = .(person_id, T0)][N > 1]
if( nrow(dup_start) > 0) {
  logger::log_error(
    glue::glue(
      "There are {nrow(dup_start)} multiple entries at same person/T0 in study cohort "
    )
  )
}
# --- Save output ---
picard::save(
  data = d4_studycohort,
  file_path = config_project$create_cohort$output$dir_d4,
  file_name = config_project$create_cohort$output$output_file_name # parquet file
)

# ----------------------------
# Create child cohort: D4_StudyCohort_Child (children-trial units)
# ----------------------------

# This function creates the child cohort (D4_StudyCohort_Child) by merging the
# D4 study cohort with the D3_FatherChild dataset. The child cohort includes only the offspring 
# of fathers with a conception within 3 years after T0.
# It also includes the mother id
d4_studycohort_child <- create_d4_child_cohort(d4_studycohort, d3_father_child)

logger::log_info(paste("D4_StudyCohortChild:", nrow(d4_studycohort_child), "rows"))
# Add logs for number of unique father_ids, children_ids and mother_ids
logger::log_info(paste("Number of unique father_ids in D4_StudyCohortChild:", 
                    length(unique(d4_studycohort_child$father_id))))

logger::log_info(paste("Number of unique children_ids in D4_StudyCohortChild:", 
                    length(unique(d4_studycohort_child$child_id))))

logger::log_info(paste("Number of unique mother_ids in D4_StudyCohortChild:", 
                    length(unique(d4_studycohort_child$mother_id))))


logger::log_info(paste("D4_StudyCohortChild:", nrow(d4_studycohort_child), "rows"))

# --- Save child cohort output ---
picard::save(
  data = d4_studycohort_child,
  file_path = config_project$create_cohort$output$dir_d4,
  file_name = config_project$create_cohort$output$output_file_name_child # parquet file
)

rm(d3_eligibility, d4_studycohort, d4_studycohort_child, variable_types, d3_father_child)
logger::log_info("Completed: create_d4_studycohort")

picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
