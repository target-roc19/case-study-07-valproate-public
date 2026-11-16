################################################################
# impute_outcome ---
# Aim:
# Create multiple-imputation follow-up data for estimand 1 and estimand 2 by imputing
# event_estimand1 and event_estimand2 among records with non-administrative censoring.
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D4_analytic_datasets/D4_StudyCohortFupChild.parquet
# - data/D4_analytic_datasets/D4_StudyCohortCovariates.parquet
#
# Output: ---
# - data/D4_analytic_datasets/D4_StudyCohortFupChildMI.parquet (containing both estimand 1 and 2)
################################################################

# Initial setup ---
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("impute_outcomes.R")
  lm$start_capturing_prints()
}

# Config loading ---
picard::load_config()
imp_cfg <- config_project$impute_outcome
dir_d4 <- config_project$outputs$dir_d4
dir_d5 <- config_project$outputs$dir_d5

picard::audit_start(
  file_name = "impute_outcomes",
  deap_name = config_project$DEAP_configuration$name
)

# Load required functions ---
source("transformations/T3_study_design/source_code/functions/impute_estimand_function.R")

logger::log_info(glue::glue("Processing study cohort child follow up object"))

# Load data ---
# Load follow-up and covariate data
logger::log_info("Loading follow-up and covariate data.")
fup <- picard::load(
  file_path = dir_d4,
  file_name = glue::glue("{imp_cfg$input$fup_file}.{imp_cfg$input$ext}")
)
covariates <- picard::load(
  file_path = dir_d4,
  file_name = glue::glue("{imp_cfg$input$cov_file}.{imp_cfg$input$ext}")
)

# Load covariates from configuration file
logger::log_info("Loading covariates from configuration file.")
covnames <- unique(unlist(imp_cfg$model$predictors, use.names = FALSE))
additional_covnames <- unique(unlist(imp_cfg$model$additional_predictors, use.names = FALSE))

# If not specified, use all covariates included in the final PS model
if (length(covnames) == 0L) {
  logger::log_info("No covariates specified in configuration. Using exposure group andall covariates from the final PS model.")
  covnames <- c("group", picard::load("data/D5_results/D5_PS_ModelBuilding.csv")[included_r2 == TRUE, variable_id])
}

# Define keys and columns to keep for merging
fup_keys <- c("person_id", "T0", "trial_id")
cov_keep <- c(fup_keys, covnames, additional_covnames)
fup_keep <- c(
  fup_keys, "child_id", "father_id", "date_of_birth",
  "event_estimand1", "outcome_missing_estimand1", "general_end_fup_estimand1", "pyr_estimand1",
  "event_estimand2", "outcome_missing_estimand2", "general_end_fup_estimand2", "pyr_estimand2",
  "child_age_at_endfup_est1", "child_age_at_endfup_est2"
)

# Set person_id in df_fup to be the father_id
fup[, person_id := father_id]

# Calculate child age at end of follow-up for each estimand (sensitivity analysis)
fup[, child_age_at_endfup_est1 := as.numeric(difftime(general_end_fup_estimand1, date_of_birth, units = "days") / 365.25)]
fup[, child_age_at_endfup_est2 := as.numeric(difftime(general_end_fup_estimand2, date_of_birth, units = "days") / 365.25)]

# Merge follow-up and covariate data
mi_dt <- data.table::merge.data.table(
  fup[, ..fup_keep],
  covariates[, ..cov_keep],
  by = fup_keys,
  all.x = TRUE
)

# Repeat for main analysis (default) and sensitivity analysis (+ calendar time and child age) dataset
for (analysis_type in c("main", "sensitivity")) {
  logger::log_info(glue::glue("Processing {analysis_type} analysis dataset."))

  # Define covariates for each estimand based on analysis type
  if (analysis_type == "sensitivity") {
    # For sensitivity analysis, include additional covariates (calendar time and child age at end of follow-up)
    covnames_est1 <- unique(c(covnames, "SV_CALENDAR_TIME_INT", "child_age_at_endfup_est1"))
    covnames_est2 <- unique(c(covnames, "SV_CALENDAR_TIME_INT", "child_age_at_endfup_est2"))
  } else {
    # For main analysis, use the specified covariates
    covnames_est1 <- covnames
    covnames_est2 <- covnames
  }

  available_predictors_est1 <- covnames_est1[covnames_est1 %in% names(mi_dt)]
  available_predictors_est2 <- covnames_est2[covnames_est2 %in% names(mi_dt)]
  missing_predictors <- setdiff(c(covnames_est1, covnames_est2), c(available_predictors_est1, available_predictors_est2))

  if (length(missing_predictors) > 0L) {
    logger::log_error(
      glue::glue(
        "Missing predictors dropped: {paste(missing_predictors, collapse = ', ')}"
      )
    )
  }

  if (!"event_estimand1" %in% names(mi_dt)) {
    logger::log_error("event_estimand1 is not present in the input FUP dataset.")
  }

  if (!"event_estimand2" %in% names(mi_dt)) {
    logger::log_error("event_estimand2 is not present in the input FUP dataset.")
  }

  # Convert event_estimand1 and event_estimand2 to integer and set missing values for non-admin rows
  mi_dt[, event_estimand1_observed := as.integer(event_estimand1)]
  mi_dt[, event_estimand1 := as.integer(event_estimand1)]
  mi_dt[outcome_missing_estimand1 == TRUE, event_estimand1 := NA_integer_]

  mi_dt[, event_estimand2_observed := as.integer(event_estimand2)]
  mi_dt[, event_estimand2 := as.integer(event_estimand2)]
  mi_dt[outcome_missing_estimand2 == TRUE, event_estimand2 := NA_integer_]

  # Convert covariates and outcomes to factors for imputation
  # Exclude numeric columns (SV_CALENDAR_TIME_INT, child_age_at_endfup_est1/2) and event columns
  numeric_cols <- c("SV_CALENDAR_TIME_INT", "child_age_at_endfup_est1", "child_age_at_endfup_est2", "pyr_estimand1", "pyr_estimand2", "event_estimand1", "event_estimand2")
  for (col in setdiff(c(covnames), numeric_cols)) {
    if (col %in% names(mi_dt)) {
      mi_dt[, (col) := as.factor(get(col))]
    }
  }
  
  data_not_missing <- mi_dt[!is.na(event_estimand1),]
  # Drop unused factor levels for all factor columns after subsetting
  for (col in available_predictors_est1) {
    if (is.factor(data_not_missing[[col]])) {
      data_not_missing[, (col) := droplevels(get(col))]
    }
  }
  
  # Remove zero-variance predictors (factors with only 1 level) from the model
  valid_predictors_est1 <- available_predictors_est1[sapply(available_predictors_est1, function(col) {
    if (is.factor(data_not_missing[[col]])) {
      nlevels(data_not_missing[[col]]) > 1
    } else {
      length(unique(data_not_missing[[col]])) > 1
    }
  })]
  
  if (length(valid_predictors_est1) == 0) {
    logger::log_error("No valid predictors with variance found for estimand 1 model.")
  }

  ### Add MICE models ad-hoc diagnostics
  ## Estimate logistic regression of outcome on covariates to get approximate idea of how the imputation model looks like
  model_summary <- summary(stats::glm(as.formula(paste("event_estimand1 ~", paste(valid_predictors_est1, collapse = " + "))), data = data_not_missing, family = binomial))
  
  picard::save(
    data = model_summary,
    file_path = dir_d5,
    file_name = glue::glue("outcome_imputation_diagnostics/D5_LogisticModel_estimand1_{analysis_type}.RData")
  )

  ## Add table comparing distribution of covariates by value of the outcome (0 no outcome, 1 outcome) to assess
  ## possible separation issues
  outcome <- "event_estimand1"
  
  ## Create ad-hoc bins
  bins <- list(
  SV_CALENDAR_TIME_INT     = c(0, 15, 30, 45, 60, 75),
  child_age_at_endfup_est1 = -5:8
  )

  sep_check <- lapply(valid_predictors_est1, function(v) {
   x <- data_not_missing[[v]]
    if (v %in% names(bins)) x <- cut(x, breaks = bins[[v]], include.lowest = TRUE)
    y <- factor(data_not_missing[[outcome]], levels = c(0, 1))
    tab <- table(x, y, useNA = "ifany")
    data.frame(predictor = v, level = rownames(tab), as.data.frame.matrix(tab), row.names = NULL)
  }) |> dplyr::bind_rows()

  # Save separation check 
  picard::save(
    data = sep_check,
    file_path = dir_d5,
    file_name = glue::glue("outcome_imputation_diagnostics/D5_SeparationCheck_estimand1_{analysis_type}.csv")
  )

  # compare covariates across missing and non-missing outcome groups for estimand 1
  outcomes.not.missing <- mi_dt[!is.na(event_estimand1),]
  outcomes.missing <- mi_dt[is.na(event_estimand1),]
  summary.outcomes.not.missing <- summary(outcomes.not.missing)
  summary.outcomes.missing <- summary(outcomes.missing)

  picard::save(
    data = list(
      summary.outcomes.not.missing = summary.outcomes.not.missing,
      summary.outcomes.missing = summary.outcomes.missing
    ),
    file_path = dir_d5,
    file_name = glue::glue("outcome_imputation_diagnostics/D5_SummaryCovariates_estimand1_{analysis_type}.RData")
  )


  # Impute missing outcomes for both estimands ---
  imp_estimand1 <- impute_estimand(mi_dt, 1, available_predictors_est1, imp_cfg)
  imp_estimand2 <- impute_estimand(mi_dt, 2, available_predictors_est2, imp_cfg)

  # For estimand 1 and sensitivity analysis, include an additional imputation model with all covariates but excluding
  # child_age_at_endfup_est1 
  if (analysis_type == "sensitivity") {
    available_predictors_est1_sens <- setdiff(available_predictors_est1, "child_age_at_endfup_est1")
    imp_estimand1_sens_extra <- impute_estimand(mi_dt, 1, available_predictors_est1_sens, imp_cfg)
  }


  # Save summary of imputation results for estimand 1
  writeLines(capture.output(summary(imp_estimand1$imp)), con = file.path(dir_d5, glue::glue("outcome_imputation_diagnostics/D5_MICE_Summary_estimand1_{analysis_type}.txt")))
  # Save summary of imputation results for estimand 2
  writeLines(capture.output(summary(imp_estimand2$imp)), con = file.path(dir_d5, glue::glue("outcome_imputation_diagnostics/D5_MICE_Summary_estimand2_{analysis_type}.txt")))

  # save plot the convergence of the imputation process as png
  # estimand 1
  logger::log_info(glue::glue("Saving convergence plots for estimand 1 and estimand 2."))
  plot_file <- glue::glue("D5_MICE_ConvergencePlot_estimand1_{analysis_type}")
  png(file = file.path(dir_d5, glue::glue("{plot_file}.png")), width = 24, height = 18, units = "cm", res = 300)
  print(plot(imp_estimand1$imp))
  dev.off()
  # estimand 1 extra analysis removing child_afe_at_endfup_est1
  if (analysis_type == "sensitivity") {
    plot_file <- glue::glue("D5_MICE_ConvergencePlot_estimand1_sensitivity_no_child_age")
    png(file = file.path(dir_d5, glue::glue("{plot_file}.png")), width = 24, height = 18, units = "cm", res = 300)
    print(plot(imp_estimand1_sens_extra$imp))
    dev.off()
  }

  # estimand 2
  plot_file <- glue::glue("D5_MICE_ConvergencePlot_estimand2_{analysis_type}")
  png(file = file.path(dir_d5, glue::glue("{plot_file}.png")), width = 24, height = 18, units = "cm", res = 300)
  print(plot(imp_estimand2$imp))
  dev.off()
  

  # Create a list of completed datasets with imputed values for non-admin rows
  m <- as.integer(imp_cfg$model$n_imputations)
  out_list <- lapply(seq_len(m), function(i) {
    out <- data.table::copy(mi_dt)

    # Impute estimand 1
    if (!is.null(imp_estimand1)) {
      completed_estimand1 <- mice::complete(imp_estimand1$imp, action = i)
      out[imp_estimand1$idx_impute, event_estimand1 := completed_estimand1[imp_estimand1$idx_impute, "event_estimand1"]]
    }

    # Impute estimand 2
    if (!is.null(imp_estimand2)) {
      completed_estimand2 <- mice::complete(imp_estimand2$imp, action = i)
      out[imp_estimand2$idx_impute, event_estimand2 := completed_estimand2[imp_estimand2$idx_impute, "event_estimand2"]]
    }

    out[, imputation_id := i]
    out
  })

  # Combine the list of completed datasets into a single data.table and calculate follow-up lengths
  output_dt <- data.table::rbindlist(out_list, use.names = TRUE)

  # Calculate follow-up lengths for estimand 1
  output_dt[, fup_d_estimand1 := general_end_fup_estimand1]
  output_dt[, fup_length_days_estimand1 := as.numeric(difftime(fup_d_estimand1, T0, units = "days") + 1)]
  output_dt[, fup_length_months_estimand1 := fup_length_days_estimand1 / config_values$month_length]

  # Calculate follow-up lengths for estimand 2
  output_dt[, fup_d_estimand2 := general_end_fup_estimand2]
  output_dt[, fup_length_days_estimand2 := as.numeric(difftime(fup_d_estimand2, T0, units = "days") + 1)]
  output_dt[, fup_length_months_estimand2 := fup_length_days_estimand2 / config_values$month_length]

  # Restore person_id to be the child_id for the output dataset
  output_dt[, person_id := child_id]

  # Save the output dataset with imputed outcomes
  picard::save(
    data = output_dt,
    file_path = dir_d4,
    file_name = glue::glue("{imp_cfg$output$fup_mi_file}{ifelse(analysis_type == 'main', '', '_TV')}.{imp_cfg$output$ext}")
  )
}

rm(fup, covariates, mi_dt, out_list, output_dt, imp_estimand1, imp_estimand2)
if (exists("imp")) {
  rm(imp)
}
gc()

picard::audit_end()

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
