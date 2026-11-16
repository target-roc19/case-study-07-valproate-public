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
  lm$start_script("create_mother_baseline_covariates")
  lm$start_capturing_prints()
}

## Config loading ----
config_project <- picard::load_config("configuration/config_project.yaml")
config_values <- picard::load_config("configuration/config_values.yaml")
create_anchored_variables <- config_project$create_anchored_variables

# Path to anchored variables Hive
anchor_hive_dir <- create_anchored_variables$output$anchoring_dir_mother

## Audit setup ---
picard::audit_start(
  file_name = "create_mother_baseline_covariates",
  deap_name = config_project$DEAP_configuration$name
)

logger::log_info("Starting: extracting mother baseline covariates")

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

logger::log_info(paste0("Extracting mother baseline covariates"))

d4_children_study_cohort <- data.table::as.data.table(picard::load(
  file_path = create_anchored_variables$input$cohort_dir,
  file_name = create_anchored_variables$input$cohort_file_child # the mother id can be found in the children-trial cohort 
))


# In test mode, mother DOB-anchored variables were written with shifted T0
# (estimated_conception_date + 273). Keep that join key separate so output
# can still retain the original date_of_birth.
if (isTRUE(create_anchored_variables$test_mode)) {
  logger::log_info(
    "Test mode is ON: using shifted date_of_birth anchor (estimated_conception_date + 273) to retrieve mother anchored covariates"
  )
  d4_children_study_cohort[, date_of_birth_anchor := estimated_conception_date + 273]
} else {
  d4_children_study_cohort[, date_of_birth_anchor := date_of_birth]
}

# Create mother cohort by deduplicating the children-trial cohort;
# for twins/multiplets, the children cohort includes one row per individual.
# here we collapse that on the mother level, i.e., we have one 
# row per mother and pregnancy (children on the same pregnancy always have same conception date and date of birth
# by assumption/construction)

d4_mother_study_cohort <- unique(d4_children_study_cohort[, .(
  mother_id,
  pregnancy_id,
  estimated_conception_date,
  date_of_birth,
  date_of_birth_anchor
)])

counts <- table(paste(d4_mother_study_cohort$mother_id, d4_mother_study_cohort$pregnancy_id, d4_mother_study_cohort$estimated_conception_date, d4_mother_study_cohort$date_of_birth, d4_mother_study_cohort$date_of_birth_anchor))

if( any(counts > 1)) {
  logger::log_warn(
    paste0(
      "There are ", sum(counts > 1), " duplicate mother/pregnancy entries in the mother cohort. ",
      "This may indicate an issue with the input data."
    )
  )
}
if(all(counts == 1)) {
  logger::log_info(
    "Mother cohort has unique mother/pregnancy entries."
  )
}


# Add a person_id equal to mother_id to match the output expected function;
# Note cohort still keeps the variable mother_id

d4_mother_study_cohort[, person_id := mother_id]

# CHECK (remove in final version)
anchoring_window_metadata[, is_expected_missing := FALSE]

# Replace T0 by the anchor_date

# ------------------------------------------
# Process date_of_birth anchored covariates
# ------------------------------------------

# date_of_birth_anchor as T0 for mother baseline covariates extraction
# (in test mode this is estimated_conception_date + 273; otherwise date_of_birth)
d4_mother_study_cohort[, T0 := date_of_birth_anchor]

covariates_date_of_birth <- anchoR::get_anchor_result(
  metadata = anchoring_window_metadata[
    cohort == "mother" &
      covariate == TRUE &
      exclude_var == FALSE &
      anchor_variable == "date_of_birth"
  ],
  anchor_hive_path = anchor_hive_dir,
  population = d4_mother_study_cohort,
  impute_missing = TRUE,
  result_shape = "wide"
)

# Drop temporary anchor key; keep original date_of_birth for downstream joins
covariates_date_of_birth[, date_of_birth_anchor := NULL]

# ------------------------------------------------------
# Process estimated_conception_date anchored covariates
# ------------------------------------------------------

# estimated_conception_date as T0 for mother baseline covariates extraction
d4_mother_study_cohort[, T0 := estimated_conception_date]
covariates_estimated_conception <- anchoR::get_anchor_result(
  metadata = anchoring_window_metadata[
    cohort == "mother" &
      covariate == TRUE &
      exclude_var == FALSE &
      anchor_variable == "estimated_conception_date"
  ],
  anchor_hive_path = anchor_hive_dir,
  population = d4_mother_study_cohort,
  impute_missing = TRUE,
  result_shape = "wide"
)

# Drop temporary anchor key; keep original date_of_birth for downstream joins
covariates_estimated_conception[, date_of_birth_anchor := NULL]

#------------------------------------------------------
# Combine the two covariate datasets by merging on person_id and T0
#------------------------------------------------------

# Combine the two covariate datasets by merging on person_id and T0
covariates <- data.table::merge.data.table(
  covariates_date_of_birth[, -c("T0")],
  covariates_estimated_conception[, -c("T0")],
  by = c(
    "person_id",
    "estimated_conception_date",
    "date_of_birth",
    "mother_id",
    "pregnancy_id",
    "window_name"
  ),
  all = TRUE
)

# Remove any variables with "date_" prefix
covariates <- covariates[, !grepl("^date_", names(covariates)), with = FALSE]

# Remove any "value_" prefix from variable names
data.table::setnames(covariates, old = names(covariates), new = sub("^value_", "", names(covariates)))

# # Rename mother_id to person_id to match D3_SPELLS
# data.table::setnames(covariates, old = "mother_id", new = "person_id")

# Add age-group to covariates dataset
logger::log_info(
  "Calculating age and age categories for mother baseline covariates"
)
spells <- unique(picard::load(
  file_path = config_project$outputs$dir_d3,
  file_name = "D3_SPELLS.parquet"
)[, .(person_id, birth_date)])
covariates <- merge(covariates, spells, by = "person_id", all.x = TRUE)
covariates[,
  SV_AGE_MOTHER := lubridate::year(estimated_conception_date) -
    lubridate::year(birth_date) -
    (format(estimated_conception_date, "%m-%d") < format(birth_date, "%m-%d"))
]

# Remove birth_date after calculating age
covariates[, birth_date := NULL]

# choose concept_ranges source
concept_ranges <- data.table::fread(file.path(
  "transformations/common_configuration/RWE-BRIDGE/concept_ranges.csv"
))[concept_id %in% "PP_AGE_CAT"]
data.table::setDT(concept_ranges)

# Add age category using the concept_ranges table
covariates <- covariates[
  concept_ranges,
  on = .(
    SV_AGE_MOTHER >= lower_range,
    SV_AGE_MOTHER < upper_range
  ),
  SV_AGE_MOTHER_CAT := i.description
]

# # Rename back mother_id to person_id to match D3_SPELLS
# data.table::setnames(covariates, old = "person_id", new = "mother_id")

#------------------------------------------------------
# Add person trial, T0, and father_id to each mother
#------------------------------------------------------

# Load father child linkage: "data/D4_analytic_datasets/D4_StudyCohortChild.parquet"
# and get father_id and T0 for each mother_id (they have the same child_id)
logger::log_info(
  "Loading D4_StudyCohortChild.parquet to get father_id and T0 for each mother_id"
)
d4_child <- picard::load(
  file_path = config_project$outputs$dir_d4,
  file_name = "D4_StudyCohortChild.parquet"
)[, .(child_id, father_id, mother_id, T0, estimated_conception_date, trial_id, group)]

# Replace d4_covariates_mother$person_id with father_id and rename it as person_id
logger::log_info(
  "Merging mother d4_covariates with d4_child to get father_id and T0 for each mother_id"
)
covariates <- data.table::merge.data.table(
  covariates,
  d4_child[, .(
    father_id,
    child_id,
    mother_id,
    T0,
    trial_id,
    estimated_conception_date,
    group
  )],
  by.x = c("person_id", "estimated_conception_date"),
  by.y = c("mother_id", "estimated_conception_date"),
  all.x = TRUE
)

# Take unique mother_id, child_id, trial_id to remove duplicates after merging
covariates <- unique(covariates, by = c("mother_id", "child_id", "trial_id", "group"))

# check uniqueness of T0 per cohort
dup_start <- covariates[, .N, by = .(person_id, T0, child_id)][N > 1]
if( nrow(dup_start) > 0) {
  logger::log_warn(
    paste0(
      "There are ", nrow(dup_start), " multiple entries at same person/T0/child_id in covariates. ",
      "This may indicate an issue with the merging process or the input data."
    )
  )
}

# # Replace d4_covariates_mother$person_id with father_id and rename it as person_id
# covariates[, person_id := father_id]

# Save to disk
picard::save(
  data = covariates,
  file_path = create_anchored_variables$output$dir,
  file_name = create_anchored_variables$output$baseline_cov_file_mother
)

rm(d4_mother_study_cohort, covariates)
gc()
logger::log_info(paste0("Finished extracting mother baseline covariates "))


logger::log_info("Mother baseline covariates extraction completed")
picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
