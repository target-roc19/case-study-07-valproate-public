################################################################

# Initial setup ---
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("compute_mother_weights.R")
  lm$start_capturing_prints()
}

# Config loading ---
picard::load_config()

config_mother_weights <- config_project$compute_mother_weights

picard::audit_start(
  file_name = "compute_mother_weights",
  deap_name = config_project$DEAP_configuration$name
)

# Load male weights and children study cohort
male_iptw_weights <- picard::load(
  file_path = config_mother_weights$input$dir_d4,
  file_name = config_mother_weights$input$d4_iptw_male
)

# Load D4_StudyCohortChild to get mother_id and father_id
study_cohort_child <- picard::load(
  file_path = config_mother_weights$input$dir_d4,
  file_name = config_mother_weights$input$d4_studycohort_child
)

## add one in test twin: 
if(config_mother_weights$test_mode == TRUE){
  new.row <- study_cohort_child[1,]
  new.row[, child_id := paste0(child_id, "_twin")]
  study_cohort_child <- rbind(study_cohort_child, new.row)
}

mother_iptw_weights <- data.table::merge.data.table(
  x = male_iptw_weights,
  y = study_cohort_child[, .(T0, group, trial_id, pregnancy_id, date_of_birth, father_id, mother_id, child_id)],
  by.x = c("person_id", "T0", 'group'),
  by.y = c("father_id", "T0", 'group'),
  all.y = TRUE,
  all.x = FALSE
)

# Creating father id column in mother_iptw_weights to match with study_cohort_child
mother_iptw_weights[, father_id := person_id]

if(nrow(mother_iptw_weights) != nrow(study_cohort_child)) {
  logger::log_warn("The number of rows in mother_iptw_weights does not match the number of rows in study_cohort_child. There may be missing father_id values.")
}


# Count number of siblings for each mother/father (by T0, pregnancy_id, date_of_birth, group)
mother_iptw_weights[, n_siblings := .N, by = .(T0, pregnancy_id, date_of_birth, group)]
mother_iptw_weights[, n_siblings_by_father := .N, by = .(T0, father_id)]

# Throw error if calculations above don't coincide
if (!all(mother_iptw_weights[, n_siblings] == mother_iptw_weights[, n_siblings_by_father])) {
  logger::log_error("n_siblings and n_siblings_by_father are not equal for all rows. This indicates a mismatch in the sibling counts. Please check.")
}

# Divide weights by number of siblings to get mother weights
mother_iptw_weights[, raw_iptw := raw_iptw / n_siblings]
mother_iptw_weights[, stabilized_iptw := stabilized_iptw / n_siblings]
mother_iptw_weights[, stabilized_trunc_iptw := stabilized_trunc_iptw / n_siblings]

# check that all person id is equal to father id
if (all(mother_iptw_weights[, person_id] == mother_iptw_weights[, father_id])) {
  logger::log_info("All person_id values are equal to father_id values. This is expected.")
} else {
  logger::log_warn("Not all person_id values are equal to father_id values. Please check the data.")
}


# Save the output dataset with imputed outcomes
picard::save(
  data = mother_iptw_weights,
  file_path = config_mother_weights$output$dir,
  file_name = config_mother_weights$output$d4_iptw_mothers
)

rm(male_iptw_weights, mother_iptw_weights, study_cohort_child)
gc()

picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
