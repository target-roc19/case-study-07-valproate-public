# ---------------------------------------------------------------
# Step: create_fup
#
# Input:  D3_ANCHORED_VARIABLES_male (data/D3_study_variables/)
#         D3_ANCHORED_VARIABLES_child (data/D3_study_variables/)
#         D4_StudyCohort (data/D4_analytic_datasets/)
#         D4_StudyCohortchild (data/D4_analytic_datasets/)
#         D3_SPELLS (data/D3_study_variables/)
#         D3_UNIVARIATE_EPISODES_parquet (data/D3_study_variables/)
#
# Output: D4_StudyCohortFup (data/D4_analytic_datasets/)
#         D4_StudyCohortFupChild (data/D4_analytic_datasets/)
#
# This script extracts follow-up variables for fathers and children from the
# anchored variables Hive, computes censoring dates and reasons for censoring,
# and calculates follow-up duration for each individual. The output datasets
# are saved for further analysis.
# ---------------------------------------------------------------

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
  lm$start_script("create_fup")
  lm$start_capturing_prints()
}

## Config loading ----
config_project <- picard::load_config("configuration/config_project.yaml")
config_values <- picard::load_config("configuration/config_values.yaml")
create_anchored_variables <- config_project$create_anchored_variables

# Path to anchored variables Hive
anchor_hive_dir <- create_anchored_variables$output$anchoring_dir_male
anchor_hive_dir_child <- create_anchored_variables$output$anchoring_dir_child

## Functions ----
source("transformations/T3_study_design/source_code/functions/follow_up_functions.R")
source("transformations/T3_study_design/source_code/functions/treatment_censoring_functions.R")

## Audit setup ---
picard::audit_start(
  file_name = "create_fup",
  deap_name = config_project$DEAP_configuration$name
)

logger::log_info("Starting: extracting post-exposure (fup) variables")

# ----------------------------
# LOAD METADATA
# ----------------------------

anchoring_window_metadata <- picard::load(
  file_path = create_anchored_variables$input$metadata_dir,
  file_name = create_anchored_variables$input$metadata_file
)

# =============================
# EXTRACT FATHER FUP VARIABLES
# =============================

logger::log_info("Extracting males fup variables")

# Load study cohort for this analysis to get the population to extract fup
# variables for. We only select person_id and T0 since those are needed for
# the anchoring, and match_id and group which are needed for some of the
# censoring rules and to add back to the fup table after extracting from the
# anchored variables hive.
d4_fup_father <- data.table::as.data.table(picard::load(
  file_path = create_anchored_variables$input$cohort_dir,
  file_name = create_anchored_variables$input$cohort_file
))

#-----------------------------------------
# 1) Add no_livebirth_conception
#-----------------------------------------
logger::log_info("Adding no_livebirth_conception variable from D4_StudyCohort$conception_within_3_years")

# if not conception within 3 years after T0, then no_livebirth_conception = assign T0 + 3 years as the date of no_livebirth, else NA
d4_fup_father[, no_livebirth_conception := as.Date(ifelse(!conception_within_3_years, T0 + lubridate::years(3), as.Date(NA)))]

# Also add livebirth_conception as the earliest conception date if it happens within 3 years of T0, else NA
# use conception_within_3_years to define it
d4_fup_father[, livebirth_conception := as.Date(ifelse(conception_within_3_years, earliest_conception_date, as.Date(NA)))]

#-----------------------------------------
# 2) Add conception_within_3_months
#-----------------------------------------
logger::log_info("Computing conception_within_3_months variable from D4_StudyCohort$earliest_conception_date")
d4_fup_father[, conception_within_3_months := as.Date(ifelse(!is.na(earliest_conception_date) & earliest_conception_date <= T0 + 30.25 * 3, as.Date(earliest_conception_date), as.Date(NA)))]

#-----------------------------------------
# 3) Add treatment discontinuation
#-----------------------------------------

# For a given drug we should check the current episode (which includes T0) and all the following episodes until we get a FALSE in IS_ON_VPA/LEV. Then we use the end_episode of the last episode with IS_ON_VPA/LVE = TRUE as the date of discontinuation (i.e., we concatenate episodes).

# For VPA --------

# For those rows with group == "EXPOSED": find the univariate episode for IS_ON_VPA that includes T0 and all subsequent episodes for the same person_id until we get a FALSE in IS_ON_VPA. Then we use the end_episode of the last episode with IS_ON_VPA = TRUE as the date of discontinuation (i.e., we concatenate episodes).

# CHECK: Load D3_UNIVARIATE_EPISODES to get the treatment discontinuation dates for VPA and LEV
path_to_vpa <- "data/D3_study_variables/D3_UNIVARIATE_EPISODES_parquet/variable_id=SV_IS_ON_VPA"
is_on_vpa <- data.table::as.data.table(picard::load(file.path(path_to_vpa, dir(path_to_vpa))))
is_on_vpa[, value := as.logical(value)]
is_on_vpa <- unique(is_on_vpa)

# Compute treatment discontinuation dates for each person_id + T0 in the follow-up dataset
disc_dates <- compute_treatment_discontinuation(d4_fup_father[group == "EXPOSED"], is_on_vpa)

# Remove duplicates introduced by episodeR in univariate episodes
disc_dates <- unique(disc_dates)

# Merge back to the follow-up dataset
d4_fup_father <- data.table::merge.data.table(
  x = d4_fup_father,
  y = disc_dates,
  by = c("person_id", "T0"),
  all.x = TRUE,
  sort = FALSE
)

# Rename treatment_discontinuation to treatment_discontinuation_vpa
data.table::setnames(d4_fup_father, "treatment_discontinuation", "treatment_discontinuation_vpa")

# For LEV --------

# For those rows with group == "CONTROL": find the univariate episode for IS_ON_LEV that includes T0 and all subsequent episodes for the same person_id until we get a FALSE in IS_ON_LEV. Then we use the end_episode of the last episode with IS_ON_LEV = TRUE as the date of discontinuation (i.e., we concatenate episodes).

path_to_lev <- "data/D3_study_variables/D3_UNIVARIATE_EPISODES_parquet/variable_id=SV_IS_ON_LEV"
is_on_lev <- picard::load(file.path(path_to_lev, dir(path_to_lev)))
is_on_lev <- data.table::as.data.table(is_on_lev)
is_on_lev[, value := as.logical(value)]
is_in_lev <- unique(is_on_lev)

# Compute treatment discontinuation dates for each person_id + T0 in the follow-up dataset
disc_dates <- compute_treatment_discontinuation(d4_fup_father[group == "CONTROL"], is_on_lev)

# Remove duplicates introduced by episodeR in univariate episodes
disc_dates <- unique(disc_dates)

# Merge back to the follow-up dataset
d4_fup_father <- data.table::merge.data.table(
  x = d4_fup_father,
  y = disc_dates,
  by = c("person_id", "T0"),
  all.x = TRUE,
  sort = FALSE
)

# Rename treatment_discontinuation to treatment_discontinuation_lev
data.table::setnames(d4_fup_father, "treatment_discontinuation", "treatment_discontinuation_lev")

# Finally, we can compute the treatment_discontinuation variable as the minimum of treatment_discontinuation_vpa and treatment_discontinuation_lev, depending on the group.
d4_fup_father[, treatment_discontinuation := ifelse(
  group == "EXPOSED",
  as.Date(treatment_discontinuation_vpa),
  as.Date(treatment_discontinuation_lev)
)]
# Convert to dates
d4_fup_father[, treatment_discontinuation := as.Date(treatment_discontinuation)]

# Finally if treatment_discontinuation occurs after earliest_conception_date,
# we set treatment_discontinuation to NA since it is not relevant for the follow-up period.
d4_fup_father[, treatment_discontinuation := as.Date(ifelse(
  !is.na(treatment_discontinuation) & !is.na(earliest_conception_date) & treatment_discontinuation > earliest_conception_date,
  as.Date(NA),
  treatment_discontinuation
))]

#-----------------------------------------
# 4) Add treatment_switch
#-----------------------------------------

# Also load the univariate episodes for IS_ON_OT_ASM to compute treatment switch
path_to_ot_asm <- "data/D3_study_variables/D3_UNIVARIATE_EPISODES_parquet/variable_id=SV_IS_ON_OT_ASM"
is_on_ot_asm <- picard::load(file.path(path_to_ot_asm, dir(path_to_ot_asm)))
is_on_ot_asm <- data.table::as.data.table(is_on_ot_asm)
is_on_ot_asm[, value := as.logical(value)]
is_on_ot_asm <- unique(is_on_ot_asm)

# Add first date of treatment start for VPA, LEV, and OT_ASM
d4_fup_father <- compute_treatment_switch(d4_fup_father, is_on_vpa, rename_to = "treatment_start_vpa")
d4_fup_father <- compute_treatment_switch(d4_fup_father, is_on_lev, rename_to = "treatment_start_lev")
d4_fup_father <- compute_treatment_switch(d4_fup_father, is_on_ot_asm, rename_to = "treatment_start_ot_asm")

# Switch date of treatment start to NA if the person is not in the corresponding group
# (e.g., if the person is in the EXPOSED group, then treatment_start_vpa should be NA)
d4_fup_father[group == "EXPOSED", treatment_start_vpa := as.Date(NA)]
d4_fup_father[group == "CONTROL", treatment_start_lev := as.Date(NA)]

# now define treatment_switch as the earliest of treatment_start_vpa, treatment_start_lev, and treatment_start_ot_asm
d4_fup_father[, treatment_switch := as.Date(do.call(pmin, c(.SD, na.rm = TRUE))), .SDcols = c("treatment_start_vpa", "treatment_start_lev", "treatment_start_ot_asm")]

# Finally, if treatment_switch occurs after earliest_conception_date, we set treatment_switch to NA since it is not relevant for the follow-up period.
d4_fup_father[, treatment_switch := as.Date(ifelse(
  !is.na(treatment_switch) & !is.na(earliest_conception_date) & treatment_switch > earliest_conception_date,
  as.Date(NA),
  treatment_switch
))]

#-----------------------------------------
# 5) Add treatment_stop_estimand2
#-----------------------------------------

# Moment where the father is identified to stop the treatment, if it happens more than 3 months before conception:
d4_fup_father[, treatment_stop_more_than_3_months := ifelse(
  !is.na(treatment_discontinuation) & !is.na(earliest_conception_date) & treatment_discontinuation < earliest_conception_date - 30.25 * 3,
  treatment_discontinuation,
  as.Date(NA)
)]
# As date
d4_fup_father[, treatment_stop_more_than_3_months := as.Date(treatment_stop_more_than_3_months)]

# Treatment discontinuation 3 months or less before conception:
d4_fup_father[, treatment_stop_3_months_or_less := ifelse(
  !is.na(treatment_discontinuation) & !is.na(earliest_conception_date) & treatment_discontinuation >= earliest_conception_date - 30.25 * 3,
  treatment_discontinuation,
  as.Date(NA)
)]
# As date
d4_fup_father[, treatment_stop_3_months_or_less := as.Date(treatment_stop_3_months_or_less)]

#-----------------------------------------
# 6) Add disenrolment_database_father when individuals are disenrolled from database
#-----------------------------------------

# 4) disenrolment_database_child when individuals are disenrolled from database
logger::log_info("Merging in disenrolment_database_father from D3_SPELLS$end_spell")
spells <- picard::load(
  file_path = config_project$outputs$dir_d3,
  file_name = "D3_SPELLS.parquet"
)[, .(person_id, end_spell)]

# If multiple spells per person raise a warning
if (nrow(spells) != length(unique(spells$person_id))) {
  logger::log_warn(paste0(
    "Found multiple spells per person in D3_SPELLS. The earliest spell after T0 (with the earliest end_spell date) will be used for each matched case to determine disenrolment_database_father."
  ))
  # For each person take the earliest end_spell after T0 date as the
  # disenrolment_database_father date (in case of multiple spells per person), and
  # keep NAs as is since they indicate no disenrolment from database rather than
  # missing data.

  # Unique row identifier
  d4_fup_father[, row_id := .I]

  # Merge spells with d4_fup_father to get end_spell dates for each person_id + T0
  # combination
  tmp <- data.table::merge.data.table(
    d4_fup_father[, .(row_id, person_id, T0)],
    spells,
    by = "person_id",
    all.x = TRUE,
    allow.cartesian = TRUE
  )

  # For each person_id + T0, take the earliest end_spell date that is after
  # T0 as the disenrolment_database_father date. If there are no end_spell dates after
  # T0, set disenrolment_database_father to NA.
  disenrolment_database_father <- tmp[
    ,
    .(
      disenrolment_database_father = {
        x <- end_spell[!is.na(end_spell) & end_spell > T0[1]]
        if (length(x)) min(x) else as.Date(NA)
      }
    ),
    by = row_id
  ]

  # Merge back the disenrolment_database_father variable to d4_fup_father using the row_id
  d4_fup_father[disenrolment_database_father, disenrolment_database_father := i.disenrolment_database_father, on = "row_id"]
  d4_fup_father[, row_id := NULL]

  rm(tmp, disenrolment_database_father)
} else {
  d4_fup_father <- data.table::merge.data.table(
    x = d4_fup_father,
    y = spells,
    by = "person_id",
    all.x = TRUE
  )
  data.table::setnames(d4_fup_father, "end_spell", "disenrolment_database_father")
}
# father_disenrolment_before_3_years: if disenrolment_database_father occurs before T0 + 3 years, then TRUE, else FALSE
d4_fup_father[, father_disenrolment_before_3_years := !is.na(disenrolment_database_father) & disenrolment_database_father < T0 + lubridate::years(3)]
rm(spells)

#-----------------------------------------
# 7) Add father_admin_censoring
#-----------------------------------------

# Moment of reaching 3 years and 9 months after T0, which is the administrative censoring date for fathers
d4_fup_father[, father_admin_censoring := T0 + lubridate::years(3)]


# ============================
# EXTRACT CHILD FUP VARIABLES
# ============================

logger::log_info("Extracting child fup variables")

d4_study_cohort_child <- data.table::as.data.table(picard::load(
  file_path = create_anchored_variables$input$cohort_dir,
  file_name = create_anchored_variables$input$cohort_file_child
))
# d4_study_cohort_child <- d4_study_cohort_child[, .(child_id, match_id, T0, group)]

# Use person_id as the child_id to match the anchoring function's expected input
d4_study_cohort_child[, person_id := child_id]

# CHECK (remove in final version)
anchoring_window_metadata[, is_expected_missing := FALSE]

logger::log_info("Extracting fup variables from anchored Hive using anchoR")

# don't pass the population argumentbecause the hive has date_of_birth as T0
# which is wrong in this case, as it would lead to filtering out cases wrongly
d4_fup_child <- anchoR::get_anchor_result(
  metadata = anchoring_window_metadata[cohort == "offspring"],
  anchor_hive_path = anchor_hive_dir_child,
  population = NULL,
  impute_missing = TRUE,
  only_date = TRUE,
  result_shape = "wide"
)[, -"T0"]

# merge d4_study_cohort_child and d4_fup_child
d4_fup_child <- data.table::merge.data.table(
  x = d4_study_cohort_child,
  y = d4_fup_child,
  by = "person_id",
  all.x = TRUE,
  sort = FALSE
)
d4_fup_child[, window_name := "risk"]

# Rename variables to match codebook names
data.table::setnames(d4_fup_child, old = c(
  "SV_MAJORCA", "SV_DEATH", "SV_AUTISM", "SV_ADHD"
), new = c(
  "major_congenital_malformation", "death_child", "diagnosis_autism", "diagnosis_adhd"
))

# Load additional variables if needed -------------------------

# 1) end_study_date from config_values.yaml
logger::log_info(paste0(
  "Using end_study_date from config_values.yaml: ",
  config_values$end_study_date
))
end_study_date <- as.Date(config_values$end_study_date)
d4_fup_child[, end_study_period_child := end_study_date]

# 2) recommended_end_date from config_values.yaml
logger::log_info(paste0(
  "Using recommended_end_date from config_values.yaml: ",
  config_values$recommended_end_date
))
recommended_end_date <- as.Date(config_values$recommended_end_date)
d4_fup_child[, end_of_data_collection_child := recommended_end_date]

# 3) Add age_8_years_old as the moment when the child turns 8 years old (date_of_birth + 8 years)
d4_fup_child[, age_8_years_old := date_of_birth + lubridate::years(8)]

# 4) disenrolment_database_child when individuals are disenrolled from database
logger::log_info("Merging in disenrolment_database_child from D3_SPELLS$end_spell")
spells <- picard::load(
  file_path = config_project$outputs$dir_d3,
  file_name = "D3_SPELLS.parquet"
)[, .(person_id, end_spell)]

# If multiple spells per person raise a warning
if (nrow(spells) != length(unique(spells$person_id))) {
  logger::log_warn(paste0(
    "Found multiple spells per person in D3_SPELLS. The earliest spell after T0 (with the earliest end_spell date) will be used for each matched case to determine disenrolment_database_child."
  ))
  # For each person take the earliest end_spell after T0 date as the
  # disenrolment_database_child date (in case of multiple spells per person), and
  # keep NAs as is since they indicate no disenrolment from database rather than
  # missing data.

  # Unique row identifier
  d4_fup_child[, row_id := .I]

  # Merge spells with d4_fup_child to get end_spell dates for each person_id + T0
  # combination
  tmp <- data.table::merge.data.table(
    d4_fup_child[, .(row_id, person_id, T0)],
    spells,
    by = "person_id",
    all.x = TRUE,
    allow.cartesian = TRUE
  )

  # For each person_id + T0, take the earliest end_spell date that is after
  # T0 as the disenrolment_database_child date. If there are no end_spell dates after
  # T0, set disenrolment_database_child to NA.
  disenrolment_database_child <- tmp[
    ,
    .(
      disenrolment_database_child = {
        x <- end_spell[!is.na(end_spell) & end_spell > T0[1]]
        if (length(x)) min(x) else as.Date(NA)
      }
    ),
    by = row_id
  ]

  # Merge back the disenrolment_database_child variable to d4_fup_child using the row_id
  d4_fup_child[disenrolment_database_child, disenrolment_database_child := i.disenrolment_database_child, on = "row_id"]
  d4_fup_child[, row_id := NULL]

  rm(tmp, disenrolment_database_child)
} else {
  d4_fup_child <- data.table::merge.data.table(
    x = d4_fup_child,
    y = spells,
    by = "person_id",
    all.x = TRUE
  )
  data.table::setnames(d4_fup_child, "end_spell", "disenrolment_database_child")
}
rm(spells)

# Compute variables -------------------------

# 1) Compute composite outcome as the earliest of autism, adhd, death and mca
logger::log_info("Computing composite outcome variable as the earliest of autism diagnosis, adhd diagnosis, death and major congenital malformation")
d4_fup_child[, composite_outcome := as.Date(
  do.call(pmin, c(.SD, na.rm = TRUE))
), .SDcols = c("major_congenital_malformation", "death_child", "diagnosis_autism", "diagnosis_adhd")]

#-----------------------------------------
# Censor and compute FUP duration
#----------------------------------------

# Set person_id to father_id again
d4_fup_child[, person_id := father_id]

# Combine father and child censoring variables into a data.table
# - keep all fathers
# - more than one children can be matched to a father-T0 if we have multiplets
d4_fup_child <- data.table::merge.data.table(
  x = d4_fup_father[, .(person_id, T0, group, treatment_switch, treatment_stop_more_than_3_months)],
  y = d4_fup_child,
  by = c("person_id", "T0", "group"),
  all.x = FALSE,
  all.y = TRUE,
  sort = FALSE
)

# Restore person_id to child_id for the child follow-up dataset
d4_fup_child[, person_id := child_id]

# Loop over estimands --------------------------
for (estimand in seq_along(c("estimand1", "estimand2"))) {
  # Compute censoring dates and reasons for censoring -------------------------

  # Estimand-specific censoring reasons
  if (estimand == 1) {
    logger::log_info("Computing censoring dates and reasons for censoring for estimand 1")
    father_censor_vars <- c(
      "earliest_conception_date",
      "treatment_switch",
      # "father_admin_censoring",
      "no_livebirth_conception",
      "disenrolment_database_father"
    )
    child_censor_vars <- c(
      "diagnosis_autism",
      "diagnosis_adhd",
      "death_child",
      "major_congenital_malformation",
      "end_study_period_child",
      "end_of_data_collection_child",
      "age_8_years_old",
      "disenrolment_database_child",
      # father censoring variables that are relevant for children
      "treatment_switch"
    )
  } else if (estimand == 2) {
    logger::log_info("Computing censoring dates and reasons for censoring for estimand 2")
    father_censor_vars <- c(
      "earliest_conception_date",
      "treatment_stop_more_than_3_months",
      "treatment_switch",
      # "father_admin_censoring",
      "no_livebirth_conception",
      "disenrolment_database_father"
    )
    child_censor_vars <- c(
      "diagnosis_autism",
      "diagnosis_adhd",
      "death_child",
      "major_congenital_malformation",
      "end_study_period_child",
      "end_of_data_collection_child",
      "age_8_years_old",
      "disenrolment_database_child",
      # father censoring variables that are relevant for children
      "treatment_stop_more_than_3_months",
      "treatment_switch"
    )
  }

  #-----------------------------------------
  # Censor males
  #-----------------------------------------

  # Estimand-specific reason_censoring_est*
  logger::log_info("Computing censoring dates and reasons for censoring in males")
  d4_fup_father <- censorFupAesiVect(
    aesi_fup_table = d4_fup_father,
    rw_id = NULL,
    person_id_var = "person_id",
    match_date_var = "T0",
    match_id_var = NULL,
    group_var = "group",
    ind_censor_vars = father_censor_vars,
    pair_censoring = FALSE,
    pair_censor_vars = NULL,
    # infant-denominator pregnancy outcomes
    selective_postpreg_censor = FALSE,
    preg_end_var = NULL,
    postpreg_censor_vars = NULL,
    # return reason for censoring for easier debugging
    return_reason = TRUE
  )

  # Estimand-specific FUP variables (end_fup, event_count, event_date, fup_dats, etc.)
  logger::log_info("Computing follow-up variables in males")

  # Note: when date_of_birth is not available (i.e., no live born) we get
  # end_fup = NA and_pyr = NA. This is expected and correct, as the follow-up
  # is defined for childre and not for fathers.
  d4_fup_father <- calculateFupLengthAesi(
    aesi_fup_table = d4_fup_father,
    rw_id = NULL, # indicator suffix to be given to computed columns (e.g., "_main")
    censor_date_var = "end_fup", # a single date, date of censoring
    event_date_var = "earliest_conception_date", # a single date, date of event occurrence
    start_risk_window_vars = "T0", # a vector of dates denoting start dates of the risk window(s)
    end_risk_window_vars = "father_admin_censoring", # a vector of dates denoting the end of rw; start_ and end_rw_date form pairs
    scaling = 1
  )

  # Rename end_fup and reason_endfup to estimand-specific names
  data.table::setnames(d4_fup_father,
    old = c("end_fup", "reason_endfup", "eventCount", "fup", "pyr"),
    new = c(paste0("general_end_fup_estimand", estimand), paste0("reason_endfup_estimand", estimand), paste0("event_estimand", estimand), paste0("fup_length_days_estimand", estimand), paste0("pyr_estimand", estimand))
  )

  #-----------------------------------------
  # Censor children
  #-----------------------------------------

  # Estimand-specific reason_censoring_est*
  logger::log_info("Computing censoring dates and reasons for censoring in children")
  d4_fup_child <- censorFupAesiVect(
    aesi_fup_table = d4_fup_child,
    rw_id = NULL,
    person_id_var = "child_id",
    match_date_var = "T0",
    match_id_var = NULL,
    group_var = "group",
    ind_censor_vars = child_censor_vars,
    pair_censoring = FALSE,
    pair_censor_vars = NULL,
    # infant-denominator pregnancy outcomes
    selective_postpreg_censor = FALSE,
    preg_end_var = NULL,
    postpreg_censor_vars = NULL,
    # return reason for censoring for easier debugging
    return_reason = TRUE
  )

  # Estimand-specific FUP variables (end_fup, event_count, event_date, fup_dats, etc.)
  logger::log_info("Computing follow-up variables in children")

  # Note: when date_of_birth is not available (i.e., no live born) we get
  # end_fup = NA and_pyr = NA. This is expected and correct, as the follow-up
  # is defined for childre and not for fathers.
  d4_fup_child <- calculateFupLengthAesi(
    aesi_fup_table = d4_fup_child,
    rw_id = NULL, # indicator suffix to be given to computed columns (e.g., "_main")
    censor_date_var = "end_fup", # a single date, date of censoring
    event_date_var = "composite_outcome", # a single date, date of event occurrence
    start_risk_window_vars = "date_of_birth", # a vector of dates denoting start dates of the risk window(s)
    end_risk_window_vars = "age_8_years_old", # a vector of dates denoting the end of rw; start_ and end_rw_date form pairs
    scaling = 1
  )

  # CHECK:
  # If child reason_endfup is a father censoring reason, then we set eventCount,
  # fup, and pyr to NA since the child is censored due to a father reason. Not
  # doing so would be problematic and lead to a negative follow-up time for the
  # child, which is not possible.
  d4_fup_child[reason_endfup %in% father_censor_vars, `:=`(
    eventCount = as.numeric(NA),
    fup = as.numeric(NA),
    pyr = as.numeric(NA)
  )]

  # outcome_observed: Is the outcome known at 8 years of age? Yes if the event
  # was observed, or the event was not observed and the children reached 8 years
  # of age
  d4_fup_child[, outcome_observed := ifelse(reason_endfup %in% c(
    "diagnosis_autism",
    "diagnosis_adhd",
    "death_child",
    "major_congenital_malformation",
    "age_8_years_old"
  ), TRUE, FALSE)]

  # outcome_missing: Is the outcome missing (and thus imputed). Yes if no event,
  # and children did not reach 8 years of age
  d4_fup_child[, outcome_missing := !outcome_observed]

  # Rename end_fup and reason_endfup to estimand-specific names
  data.table::setnames(d4_fup_child,
    old = c("end_fup", "reason_endfup", "eventCount", "fup", "pyr", "outcome_observed", "outcome_missing"),
    new = c(paste0("general_end_fup_estimand", estimand), paste0("reason_endfup_estimand", estimand), paste0("event_estimand", estimand), paste0("fup_length_days_estimand", estimand), paste0("pyr_estimand", estimand), paste0("outcome_observed_estimand", estimand), paste0("outcome_missing_estimand", estimand))
  )

  # Finally, check if any fathers (fathers linked to livebirth conception within
  # 3 years) have loss to follow up (disenrolment_database_father) before
  # earliest_conception_date. If so, we raise a warning since this would lead
  # to a gap of time in which treatment discontinuation and treatment switch
  # could have occurred, but we would not know about it
  n_fathers_at_risk <- d4_fup_father[!is.na(disenrolment_database_father) & disenrolment_database_father < earliest_conception_date & conception_within_3_years, .N]
  if (any(n_fathers_at_risk > 0)) {
    logger::log_warn(paste0(
      "There are ", n_fathers_at_risk, " fathers with loss to follow-up (disenrolment_database_father) before earliest_conception_date. This may lead to a gap of time in which treatment discontinuation and treatment switch could have occurred, but we would not know about it."
    ))
  }
} # end of the estimand loop

#-----------------------------------------
# Save outputs
#-----------------------------------------

# Save male FUP object
picard::save(
  data = d4_fup_father,
  file_path = create_anchored_variables$output$dir,
  file_name = create_anchored_variables$output$fup_file
)

# Save child FUP object
picard::save(
  data = d4_fup_child,
  file_path = create_anchored_variables$output$dir,
  file_name = create_anchored_variables$output$fup_file_child
)

rm(d4_fup_father, d4_study_cohort_child, d4_fup_child, disc_dates, is_on_vpa, is_on_lev, is_on_ot_asm)
gc()

logger::log_info("Fup computation completed")
picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
