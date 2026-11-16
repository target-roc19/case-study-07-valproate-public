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
  lm$start_script("create_anchored_variables")
  lm$start_capturing_prints()
}

## Config loading ----
config_project <- picard::load_config("configuration/config_project.yaml")
config_values <- picard::load_config("configuration/config_values.yaml")
create_anchored_variables <- config_project$create_anchored_variables

# Set path to concepts database
concepts_dir <- create_anchored_variables$input$concepts_dir

# Output path for anchored variables in the Hive format
male_anchor_hive_dir <- create_anchored_variables$output$anchoring_dir_male
mother_anchor_hive_dir <- create_anchored_variables$output$anchoring_dir_mother
child_anchor_hive_dir <- create_anchored_variables$output$anchoring_dir_child


## Audit setup ---
picard::audit_start(
  file_name = "create_anchored_variables",
  deap_name = config_project$DEAP_configuration$name
)

logger::log_info("Starting: variable anchoring")

# ----------------------------
# LOAD METADATA
# ----------------------------

# load anchoring window metadata which defines the variables to be anchored,
# their data type, and the time windows for anchoring
anchoring_window_metadata <- picard::load(
  file_path = create_anchored_variables$input$metadata_dir,
  file_name = create_anchored_variables$input$metadata_file
)

# ----------------------------
# LOAD AND ANCHOR MALE DATA
# ----------------------------

if (create_anchored_variables$config$anchor_males) {
  # Load all cohorts and collect unique person_id + T0.

  # Anchoring is run once on this combined population to avoid redundant work.
  logger::log_info("Loading male study cohort")
  d4_studycohort <- data.table::as.data.table(picard::load(
    file_path = create_anchored_variables$input$cohort_dir,
    file_name = create_anchored_variables$input$cohort_file
  ))

  # Keep only unique person_id + T0 combinations to avoid redundant anchoring
  d4_studycohort <- unique(d4_studycohort[, .(person_id, T0)])

  logger::log_info(paste0(
    "D4_StudyCohort with unique person_id + T0: ",
    nrow(d4_studycohort)
  ))

  # ANCHOR ALL MALE VARIABLES ----------
  anchoR::anchor_by_variable(
    population = d4_studycohort,
    metadata = anchoring_window_metadata[cohort == "males" & exclude_var == FALSE],
    concepts = concepts_dir,
    anchor_col = "T0",
    anchor_hive_path = male_anchor_hive_dir
  )

  logger::log_info("Variable anchoring completed for males")
} else {
  logger::log_info("Skipping male baseline covariates extraction as per configuration settings")
}

# ----------------------------
# LOAD AND ANCHOR CHILDREN DATA
# ----------------------------

if (create_anchored_variables$config$anchor_children) {
  # Load all cohorts and collect unique person_id + T0.

  # Anchoring is run once on this combined population to avoid redundant work.
  logger::log_info("Loading child study cohort")
  d4_studycohort <- data.table::as.data.table(picard::load(
    file_path = create_anchored_variables$input$cohort_dir,
    file_name = create_anchored_variables$input$cohort_file_child
  ))

  # Keep only unique person_id + T0 combinations to avoid redundant anchoring
  d4_studycohort <- unique(d4_studycohort[, .(child_id, date_of_birth)])

  # rename child_id to person_id to match the anchoring function's expected input
  data.table::setnames(d4_studycohort, old = "child_id", new = "person_id")

  logger::log_info(paste0(
    "D4_StudyCohortChild with unique child_id + date_of_birth: ",
    nrow(d4_studycohort)
  ))

  # ANCHOR ALL CHILDREN VARIABLES ----------
  anchoR::anchor_by_variable(
    population = d4_studycohort,
    metadata = anchoring_window_metadata[cohort == "offspring"],
    concepts = concepts_dir,
    anchor_col = "date_of_birth",
    anchor_hive_path = child_anchor_hive_dir
  )

  logger::log_info("Variable anchoring completed for children")
} else {
  logger::log_info("Skipping children baseline covariates extraction as per configuration settings")
}

# ----------------------------
# LOAD AND ANCHOR MOTHER DATA
# ----------------------------

if (create_anchored_variables$config$anchor_mothers) {
  # Load all cohorts and collect unique person_id + T0.

  # Anchoring is run once on this combined population to avoid redundant work.
  logger::log_info("Loading child study cohort to anchor mother variables")
  d4_studycohort <- data.table::as.data.table(picard::load(
    file_path = create_anchored_variables$input$cohort_dir,
    file_name = create_anchored_variables$input$cohort_file_child
  ))

  # Keep only unique person_id + T0 combinations to avoid redundant anchoring
  d4_studycohort <- unique(d4_studycohort[, .(mother_id, pregnancy_id, estimated_conception_date, date_of_birth)])

  # Add columns start_episode and end_episode, corresponding to estimated_conception_date and date_of_birth, respectively
  d4_studycohort[, start_episode := estimated_conception_date]
  d4_studycohort[, end_episode := date_of_birth]

  # If test_mode == TRUE use end_episode as estimated_conception_date + 9 months
  if (create_anchored_variables$test_mode) {
    logger::log_info("Test mode is ON: setting end_episode to estimated_conception_date + 9 months (273 days)")
    d4_studycohort[, date_of_birth := estimated_conception_date + 273]
    d4_studycohort[, end_episode := estimated_conception_date + 273]
  }

  # Rename pregnancy_id to person_id to match the anchoring function's expected input
  # data.table::setnames(d4_studycohort, old = "pregnancy_id", new = "person_id")
  # d4_studycohort[, person_id := paste0(mother_id, "_", pregnancy_id)]
  d4_studycohort[, person_id := mother_id]

  logger::log_info(paste0(
    "D4_StudyCohortMother with unique person_id + estimated_conception_date + date_of_birth: ",
    nrow(d4_studycohort)
  ))

  # Add necessary columns to metadata: start_episode, end_episode, and event_col
  mother_metadata <- anchoring_window_metadata[cohort == "mother" & exclude_var == FALSE]
  mother_metadata[, event_col := "pregnancy_episodes"]
  mother_metadata[, anchor_start_col := anchor_variable]
  mother_metadata[, is_expected_missing := FALSE]

  # Make nested pregnancy episode data
  d4_studycohort[, pregnancy_episodes := lapply(person_id, function(id) {
    d4_studycohort[
      person_id == id,
      .(pregnancy_id = pregnancy_id, start_episode = start_episode, end_episode = end_episode)
    ]
  })]

  # Remove redundat columns
  pregnancy_periods <- d4_studycohort[, c("person_id","start_episode", "end_episode", "pregnancy_id")]
  d4_studycohort[, c("start_episode", "end_episode", "pregnancy_id") := NULL]

  # ANCHOR ALL MOTHER VARIABLES ----------

  # Anchor variables using the estimated_conception_date as the anchor date
  anchoR::anchor_by_variable(
    population = d4_studycohort,
    metadata = mother_metadata[anchor_variable == "estimated_conception_date"],
    concepts = concepts_dir,
    anchor_col = "estimated_conception_date",
    anchor_hive_path = mother_anchor_hive_dir,
    episodes = pregnancy_periods
  )

  # Anchor variables using the date_of_birth as the anchor date
  anchoR::anchor_by_variable(
    population = d4_studycohort,
    metadata = mother_metadata[anchor_variable == "date_of_birth"],
    concepts = concepts_dir,
    anchor_col = "date_of_birth",
    anchor_hive_path = mother_anchor_hive_dir,
    episodes = pregnancy_periods
  )

  logger::log_info("Variable anchoring completed for mothers")
} else {
  logger::log_info("Skipping mother baseline covariates extraction as per configuration settings")
}

rm(d4_studycohort, anchoring_window_metadata, mother_metadata)
gc()

picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
