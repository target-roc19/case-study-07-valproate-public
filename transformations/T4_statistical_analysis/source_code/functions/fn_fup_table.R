#' Create Table 5.2.x: Outcomes and Missing Data
#'
#' This function generates a table showing outcome status and missing data patterns
#' for children across exposed and control groups. The denominator is always the total
#' number of child-trial units in each group.
#'
#' @param d_child A data frame containing child-level follow-up data
#' @param estimand Integer (1 or 2) specifying which estimand to use
#' @param n_dec Integer specifying the number of decimal places (default = 1)
#'
#' @return A data.table with the formatted Table 5.2.x
#'
#' @details
#' The table includes:
#' - Missing (imputed) section: Categories of children with missing outcome data
#' - Not missing section: Outcomes observed, categorized by outcome type
#'
create_outcome_fup_table <- function(d_child,
                                     estimand = 1,
                                     n_dec = 1) {
  ## ---- Input validation ----
  if (!estimand %in% c(1, 2)) {
    stop("estimand must be 1 or 2")
  }

  # Column names
  outcome_obs_col <- paste0("outcome_observed_estimand", estimand)
  outcome_miss_col <- paste0("outcome_missing_estimand", estimand)
  reason_col <- paste0("reason_endfup_estimand", estimand)

  # Check if required columns exist
  if (!all(c(outcome_obs_col, outcome_miss_col, reason_col) %in% names(d_child))) {
    stop(paste0("Required columns not found in child data for estimand ", estimand))
  }

  d_child_copy <- data.table::as.data.table(d_child)

  ## ---- Define missing reasons ----
  missing_reasons <- c(
    "disenrolment_database_child",
    "disenrolment_database_father",
    "end_of_data_collection_child",
    "end_study_period_child", # Didn't reach 8 years without outcome
    "treatment_switch"
  )

  missing_labels <- c(
    "Disenrolment or migration child",
    "Disenrolment or migration before three years father",
    "End of data availability in data source",
    "Did not reach 8 years of age, no outcome",
    "Treatment switch"
  )

  if (estimand == 2) {
    # For estimand 2, split treatment discontinuation into two categories
    missing_reasons <- c(
      missing_reasons,
      "treatment_stop_more_than_3_months"
    )
    missing_labels <- c(
      missing_labels,
      "Treatment discontinuation more than 3 months before estimated conception"
    )
  }

  ## ---- Calculate counts and percentages ----
  # Total children per group
  n_exposed <- nrow(d_child_copy[d_child_copy[["group"]] == "EXPOSED"])
  n_control <- nrow(d_child_copy[d_child_copy[["group"]] == "CONTROL"])
  n_overall <- n_exposed + n_control

  # Initialize output columns
  col1 <- c()
  col2_overall_n <- c()
  col2_overall_pct <- c()
  col3_exposed_n <- c()
  col3_exposed_pct <- c()
  col4_control_n <- c()
  col4_control_pct <- c()

  # Helper function to add rows
  add_row <- function(label, count_exp, count_con) {
    pct_exp <- round(100 * count_exp / n_exposed, n_dec)
    pct_con <- round(100 * count_con / n_control, n_dec)
    count_overall <- count_exp + count_con
    pct_overall <- round(100 * count_overall / n_overall, n_dec)

    col1 <<- c(col1, label)
    col2_overall_n <<- c(col2_overall_n, as.character(count_overall))
    col2_overall_pct <<- c(col2_overall_pct, paste0(pct_overall, "%"))
    col3_exposed_n <<- c(col3_exposed_n, as.character(count_exp))
    col3_exposed_pct <<- c(col3_exposed_pct, paste0(pct_exp, "%"))
    col4_control_n <<- c(col4_control_n, as.character(count_con))
    col4_control_pct <<- c(col4_control_pct, paste0(pct_con, "%"))
  }

  # Header
  col1 <- c(col1, "")
  col2_overall_n <- c(col2_overall_n, paste0("Overall (N = ", n_overall, ")"))
  col2_overall_pct <- c(col2_overall_pct, "Count")
  col3_exposed_n <- c(col3_exposed_n, paste0("Exposed (N = ", n_exposed, ")"))
  col3_exposed_pct <- c(col3_exposed_pct, "Count")
  col4_control_n <- c(col4_control_n, paste0("Control (N = ", n_control, ")"))
  col4_control_pct <- c(col4_control_pct, "Percentage")

  # Header row 2
  col1 <- c(col1, "")
  col2_overall_n <- c(col2_overall_n, "Count")
  col2_overall_pct <- c(col2_overall_pct, "Percentage")
  col3_exposed_n <- c(col3_exposed_n, "Count")
  col3_exposed_pct <- c(col3_exposed_pct, "Percentage")
  col4_control_n <- c(col4_control_n, "Count")
  col4_control_pct <- c(col4_control_pct, "Percentage")

  # Missing section
  col1 <- c(col1, "Missing (imputed)")
  col2_overall_n <- c(col2_overall_n, "")
  col2_overall_pct <- c(col2_overall_pct, "")
  col3_exposed_n <- c(col3_exposed_n, "")
  col3_exposed_pct <- c(col3_exposed_pct, "")
  col4_control_n <- c(col4_control_n, "")
  col4_control_pct <- c(col4_control_pct, "")

  # Add missing reason rows
  for (i in seq_along(missing_labels)) {
    reason_var <- missing_reasons[i]

    # Count children with this missing reason
    d_exp_missing <- d_child_copy[d_child_copy[["group"]] == "EXPOSED" & d_child_copy[[outcome_miss_col]] == TRUE]
    d_con_missing <- d_child_copy[d_child_copy[["group"]] == "CONTROL" & d_child_copy[[outcome_miss_col]] == TRUE]

    count_exp <- sum(d_exp_missing[[reason_col]] == reason_var, na.rm = TRUE)
    count_con <- sum(d_con_missing[[reason_col]] == reason_var, na.rm = TRUE)

    add_row(paste0("   ", missing_labels[i]), count_exp, count_con)
  }

  # Not missing section
  col1 <- c(col1, "Not missing")
  col2_overall_n <- c(col2_overall_n, "")
  col2_overall_pct <- c(col2_overall_pct, "")
  col3_exposed_n <- c(col3_exposed_n, "")
  col3_exposed_pct <- c(col3_exposed_pct, "")
  col4_control_n <- c(col4_control_n, "")
  col4_control_pct <- c(col4_control_pct, "")

  # Reached 8 years without outcome
  d_exp_obs <- d_child_copy[d_child_copy[["group"]] == "EXPOSED" & d_child_copy[[outcome_obs_col]] == TRUE]
  d_con_obs <- d_child_copy[d_child_copy[["group"]] == "CONTROL" & d_child_copy[[outcome_obs_col]] == TRUE]

  count_exp_no_outcome <- sum(d_exp_obs[[reason_col]] == "age_8_years_old", na.rm = TRUE)
  count_con_no_outcome <- sum(d_con_obs[[reason_col]] == "age_8_years_old", na.rm = TRUE)
  add_row("   Reached 8 years of age, no outcome", count_exp_no_outcome, count_con_no_outcome)

  # Outcome section
  col1 <- c(col1, "   Outcome")
  col2_overall_n <- c(col2_overall_n, "")
  col2_overall_pct <- c(col2_overall_pct, "")
  col3_exposed_n <- c(col3_exposed_n, "")
  col3_exposed_pct <- c(col3_exposed_pct, "")
  col4_control_n <- c(col4_control_n, "")
  col4_control_pct <- c(col4_control_pct, "")

  # Add outcome rows
  outcome_reasons <- c("major_congenital_malformation", "death_child", "diagnosis_autism", "diagnosis_adhd")
  outcome_labels_full <- c(
    "Major congenital malformation",
    "Death of offspring after birth",
    "Autism diagnosis",
    "ADHD diagnosis"
  )

  for (i in seq_along(outcome_reasons)) {
    count_exp <- sum(d_exp_obs[[reason_col]] == outcome_reasons[i], na.rm = TRUE)
    count_con <- sum(d_con_obs[[reason_col]] == outcome_reasons[i], na.rm = TRUE)
    add_row(paste0("      ", outcome_labels_full[i]), count_exp, count_con)
  }

  # Create output data.table
  df <- data.table::data.table(
    label = col1,
    overall_count = col2_overall_n,
    overall_pct = col2_overall_pct,
    exposed_count = col3_exposed_n,
    exposed_pct = col3_exposed_pct,
    control_count = col4_control_n,
    control_pct = col4_control_pct
  )

  return(df)
}

#' This function generates a summary table for follow-up time, intercurrent
#' events, reasons for end of follow-up, and censoring for a single group
#' within a given dataset.
#'
#' It computes descriptive statistics for follow-up time, including median,
#' interquartile range (Q1, Q3), minimum, and maximum. It also summarizes
#' intercurrent events, end-of-follow-up outcomes, and censoring reasons as
#' counts and percentages relative to the total number of observations.
#'
#' Intercurrent events are identified based on non-missing values in the
#' specified columns.
#' End-of-follow-up and censoring categories are defined provided values,
#' allowing for flexible grouping of categories (e.g., combining multiple
#' reasons into a single row).
#'
#' Optionally, the function can also calculate follow-up summary statistics
#' separately for each censoring category. When `cens_fup = TRUE`,
#' median, Q1, Q3, minimum, and maximum follow-up times are displayed
#' below each censoring reason in the output table.
#'
#' Results are returned as a three-column table suitable for reporting (
#' according to the table shells).
#'
#' @param d A data frame or data.table containing patient-level data.
#' @param fup_time Character string specifying the column name for follow-up time.
#' @param reas_cens Character string specifying the column name indicating
#'   reason for end of follow-up or censoring.
#' @param header Character string used as the column header (e.g., group name).
#' @param ie_vars Character vector of column names indicating intercurrent
#'   events (non-missing values are counted as events).
#' @param ie_labels Character vector of labels corresponding to `ie_vars`.
#' @param eof_vars List of character vectors specifying values in
#'   `reas_cens` that define each end-of-follow-up category. Each element
#'   can contain one or more values.
#' @param eof_labels Character vector of labels corresponding to `eof_vars`.
#' @param cens_vars List of character vectors specifying values in
#'   `reas_cens` that define each censoring category. Each element can
#'   contain one or more values.
#' @param cens_labels Character vector of labels corresponding to
#'   `cens_vars`.
#' @param row_structure A vector with the order each section should be added
#' in the table. The default order is "header", "fup", "ie", "eof", "cens".
#' @param section_labels A list with the labels referring to each section
#' of the table that was added in row_structure. The default labels are:
#' fup  = "Person-months of follow-up",
#' ie   = "Occurrence of Intercurrent Events during follow-up, n (%)",
#' eof  = "Reason for end of follow-up, n (%)",
#' cens = "Reason for censoring, n (%)"
#' @param cens_fup If the summary statistics for each fup reason
#' need to be calculated (default FALSE)
#' @param n_dec Integer specifying the number of decimal places for rounding
#'   numeric outputs (default = 2).
#'
#' @examples
#' fup_ie_cens_tab(
#'   d,
#'   fup_time = "fup_length_months_1_3",
#'   reas_cens = "reason_censoring_1_3",
#'   header = "Overall",
#'   ie_vars = c("treat_disc_d", "partial_disc_d"),
#'   ie_labels = c("Treatment discontinuation", "Partial discontinuation"),
#'   eof_vars = list("disease_progression_d", "death_d"),
#'   eof_labels = c("Disease progression", "Death"),
#'   cens_vars = list(
#'     c("end_observation_data_d", "end_study_period"),
#'     "end_spell"
#'   ),
#'   cens_labels = c("Administrative censoring", "Disenrollment"),
#'   cens_fup = TRUE
#' )
#'
fup_ie_cens_tab <- function(d,
                            fup_time,
                            reas_cens,
                            header,
                            ie_vars,
                            ie_labels,
                            eof_vars,
                            eof_labels,
                            cens_vars,
                            cens_labels,
                            row_structure = c("header", "fup", "ie", "eof", "cens"),
                            section_labels = list(
                              fup  = "Person-months of follow-up",
                              ie   = "Occurrence of Intercurrent Events during follow-up, n (%)",
                              eof  = "Reason for end of follow-up, n (%)",
                              cens = "Reason for censoring, n (%)"
                            ),
                            cens_fup = FALSE,
                            n_dec = 2) {
  ## ---- Input validation ----
  # If the lenggth of the variables does not match the length of labels, stops
  if (length(ie_vars) != length(ie_labels)) {
    stop("ie_vars and ie_labels must have the same length")
  }

  if (length(eof_vars) != length(eof_labels)) {
    stop("eof_vars and eof_labels must have the same length")
  }

  if (length(cens_vars) != length(cens_labels)) {
    stop("cens_vars and cens_labels must have the same length")
  }

  # if thefup time vector is not part of the d
  if (!fup_time %in% names(d)) {
    stop("fup_time not found in d")
  }
  # same for reasons vector
  if (!reas_cens %in% names(d)) {
    stop("reas_cens not found in d")
  }
  # if the IE events columns are not part of d, stops
  if (!all(ie_vars %in% names(d))) {
    stop("Some ie_vars not found in d")
  }

  ## Extract the vectors
  fup_vec <- d[[fup_time]]
  cens_vec <- d[[reas_cens]]

  ## Check if the end of follow up/censoring reasons exist in the cens_vec
  if (!all(unlist(eof_vars) %in% unique(cens_vec))) {
    warning("Some eof_vars values not found in reas_cens")
  }

  if (!all(unlist(cens_vars) %in% unique(cens_vec))) {
    warning("Some cens_vars values not found in reas_cens")
  }

  ## Total rows, to be used as denominator
  n_total <- nrow(d)

  if (n_total == 0) warning("Dataset has zero rows")

  ## Person-months of follow up
  if (any(is.na(fup_vec))) {
    warning("Missing values in the follow-up vector")
  }

  # Calculate the summary statistics for persons-months of fup
  fup_stats <- summ_fun(fup_vec, n_dec)

  ## ---- Intercurrent events ----
  n_ie <- vapply(ie_vars, function(v) sum(!is.na(d[[v]])), numeric(1))
  p_ie <- round(100 * n_ie / n_total, n_dec)

  ## ---- Reasons for end of follow-up ----
  n_eof <- vapply(eof_vars, function(v) sum(cens_vec %in% v, na.rm = TRUE), numeric(1))
  p_eof <- round(100 * n_eof / n_total, n_dec)

  ## ---- Create output columns ----
  ie_col1 <- paste0("   ", ie_labels)
  ie_col2 <- as.character(n_ie)
  ie_col3 <- paste0(p_ie, "%")

  eof_col1 <- paste0("   ", eof_labels)
  eof_col2 <- as.character(n_eof)
  eof_col3 <- paste0(p_eof, "%")

  ## ---- Final table ----
  col1 <- c()
  col2 <- c()
  col3 <- c()

  for (section in row_structure) {
    if (section == "header") {
      col1 <- c(col1, "")
      col2 <- c(col2, paste0(header, " (N = ", n_total, ")"))
      col3 <- c(col3, "")
    }
    if (section == "fup") {
      col1 <- c(
        col1,
        section_labels$fup,
        "   Median (Q1, Q3)",
        "   Min, max"
      )

      col2 <- c(
        col2,
        "",
        as.character(fup_stats["med"]),
        as.character(fup_stats["min"])
      )

      col3 <- c(
        col3,
        "",
        paste0("(", fup_stats["q1"], ", ", fup_stats["q3"], ")"),
        as.character(fup_stats["max"])
      )
    }
    # if there is a section ie in the row structure
    if (section == "ie") {
      col1 <- c(
        col1,
        section_labels$ie
      )

      col2 <- c(
        col2,
        ""
      )

      col3 <- c(
        col3,
        ""
      )

      # for each intercurrent event calculate n, p, and follow-up statistics
      for (i in seq_along(ie_vars)) {
        # IE occurs when the variable is non-NA
        idx <- !is.na(d[[ie_vars[i]]])

        col1 <- c(col1, paste0("   ", ie_labels[i]))
        col2 <- c(col2, ie_col2[i])
        col3 <- c(col3, ie_col3[i])

        # Always add follow-up statistics rows for this IE
        fup_i <- if (sum(idx, na.rm = TRUE) > 0) summ_fun(fup_vec[idx], n_dec) else NULL

        col1 <- c(
          col1,
          "      Median (Q1, Q3)",
          "      Min, max"
        )

        if (!is.null(fup_i) && is.finite(fup_i["med"]) && is.finite(fup_i["min"])) {
          col2 <- c(
            col2,
            as.character(fup_i["med"]),
            as.character(fup_i["min"])
          )

          col3 <- c(
            col3,
            paste0("(", fup_i["q1"], ", ", fup_i["q3"], ")"),
            as.character(fup_i["max"])
          )
        } else {
          col2 <- c(col2, "", "")
          col3 <- c(col3, "", "")
        }
      }
    }
    # if there is a section eof in the row structure
    if (section == "eof") {
      col1 <- c(
        col1,
        section_labels$eof,
        eof_col1
      )

      col2 <- c(
        col2,
        "",
        eof_col2
      )

      col3 <- c(
        col3,
        "",
        eof_col3
      )
    }
    # if there is a section cens in the row structure
    if (section == "cens") {
      col1 <- c(col1, section_labels$cens)
      col2 <- c(col2, "")
      col3 <- c(col3, "")

      # for each censoring reason calculate n and p
      for (i in seq_along(cens_vars)) {
        idx <- cens_vec %in% cens_vars[[i]]

        n_i <- sum(idx, na.rm = TRUE)
        p_i <- round(100 * n_i / n_total, n_dec)

        col1 <- c(col1, paste0("   ", cens_labels[i]))
        col2 <- c(col2, as.character(n_i))
        col3 <- c(col3, paste0(p_i, "%"))

        # if it was specified in the argument
        if (cens_fup) { # calculate fup for each censoring reason

          # apply the summary statistics function for groups
          fup_i <- summ_fun_by_group(fup_vec, cens_vec, cens_vars[[i]], n_dec)

          col1 <- c(
            col1,
            "      Median (Q1, Q3)",
            "      Min, max"
          )

          if (!is.null(fup_i) && is.finite(fup_i["med"]) && is.finite(fup_i["min"])) {
            col2 <- c(
              col2,
              as.character(fup_i["med"]),
              as.character(fup_i["min"])
            )

            col3 <- c(
              col3,
              paste0("(", fup_i["q1"], ", ", fup_i["q3"], ")"),
              as.character(fup_i["max"])
            )
          } else {
            col2 <- c(col2, "", "")
            col3 <- c(col3, "", "")
          }
        }
      }
    }
  }

  df <- data.frame(
    col1 = col1,
    col2 = col2,
    col3 = col3,
    stringsAsFactors = FALSE
  )

  return(df)
}

#' Create summary statistisc for a numeric vector
#'
#' This function computes descriptive summary statistics of a
#' numeric vector. It returns the median, IQR (q1, q3) min and
#' max.
#' The missing values are ignored in all calculations.
#' The numbers are rounded to 2 decimal points by default.
#' The formatting was avoided in purpose, and the user
#' can further wrangle the output in any desired way.
#' This function helps to avoid repeating these
#' calculations.
#' @param x A numeric vector for which summary statistics
#' will be calculated
#' @param n_dec Integer number of the decimals for rounding
summ_fun <- function(x, n_dec = 2) {
  x <- as.numeric(x)

  stats <- c(
    med = median(x, na.rm = TRUE),
    q1  = unname(quantile(x, 0.25, na.rm = TRUE)),
    q3  = unname(quantile(x, 0.75, na.rm = TRUE)),
    min = min(x, na.rm = TRUE),
    max = max(x, na.rm = TRUE)
  )

  round(stats, n_dec)
}

#' Create summary statistics for a numeric vector within groups.
#'
#' This function computes descriptive summary statistics for a subset of a
#' numeric vector defined by one or more grouping values.
#'
#' The function uses `summ_fun()` internally to calculate the median,
#' quartiles (Q1, Q3), minimum, and maximum for the selected subset.
#'
#' If no observations match the specified grouping values, the function
#' returns NULL.
#'
#' @param num_vec A numeric vector for which summary statistics will be
#'   calculated.
#' @param group_vec A vector defining the grouping variable.
#' @param group_values A vector of values in `group_vec` used to define
#'   the subset of observations included in the summary calculations.
#' @param n_dec Integer specifying the number of decimal places used for
#'   rounding the output. Default is 2.
summ_fun_by_group <- function(num_vec,
                              group_vec,
                              group_values,
                              n_dec = 2) {
  idx <- group_vec %in% group_values
  if (!any(idx, na.rm = TRUE)) {
    return(NULL)
  }
  summ_fun(num_vec[idx], n_dec)
}

#' This function generates a summary table for follow-up time, intercurrent
#' events, reasons for end of follow-up, and censoring for a single group
#' within a given dataset.
#'
#' It computes descriptive statistics for follow-up time, including median,
#' interquartile range (Q1, Q3), minimum, and maximum. It also summarizes
#' intercurrent events, end-of-follow-up outcomes, and censoring reasons as
#' counts and percentages relative to the total number of observations.
#'
#' Intercurrent events are identified based on non-missing values in the
#' specified columns.
#' End-of-follow-up and censoring categories are defined provided values,
#' allowing for flexible grouping of categories (e.g., combining multiple
#' reasons into a single row).
#'
#' Optionally, the function can also calculate follow-up summary statistics
#' separately for each censoring category. When `cens_fup = TRUE`,
#' median, Q1, Q3, minimum, and maximum follow-up times are displayed
#' below each censoring reason in the output table.
#'
#' Results are returned as a three-column table suitable for reporting (
#' according to the table shells).
#'
#' @param d A data frame or data.table containing patient-level data.
#' @param fup_time Character string specifying the column name for follow-up time.
#' @param reas_cens Character string specifying the column name indicating
#'   reason for end of follow-up or censoring.
#' @param header Character string used as the column header (e.g., group name).
#' @param ie_vars Character vector of column names indicating intercurrent
#'   events (non-missing values are counted as events).
#' @param ie_labels Character vector of labels corresponding to `ie_vars`.
#' @param eof_vars List of character vectors specifying values in
#'   `reas_cens` that define each end-of-follow-up category. Each element
#'   can contain one or more values.
#' @param eof_labels Character vector of labels corresponding to `eof_vars`.
#' @param cens_vars List of character vectors specifying values in
#'   `reas_cens` that define each censoring category. Each element can
#'   contain one or more values.
#' @param cens_labels Character vector of labels corresponding to
#'   `cens_vars`.
#' @param row_structure A vector with the order each section should be added
#' in the table. The default order is "header", "fup", "ie", "eof", "cens".
#' @param section_labels A list with the labels referring to each section
#' of the table that was added in row_structure. The default labels are:
#' fup  = "Person-months of follow-up",
#' ie   = "Occurrence of Intercurrent Events during follow-up, n (%)",
#' eof  = "Reason for end of follow-up, n (%)",
#' cens = "Reason for censoring, n (%)"
#' @param cens_fup If the summary statistics for each fup reason
#' need to be calculated (default FALSE)
#' @param n_dec Integer specifying the number of decimal places for rounding
#'   numeric outputs (default = 2).
#'
#' @examples
#' fup_ie_cens_tab(
#'   d,
#'   fup_time = "fup_length_months_1_3",
#'   reas_cens = "reason_censoring_1_3",
#'   header = "Overall",
#'   ie_vars = c("treat_disc_d", "partial_disc_d"),
#'   ie_labels = c("Treatment discontinuation", "Partial discontinuation"),
#'   eof_vars = list("disease_progression_d", "death_d"),
#'   eof_labels = c("Disease progression", "Death"),
#'   cens_vars = list(
#'     c("end_observation_data_d", "end_study_period"),
#'     "end_spell"
#'   ),
#'   cens_labels = c("Administrative censoring", "Disenrollment"),
#'   cens_fup = TRUE
#' )
#'
# ----------------------------
# HELPER FUNCTIONS
# ----------------------------
prepare_ie_vars <- function(d, ie_vars) {
  d_out <- data.table::as.data.table(d)
  ie_vars_out <- ie_vars

  for (i in seq_along(ie_vars)) {
    v <- ie_vars[i]

    if (!v %in% names(d_out)) {
      stop("IE variable not found in data: ", v)
    }

    if (is.logical(d_out[[v]])) {
      v_new <- paste0(v, "__ie")
      d_out[[v_new]] <- ifelse(d_out[[v]] %in% TRUE, 1, NA_real_)
      ie_vars_out[i] <- v_new
    } else if (inherits(d_out[[v]], "Date")) {
      v_new <- paste0(v, "__ie")
      d_out[[v_new]] <- ifelse(!is.na(d_out[[v]]), 1, NA_real_)
      ie_vars_out[i] <- v_new
    }
  }

  list(
    data = d_out,
    ie_vars = ie_vars_out
  )
}

build_fup_table <- function(d,
                            estimand,
                            estimand_label,
                            ie_vars,
                            ie_labels,
                            cens_vars,
                            cens_labels,
                            include_ie = TRUE) {
  d_ie <- prepare_ie_vars(d, ie_vars)

  # Set row_structure based on include_ie
  row_structure <- if (include_ie) {
    c("header", "fup", "ie", "cens")
  } else {
    c("header", "fup", "cens")
  }

  make_table <- function(df) {
    fup_ie_cens_tab(df,
      fup_time = paste0("fup_length_days_estimand", estimand),
      reas_cens = paste0("reason_endfup_estimand", estimand),
      header = estimand_label,
      ie_vars = if (include_ie) d_ie$ie_vars else character(0),
      ie_labels = if (include_ie) ie_labels else character(0),
      eof_vars = list(),
      eof_labels = c(),
      cens_vars = cens_vars,
      cens_labels = cens_labels,
      row_structure = row_structure,
      section_labels = list(
        fup = "Person-months of follow-up",
        ie = "Occurrence of Intercurrent Events during follow-up, n (%)",
        cens = "Reasons for end of follow-up (counting only first occurrence) *"
      ),
      cens_fup = TRUE
    )
  }

  fup_table_overall <- make_table(d_ie$data)
  fup_table_exp <- make_table(d_ie$data[d_ie$data$group == "EXPOSED", ])
  fup_table_con <- make_table(d_ie$data[d_ie$data$group == "CONTROL", ])

  fup_table <- cbind(fup_table_overall, fup_table_exp[, -1], fup_table_con[, -1])
  names(fup_table) <- c(
    "label",
    "overall_col1", "overall_col2",
    "exposed_col1", "exposed_col2",
    "control_col1", "control_col2"
  )

  fup_table
}
