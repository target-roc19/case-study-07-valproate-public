################################################################
# create_attrition_tables ---
# Aim:
# Create Table 1(a) using D3_Eligibility
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D3_study_variables/D3_Eligibility.fst
#
# Output: ---
# - data/D5_results/D5_<DEAP>_Attrition_Table1.csv
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
  lm$start_script("Creating D5 Attrition Table 1")
  lm$start_capturing_prints()
}

## Audit setup ---
if (exists("audit_start")) {
  picard::audit_start(file_name = "create_attrition_tables")
}

logger::log_info("Start of the create_attrition_tables script.")

## Config loading ---

picard::load_config()

## Load functions ---
base::source(file.path("transformations", "T4_statistical_analysis", "source_code", "functions", "fn_attrition_table.R"))

# Load input datasets ---
d3_eligibility <- picard::load(
  file_path = config_project$create_attrition_tables$input$dir_d3,
  file_name = config_project$create_attrition_tables$input$input_file_name
)


# Compute attrition table
results <- create_attrition_table(d3_eligibility)

Table1 <- results$table_1a

# Log number of overlapping IDs
logger::log_info(paste0("Number of individuals who contribute to both exposure and control at different points: ", 
results$total_overlap))

# Save Table 1
logger::log_info("Saving Table1.")

picard::save(
  data = Table1,
  file_path = config_project$create_attrition_tables$output$dir_d5,
  file_name = config_project$create_attrition_tables$output$file_name
)


picard::audit_end()

rm(d3_eligibility, Table1)
gc()
