################################################################
# create_sequential_trials_tables ---
# Aim:
# Create Table 2 using D4 Study Cohort Males and D4 Study Cohort Children datasets. This table will be used to describe the sequential trials allocation process.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D3_study_variables/D4_StudyCohort_Males.fst and D4_StudyCohort_Children.fst (to change)
#
# Output: ---
# - data/D5_results/D5_<DEAP>_Sequential_Trials_Table2.csv
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
  lm$start_script("Creating D5 Sequential Trials Table 2")
  lm$start_capturing_prints()
}

## Audit setup ---
if (exists("audit_start")) {
  picard::audit_start(file_name = "create_sequential_trials_tables")
}

logger::log_info("Start of the create_sequential_trials_tables script.")

## Config loading ---

picard::load_config()

## Load functions ---
base::source(file.path("transformations", "T4_statistical_analysis", "source_code", "functions", "fn_sequentialtrials_allocation.R"))

# Load input datasets ---
d4_males_cohort <- picard::load(
  file_path = config_project$create_sequential_trials_table$input$dir_d4,
  file_name = config_project$create_sequential_trials_table$input$file_name_males_cohort)

d4_child_cohort <- picard::load(
  file_path = config_project$create_sequential_trials_table$input$dir_d4,
  file_name = config_project$create_sequential_trials_table$input$file_name_child_cohort)

# Compute attrition table
Table2 <- create_sequential_trials_table2(d4_males_cohort, d4_child_cohort)

# Save Table 2
logger::log_info("Saving Table2.")

picard::save(
  data = Table2,
  file_path = config_project$create_sequential_trials_table$output$dir_d5,
  file_name = config_project$create_sequential_trials_table$output$file_name
)


picard::audit_end()

rm(d4_males_cohort, d4_child_cohort, Table2)
gc()
