################################################################
# create_eligibility ---
# Aim:
# Build D3_ELIGIBILITY from D3_MULTIVARIATE_EPISODES and D3_FatherChild by:
# 1) computing eligibility criteria (in_study_period, in_eligible_pop),
# 2) deriving exposure groups (receives_exposure, receives_control; excluding other ASM medication)
# 3) combining to get eligible_exposed and eligible_control flags,
# 4) computing fatherhood outcomes (father within 3 months, n pregnancies...) from D3_FatherChild data.
#
# Input files: ---
# - configuration/config_values.yaml
# - data/D3_study_variables/D3_MULTIVARIATE_EPISODES.csv
# - data/D3_study_variables/D3_FatherChild.csv
#
# Output: ---
# - data/D3_study_variables/D3_ELIGIBILITY.csv
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
  lm$start_script("create_eligibility.R")
  lm$start_capturing_prints()
}

## Audit setup ---
picard::audit_start(file_name = "create_eligibility")


logger::log_info("Start of the create_eligibility script.")

## Config loading ---


picard::load_config()

## Load functions ---
base::source(file.path("transformations", "T3_study_design", "source_code", "functions", "create_eligibility_function.R"))

logger::log_info("Load data.")
# Load input datasets ---
d3_multivariate_episodes <- picard::load(
  file_path = config_project$create_eligibility$input$dir,
  file_name = config_project$create_eligibility$input$multi_file_name
)

d3_father_child <- picard::load(
  file_path = config_project$create_eligibility$input$dir,
  file_name = config_project$create_eligibility$input$father_child_file_name
)


missing_conception_date <- d3_father_child[is.na(estimated_conception_date), .N]

logger::log_warn(paste0("Number of records in D3_FatherChild with missing estimated conception date: ", missing_conception_date, "."))

logger::log_info("Renaming start_episode and end_episode to start and end for compatibility with eligibility function and codebooks")

d3_multivariate_episodes[, 
  start := start_episode
]
d3_multivariate_episodes[,
  end := end_episode
]


logger::log_info("Computing D3_ELIGIBILITY.")
# Compute eligibility columns ---
D3_ELIGIBILITY <- compute_eligibility(d3_multivariate_episodes, d3_father_child, config_values)

# Count how many children within 3y9m there are
children_within_3y <- D3_ELIGIBILITY[conception_within_3_years == TRUE, data.table::uniqueN(person_id)]
children_after_episode <- D3_ELIGIBILITY[!is.na(first_date_of_birth), data.table::uniqueN(person_id)]

logger::log_info(paste0("Number of unique fathers with a live birth with estimated conception date within 3 years after episode end: ", children_within_3y, "."))
logger::log_info(paste0("Number of unique fathers with a live birth after episode end (regardless of timing): ", children_after_episode, "."))


# Save D3_ELIGIBILITY ---
logger::log_info("Saving D3_ELIGIBILITY.")

picard::save(
  data = D3_ELIGIBILITY,
  file_path = config_project$create_eligibility$output$dir,
  file_name = config_project$create_eligibility$output$file_name
)

picard::audit_end()

rm(d3_multivariate_episodes, d3_father_child, D3_ELIGIBILITY)
gc()
