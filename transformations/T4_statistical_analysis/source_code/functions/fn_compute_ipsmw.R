#' Compute IPSMW objects for one analysis cohort
#'
#' Implements the principal-stratum weighting workflow:
#' 1) read the conception_within_3_years indicator
#' 2) fit exposed-only logistic model,
#' 3) predict principal stratum scores
#' 4) compute control IPSMW
#' 5) return person-level outputs, model coefficients, and model-building logs.
#'
#' Data flow and expected dimensions:
#' - Starts from `cohort_data` (person-level) and keeps selected groups only.
#' - Fits the compliance model on target-group rows only (default: exposed),
#'   then predicts scores for the full merged cohort table.
#' - The main IPSMW output is person-level (not person-time): typically one row
#'   per retained cohort row after group filtering.
#'
#' Output dimensions:
#' - `D4_StudyCohort_IPSMW`: person-level table, same as
#'   `cohort_data` in row count.
#' - `D5_PS_Coef_IPSMW`: one row per coefficient in the final logistic model.
#' - `D5_PS_ModelBuilding_IPSMW`: one row per variable in `ps_variables` with
#'   inclusion/exclusion diagnostics.
#'
#' @param cohort_data Data frame/data.table with study cohort rows.
#' @param ps_variables Data table from metadata defining model covariates.
#' @param se_threshold Numeric threshold for large standard errors in Round 1.
#' @param compliance_col Character name of the precomputed compliance indicator. Default is "conception_within_3_years".
#' @param group_levels Character vector of group levels to include (default: c("EXPOSED", "CONTROL")).
#' @param target_group Character scalar specifying which group to model for compliance (default: "EXPOSED").
#' @param use_speedglm Logical scalar. If TRUE, use speedglm for faster model fitting; if FALSE, use standard glm (default: FALSE).
#'
#' @return Named list with D4 IPSMW table, D5 coefficient table, D5 model
#'   building table, and updated FUP table containing compliant_exposed.
#'
#' @noRd
compute_ipsmw <- function(
  cohort_data,
  ps_variables,
  se_threshold = 10,
  compliance_col = "conception_within_3_years",
  group_levels = c("EXPOSED", "CONTROL"),
  target_group = "EXPOSED",
  use_speedglm = FALSE
) {
  # Normalize to data.table for consistent by-reference updates.
  cohort_dt <- data.table::as.data.table(cohort_data)
  # Keep only rows matching specified group levels.
  cohort_dt <- cohort_dt[group %in% group_levels]


  # Normalize shared categorical covariates once on the full merged cohort.
  present_ps <- ps_variables[var %in% names(cohort_dt)]
  for (i in seq_len(nrow(present_ps))) {
    v <- present_ps$var[i]
    vtype <- present_ps$vartype[i]
    refcat <- as.character(present_ps$reference_category[i])

    if (vtype %in% c("CAT", "TF")) {
      data.table::set(cohort_dt, j = v, value = as.factor(cohort_dt[[v]]))
      if (!is.na(refcat) && refcat %in% levels(cohort_dt[[v]])) {
        data.table::set(
          cohort_dt,
          j = v,
          value = stats::relevel(cohort_dt[[v]], ref = refcat)
        )
      }
    }
  }

  # Target-group-only modeling cohort (typically exposed for compliance modeling).
  model_data <- data.table::copy(cohort_dt[group == target_group])
  # Drop rows where compliance cannot be evaluated, if any
  model_data <- model_data[!is.na(conception_within_3_years)]
  # Logistic regression expects a numeric binary response.
  model_data[, conception_within_3_years_binary := as.integer(conception_within_3_years)]

  if (nrow(model_data) == 0) {
    stop(paste0("No exposed rows available for IPSMW model"))
  }

  # Initialize model-building tracking table from metadata.
  model_building <- data.table::copy(ps_variables[, .(
    variable_id = var,
    var_type = vartype,
    force_in = if ("force_in" %in% names(ps_variables)) force_in else TRUE,
    force_out = if ("force_out" %in% names(ps_variables)) force_out else FALSE
  )])

  # Flag covariates missing entirely in the analysis data.
  model_building[, exists_in_data := variable_id %in% names(model_data)]

  # Compute missingness percentages for candidate variables.
  model_building[, missing_pct := vapply(
    variable_id,
    function(v) {
      if (!(v %in% names(model_data))) {
        return(NA_real_)
      }
      100 * sum(is.na(model_data[[v]])) / nrow(model_data)
    },
    numeric(1)
  )]

  # Compute non-zero variance flags to avoid singular predictors.
  model_building[, nonzero_variance := vapply(
    variable_id,
    function(v) {
      if (!(v %in% names(model_data))) {
        return(FALSE)
      }
      length(unique(model_data[[v]][!is.na(model_data[[v]])])) >= 2
    },
    logical(1)
  )]

  # Round 1 inclusion bookkeeping.
  model_building[, include_r1 := FALSE]
  model_building[, reason_excluded := NA_character_]

  model_building[exists_in_data == FALSE, reason_excluded := "missing_in_data"]
  model_building[nonzero_variance == FALSE & exists_in_data == TRUE, reason_excluded := "zero_variance"]
  model_building[force_out == TRUE, reason_excluded := "force_out"]

  # Initial predictor set must pass data presence/variance checks and not be
  # force-excluded by metadata.
  eligible_vars <- model_building[
    exists_in_data == TRUE & nonzero_variance == TRUE & force_out == FALSE,
    variable_id
  ]

  if (length(eligible_vars) == 0) {
    stop(paste0("No eligible predictors available for IPSMW model in "))
  }

  model_building[variable_id %in% eligible_vars, include_r1 := TRUE]

  # Round 1 model fit.
  logger::log_info(paste(
    "IPSMW model Round 1 with",
    length(eligible_vars),
    "predictors"
  ))

  model_r1 <- fit_ps_model(
    predictors = eligible_vars,
    cohort_covariates = model_data,
    outcome_col = "conception_within_3_years_binary",
    use_speedglm = use_speedglm
  )

  if (is.null(model_r1)) {
    stop(paste0("Round 1 IPSMW model failed for"))
  }

  # Non-converged models mark all Round-1 variables as problematic.
  if (!isTRUE(model_r1$converged)) {
    model_building[include_r1 == TRUE, reason_excluded := "non_convergence"]
  }

  # Identify unstable variables by large standard errors in coefficient blocks.
  coef_summary_r1 <- as.data.frame(summary(model_r1)$coefficients)
  for (v in eligible_vars) {
    coef_rows <- grep(paste0("^", v), rownames(coef_summary_r1))
    if (length(coef_rows) > 0) {
      max_se <- max(coef_summary_r1[coef_rows, "Std. Error"])
      if (is.finite(max_se) && max_se > se_threshold) {
        model_building[variable_id == v, reason_excluded := "large_se"]
      }
    }
  }

  # Variables flagged in Round 1 are removed and model is re-fit in Round 2.
  problematic_vars <- model_building[
    include_r1 == TRUE & !is.na(reason_excluded),
    variable_id
  ]

  if (length(problematic_vars) > 0) {
    r2_predictors <- setdiff(eligible_vars, problematic_vars)
    if (length(r2_predictors) == 0) {
      stop(paste0("All predictors excluded after Round 1"))
    }

    logger::log_info(paste(
      "IPSMW model Round 2 removing:",
      paste(problematic_vars, collapse = ", ")
    ))

    model_final <- fit_ps_model(
      predictors = r2_predictors,
      cohort_covariates = model_data,
      outcome_col = "conception_within_3_years_binary",
      use_speedglm = use_speedglm
    )

    if (is.null(model_final)) {
      stop(paste0("Round 2 IPSMW model failed"))
    }

    model_building[, included_r2 := variable_id %in% r2_predictors]
  } else {
    # Use Round 1 fit directly when no issues are identified.
    model_final <- model_r1
    model_building[, included_r2 := include_r1]
  }

  # Extract coefficient diagnostics from final model.
  coef_summary <- as.data.frame(summary(model_final)$coefficients)
  d5_ps_coef <- data.table::data.table(
    coefficient = rownames(coef_summary),
    estimate = coef_summary[, 1],
    std_error = coef_summary[, 2],
    z_score = coef_summary[, 3],
    p_value = coef_summary[, 4],
    exp_estimate = exp(coef_summary[, 1])
  )

  # Predict principal stratum score for controls and store directly in table.
  cohort_dt[, psm_score_all := stats::predict(model_final, newdata = cohort_dt, type = "response")]

  # # Compute principal-stratum score from linear predictor + inverse-logit.
  # # This avoids predict-method differences across glm/speedglm objects.
  # score_terms <- stats::delete.response(stats::terms(model_final))
  # if (!is.null(model_final$xlevels)) {
  #   score_matrix <- stats::model.matrix(score_terms, data = score_data, xlev = model_final$xlevels)
  # } else {
  #   score_matrix <- stats::model.matrix(score_terms, data = score_data)
  # }

  # model_coef <- stats::coef(model_final)
  # missing_coef <- setdiff(colnames(score_matrix), names(model_coef))
  # if (length(missing_coef) > 0) {
  #   model_coef <- c(model_coef, stats::setNames(rep(0, length(missing_coef)), missing_coef))
  # }

  # model_coef <- model_coef[colnames(score_matrix)]
  # model_coef[is.na(model_coef)] <- 0

  # linear_predictor <- as.numeric(score_matrix %*% model_coef)
  # psm_score <- stats::plogis(linear_predictor)

  eps <- 1e-6
  cohort_dt[, psm_score_all := pmin(pmax(psm_score_all, eps), 1 - eps)]

  # Build person-level IPSMW output for everyone
  d4_ipsmw <- cohort_dt[, .(
    person_id,
    T0,
    group,
    conception_within_3_years,
    psm_score_all
  )]

  d4_ipsmw[, psm_score := psm_score_all]
  d4_ipsmw[, ipsmw_raw := psm_score / (1 - psm_score)]

  # Make weight 0 if no livebirth
  d4_ipsmw[is.na(conception_within_3_years) | conception_within_3_years == FALSE, ipsmw_raw := 0]
  # Make weight 1 if exposed and conception
  d4_ipsmw[group == target_group & conception_within_3_years == TRUE, ipsmw_raw := 1]

  # Assemble model-building output table.
  d5_model_building <- model_building[, .(
    variable_id,
    var_type,
    force_in,
    force_out,
    exists_in_data,
    missing_pct,
    nonzero_variance,
    include_r1,
    included_r2,
    reason_excluded
  )]

  return(list(
    D4_StudyCohort_IPSMW = d4_ipsmw,
    D5_PS_Coef_IPSMW = d5_ps_coef,
    D5_PS_ModelBuilding_IPSMW = d5_model_building
  ))
}
