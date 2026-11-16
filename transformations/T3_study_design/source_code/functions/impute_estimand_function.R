#' Function to impute outcomes for a given estimand ---
#'
#' @param data A data.table containing the data to be imputed
#' @param estimand_num An integer indicating the estimand number (1 or 2)
#' @param available_predictors A character vector of available predictor column names
#' @param imputation_config A list containing the imputation configuration parameters
#' @return A list containing the imputed data, indices of rows to impute, event column name
#' and the number of imputations
#'
impute_estimand <- function(data, estimand_num, available_predictors, imputation_config) {
  estimand_str <- glue::glue("estimand{estimand_num}")
  event_col <- glue::glue("event_{estimand_str}")
  outcome_missing_col <- glue::glue("outcome_missing_{estimand_str}")

  # Prepare data for imputation
  model_cols <- c(event_col, available_predictors)
  model_input <- data.table::copy(data[, ..model_cols])

  # Count rows to impute
  non_admin_n <- data[get(outcome_missing_col) == TRUE, .N]
  logger::log_info(glue::glue("Rows with missing outcomes to impute ({estimand_str}): {non_admin_n}"))

  # Set up imputation parameters
  m <- as.integer(imputation_config$model$n_imputations)

  # Check if there are any non-admin rows to impute
  if (non_admin_n == 0L) {
    logger::log_warn(glue::glue("No rows with missing outcomes for {estimand_str}"))
    return(NULL)
  }

  # Initialize mice imputation
  init <- mice::mice(model_input, maxit = 0, printFlag = FALSE)
  method <- init$method
  predictor_matrix <- init$predictorMatrix

  # Set the imputation method and define the predictor matrix
  method[] <- ""
  method[event_col] <- imputation_config$model$method

  # Set the predictor matrix to only use available predictors
  predictor_matrix[, ] <- 0
  predictor_matrix[event_col, setdiff(colnames(model_input), event_col)] <- 1

  logger::log_info(
    glue::glue(
      "Imputing {event_col} using method: {imputation_config$model$method} with {m} imputations."
    )
  )

  # Run the imputation
  imp <- mice::mice(
    model_input,
    m = m,
    maxit = as.integer(imputation_config$model$maxit),
    method = method,
    predictorMatrix = predictor_matrix,
    seed = as.integer(imputation_config$model$seed),
    printFlag = FALSE
  )

  # Return completed imputation list
  return(list(
    imp = imp,
    idx_impute = which(data[[outcome_missing_col]] == TRUE),
    event_col = event_col,
    m = m
  ))
}
