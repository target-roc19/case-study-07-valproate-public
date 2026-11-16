################################################################
# fn_attrition_tables ---
# Aim:
# Build attrition tables for D3 eligibility and matched D4 cohorts.
#
# Tables:
# - Table 1: entry into eligible population
################################################################

# Convert common encodings to logical without changing source data.
.as_logical <- function(x) {
  # Keep logical vectors unchanged.
  if (is.logical(x)) {
    return(x)
  }
  # Treat non-zero numeric/integer values as TRUE.
  if (is.numeric(x) || is.integer(x)) {
    return(x != 0)
  }
  # Normalize common string representations used in extracts.
  if (is.character(x)) {
    x_up <- toupper(trimws(x))
    return(x_up %in% c("TRUE", "T", "1", "YES", "Y"))
  }
  # Fallback for other classes.
  as.logical(x)
}

.assert_required_cols <- function(dt, required_cols, table_name) {
  # Fail early with a clear message when expected input fields are absent.
  missing_cols <- setdiff(required_cols, names(dt))
  if (length(missing_cols) > 0) {
    stop(
      sprintf(
        "%s is missing required columns: %s",
        table_name,
        paste(missing_cols, collapse = ", ")
      )
    )
  }
}

.pct <- function(numerator, denominator, digits = 1) {
  # Return blank-compatible NA when denominator is undefined or zero.
  if (is.na(denominator) || denominator == 0) {
    return(NA_character_)
  }
  format(round((numerator / denominator) * 100, digits), nsmall = digits)
}

.format_count <- function(x) {
  # Keep counts as character so output tables are report-ready on write.
  if (is.na(x)) {
    return(NA_character_)
  }
  format(x, scientific = FALSE, trim = TRUE)
}

.finalize_attrition_table <- function(dt, return_na = FALSE) {
  out <- data.table::copy(dt)
  if (!return_na) {
    # Replace missing display cells with empty strings for final CSV shells.
    out[is.na(N), N := ""]
    out[is.na(Percentage), Percentage := ""]
    out[is.na(Aux), Aux := ""]
  }
  out[]
}



#' Table 1: Attrition table for entry into the eligible population.
#'
#' @param d3_eligibility D3 eligibility dataset.
#' @param digits Number of decimals for percentages.
#' @param return_na Keep NA values if TRUE; otherwise replace with empty strings.
#'
#' @return data.table with columns Label, N, Percentage, Aux.
create_attrition_table <- function(d3_eligibility, digits = 1, return_na = FALSE) {
  
  # Work on a copy to avoid modifying upstream objects by reference.
  dt <- data.table::as.data.table(data.table::copy(d3_eligibility))

  .assert_required_cols(
    dt,
    c(
      "person_id", "start", "end", "in_study_period", "SV_ENROLLED_12M",
      "SV_IS_ON_OT_ASM", "SV_IS_ON_VPA", "SV_IS_ON_LEV", 
      "receives_exposure", "receives_control",
      "SV_AGE_BETWEEN_18_50", "SV_SEX",
      "SV_GENEPILEPSY", "SV_CONTRA_VALPROATE",
      "SV_INFERTILITY", "in_eligible_pop", 
      "eligible_exposed", "eligible_control",
      "conception_within_3_years", "first_date_of_birth",
      "n_pregnancies", "n_infants"
    ),
    "d3_eligibility"
  )

  # Harmonize all logical flags used in shell criteria and totals.
  dt[, in_study_period := .as_logical(in_study_period)]
  dt[, SV_ENROLLED_12M := .as_logical(SV_ENROLLED_12M)]
  dt[, SV_IS_ON_OT_ASM := .as_logical(SV_IS_ON_OT_ASM)]
  dt[, SV_IS_ON_VPA := .as_logical(SV_IS_ON_VPA)]
  dt[, SV_IS_ON_LEV := .as_logical(SV_IS_ON_LEV)]
  dt[, receives_exposure := .as_logical(receives_exposure)]
  dt[, receives_control := .as_logical(receives_control)]
  dt[, SV_AGE_BETWEEN_18_50 := .as_logical(SV_AGE_BETWEEN_18_50)]
  dt[, SV_SEX := .as_logical(SV_SEX)]
  dt[, SV_GENEPILEPSY := .as_logical(SV_GENEPILEPSY)]
  dt[, SV_CONTRA_VALPROATE := .as_logical(SV_CONTRA_VALPROATE)]
  dt[, SV_INFERTILITY := .as_logical(SV_INFERTILITY)]
  dt[, in_eligible_pop := .as_logical(in_eligible_pop)]
  dt[, eligible_exposed := .as_logical(eligible_exposed)]
  dt[, eligible_control := .as_logical(eligible_control)]


  ########### Starts computation of table shells ##################

  # Unique people in the base source population (n_original_cohort)
  n_original_cohort <- dt[, data.table::uniqueN(person_id)]

  # Unique individuals exposed to valproate or levetiracetam
  n_original_cohort_2 <- dt[(SV_IS_ON_VPA == TRUE | SV_IS_ON_LEV == TRUE) & SV_SEX == TRUE & SV_AGE_BETWEEN_18_50 == TRUE & in_study_period == TRUE, data.table::uniqueN(person_id)]


  if (n_original_cohort_2 != n_original_cohort) {
    logger::log_warn(
      paste0(
        "The total number of unique individuals in the source population (n = ", n_original_cohort, ") differs from the count of unique individuals exposed to valproate or levetiracetam, males and with age 18 to 50 (n = ", n_original_cohort_2, "). ",
        "This discrepancy may indicate that there are individuals in the source population who were never exposed to valproate or levetiracetam, or that there are issues with the exposure variable coding. ",
        "Please investigate the source data and variable definitions to understand the reason for this difference."
      )
    )
  }
  # Unique individuals exposed only to levetiracetam or valproate (n)
  n <- dt[(receives_exposure == TRUE | receives_control == TRUE) & SV_SEX == TRUE & SV_AGE_BETWEEN_18_50 == TRUE & in_study_period == TRUE, data.table::uniqueN(person_id)]


  dt.exposed <- dt[(receives_exposure == TRUE | receives_control == TRUE) & SV_SEX == TRUE & SV_AGE_BETWEEN_18_50 == TRUE & in_study_period == TRUE, ]

  ### Apply inclusion criteria
  n1a <- dt.exposed[SV_GENEPILEPSY == TRUE, data.table::uniqueN(person_id)] 
  n1b <- dt.exposed[SV_GENEPILEPSY == TRUE & SV_CONTRA_VALPROATE == FALSE, data.table::uniqueN(person_id)] 
  n1c <- dt.exposed[SV_GENEPILEPSY == TRUE & SV_CONTRA_VALPROATE == FALSE & SV_INFERTILITY == FALSE, data.table::uniqueN(person_id)] 
  n1d <- dt.exposed[SV_GENEPILEPSY == TRUE & SV_CONTRA_VALPROATE == FALSE & SV_INFERTILITY == FALSE & SV_ENROLLED_12M == TRUE, data.table::uniqueN(person_id)]

  ## Total eligible cohort
  n_cohort <- dt.exposed[in_eligible_pop == TRUE, data.table::uniqueN(person_id)] # Final eligible population after applying all criteria.
  n_cohort_2 <- dt.exposed[SV_GENEPILEPSY == TRUE & SV_CONTRA_VALPROATE == FALSE & SV_INFERTILITY == FALSE & SV_ENROLLED_12M == TRUE & in_study_period == TRUE, data.table::uniqueN(person_id)] # Eligible population count based on individual criteria flags.

  if (n_cohort != n_cohort_2) {
    logger::log_warn(
      paste0(
        "The total number of eligible individuals (n = ", n_cohort, ") differs from the count of unique individuals who meet all individual eligibility criteria flags (n = ", n_cohort_2, "). ",
        'Please check source of discrepancy'
      )
    )
  } else {
    logger::log_info(
      paste0(
        "The total number of eligible individuals (n = ", n_cohort, ") matches the count of unique individuals who meet all individual eligibility criteria flags (n = ", n_cohort_2, ")."
      )
    )
  }

  # Number of eligible cohort who also have a livebirth (at any point after eligibility)
  n2 <- dt.exposed[
    in_eligible_pop &
      !is.na(first_date_of_birth),
    data.table::uniqueN(person_id)
  ]

  n2_livebirth_within_3y <- dt.exposed[
    in_eligible_pop &
      conception_within_3_years == TRUE,
    data.table::uniqueN(person_id)
  ]

  n_exp <- dt.exposed[eligible_exposed == TRUE,
    data.table::uniqueN(person_id)
  ]

  n_exp_livebirth <- dt.exposed[
          eligible_exposed == TRUE &
      !is.na(first_date_of_birth),
    data.table::uniqueN(person_id)
  ]
  
  n_exp_livebirth_within_3y <- dt.exposed[
    eligible_exposed == TRUE &
      conception_within_3_years == TRUE,
    data.table::uniqueN(person_id)
  ]

  n_control <- dt.exposed[
    eligible_control == TRUE,
    data.table::uniqueN(person_id)
  ]

  n_control_livebirth <- dt.exposed[
    eligible_control == TRUE &
      !is.na(first_date_of_birth),
    data.table::uniqueN(person_id)
  ]

  n_control_livebirth_within_3y <- dt.exposed[
    eligible_control == TRUE &
      conception_within_3_years == TRUE,
    data.table::uniqueN(person_id)
  ]

  # Extract is of individuals who are exposed and have a livebirth with conception date within 3 years of eligible exposure
  ids_exp_livebirth_within_3y <- dt.exposed[
    eligible_exposed == TRUE &
      conception_within_3_years == TRUE,
    base::unique(person_id)
  ]
  # Same for control
  ids_control_livebirth_within_3y <- dt.exposed[
    eligible_control == TRUE &
      conception_within_3_years == TRUE,
    base::unique(person_id)
  ]
  
  # Check for overlap between exposed and control groups with livebirth within 3 years
  overlap_ids <- base::intersect(ids_exp_livebirth_within_3y, ids_control_livebirth_within_3y)

  total_overlap <- length(overlap_ids)


  # Build shell-aligned row labels and values in final reporting order.
  table_1a <- data.table::data.table(
    Label = c(
      "All individuals registered in the healthcare data source at any time between 1st of January 2010 and 31st of March 2016 AND received valproate or levetiracetam during the enrolment period 1st January 2010 – 30th March 2016 AND Males AND Age >= 18 and <=50",
      "All individuals registered in the healthcare data source at any time between 1st of January 2010 and 31st of March 2016 AND received valproate or levetiracetam and not any other antiseizure drug at the same time during the enrolment period 1st January 2010 – 30th March 2016 AND Males AND Age >= 18 and <=50",
      "AND Ongoing generalised epilepsy",
      "AND not contraindication for valproate/levetiracetam",
      "AND not infertile",
      "AND have a 12-month lookback period available",
      "Total Eligible Cohort",
      "AND have a livebirth*",
      "AND have a livebirth with conception date within 3 years of eligible exposure",
      "Eligible Exposed",
      "AND have a livebirth*",
      "AND have a livebirth with conception date within 3 years of eligible exposure",
      "Eligible Control",
      "AND have a livebirth*",
      "AND have a livebirth with conception date within 3 years of eligible exposure"
    ),
    N = c(
      .format_count(n_original_cohort_2), # Row 1 count.
      .format_count(n), # Row 2 count.
      .format_count(n1a), # Row 3 count.
      .format_count(n1b), # Row 4 count.
      .format_count(n1c), # Row 5 count.
      .format_count(n1d), # Row 6 count.
      .format_count(n_cohort), # Row 7 count.
      .format_count(n2), # Row 8 count.
      .format_count(n2_livebirth_within_3y),
      .format_count(n_exp), # Row 9 count.
      .format_count(n_exp_livebirth), # Row 10 count.
      .format_count(n_exp_livebirth_within_3y),
      .format_count(n_control), # Row 11 count.
      .format_count(n_control_livebirth), # Row 12 count.
      .format_count(n_control_livebirth_within_3y)
    ),
    Percentage = c(
      # Percentages follow shell denominators:
      NA_character_, # Row 1 percentage intentionally blank.
      .pct(n, n_original_cohort_2), 
      .pct(n1a, n), # Row 2: n_e1 / n.
      .pct(n1b, n),
      .pct(n1c, n),
      .pct(n1d, n),
      .pct(n_cohort, n),
      .pct(n2, n_cohort),
      .pct(n2_livebirth_within_3y, n_cohort),
      .pct(n_exp, n_cohort),
      .pct(n_exp_livebirth, n_exp),
      .pct(n_exp_livebirth_within_3y, n_exp),
      .pct(n_control, n_cohort),
      .pct(n_control_livebirth, n_control),
      .pct(n_control_livebirth_within_3y, n_control)
    ),
    Aux = NA_character_
  )
  table_1a <- .finalize_attrition_table(table_1a, return_na = return_na)

  output <- list(table_1a = table_1a, total_overlap = total_overlap, overlap_ids = overlap_ids)
  return(output)
}
