# ----------------------------
# SET UP ENVIRONMENT
# ----------------------------
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("create_male_baseline_covariates")
  lm$start_capturing_prints()
}

## Config loading ----
config_project <- picard::load_config("configuration/config_project.yaml")
config_values <- picard::load_config("configuration/config_values.yaml")
create_anchored_variables <- config_project$create_anchored_variables

# Path to anchored variables Hive
anchor_hive_dir <- create_anchored_variables$output$anchoring_dir_male

## Audit setup ---
picard::audit_start(
  file_name = "create_male_baseline_covariates",
  deap_name = config_project$DEAP_configuration$name
)

logger::log_info("Starting: extracting male baseline covariates")

# ----------------------------
# LOAD METADATA
# ----------------------------

anchoring_window_metadata <- picard::load(
  file_path = create_anchored_variables$input$metadata_dir,
  file_name = create_anchored_variables$input$metadata_file
)

# ----------------------------
# EXTRACT AND SAVE COVARIATES
# ----------------------------

logger::log_info(paste0("Extracting male baseline covariates"))

d4_study_cohort <- data.table::as.data.table(picard::load(
  file_path = create_anchored_variables$input$cohort_dir,
  file_name = create_anchored_variables$input$cohort_file
))


# CHECK (remove in final version)
anchoring_window_metadata[, is_expected_missing := FALSE]

covariates <- anchoR::get_anchor_result(
  metadata = anchoring_window_metadata[cohort == "males" & covariate == TRUE],
  anchor_hive_path = anchor_hive_dir,
  population = d4_study_cohort,
  impute_missing = TRUE,
  result_shape = "wide"
)

# Remove any variables with "date_" prefix
covariates <- covariates[, !grepl("^date_", names(covariates)), with = FALSE]

# Remove any "value_" prefix from variable names
data.table::setnames(covariates, old = names(covariates), new = sub("^value_", "", names(covariates)))

# Add age-group to covariates dataset
logger::log_info("Calculating age and age categories for baseline covariates")
spells <- unique(picard::load(
  file_path = config_project$outputs$dir_d3,
  file_name = "D3_SPELLS.parquet"
)[, .(person_id, birth_date)])
covariates <- merge(covariates, spells, by = "person_id", all.x = TRUE)
covariates[, SV_AGE_FATHER := lubridate::year(T0) - lubridate::year(birth_date) - (format(T0, "%m-%d") < format(birth_date, "%m-%d"))]

# Remove birth_date after calculating age
covariates[, birth_date := NULL]

# choose concept_ranges source
concept_ranges <- data.table::fread(file.path("transformations/common_configuration/RWE-BRIDGE/concept_ranges.csv"))[concept_id %in% "PP_AGE_CAT"]
data.table::setDT(concept_ranges)

# Add age category using the concept_ranges table
covariates <- covariates[
  concept_ranges,
  on = .(
    SV_AGE_FATHER >= lower_range,
    SV_AGE_FATHER < upper_range
  ),
  SV_AGE_FATHER_CAT := i.description
  # SV_AGE_FATHER_CAT := i.new_value
]

# Add calendar year
covariates[, SV_CALENDAR_YEAR := lubridate::year(T0)]

# Add calendar quarter from T0 to covariates dataset
# covariates[, CALENDAR_QUARTER := lubridate::quarter(d4_study_cohort$T0, with_year = TRUE)]
covariates[, SV_CALENDAR_QUARTER := paste0(lubridate::year(T0), "_", lubridate::quarter(T0))]

# Add calendar time in months between January 1 2010 and T0 to covariates dataset
covariates[, SV_CALENDAR_TIME_INT := as.numeric(T0 - lubridate::ymd("2010-01-01")) %/% 30.44]

# Make sure NA in SV_ASM_PREVIOUS is interpreted as ´NONE'
covariates[, SV_ASM_PREVIOUS := ifelse(is.na(SV_ASM_PREVIOUS), "NONE", SV_ASM_PREVIOUS)]

# Remove SV_CALENDAR_TIME
suppressWarnings(covariates[, SV_CALENDAR_TIME := NULL])

# Save to disk
picard::save(
  data = covariates,
  file_path = create_anchored_variables$output$dir,
  file_name = create_anchored_variables$output$baseline_cov_file
)

rm(d4_study_cohort, covariates)
gc()
logger::log_info(paste0("Finished extracting male baseline covariates "))


logger::log_info("Male baseline covariates extraction completed")
picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
