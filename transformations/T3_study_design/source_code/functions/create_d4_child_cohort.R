#' Create child cohort: D4_StudyCohort_Child (children-trial units)
#' This function creates the child cohort (D4_StudyCohort_Child) by merging the
#' D4 study cohort with the D3_FatherChild dataset. The child cohort includes only the offspring of fathers with a conception within 3 years after T0.
#' Importantly, this cohort includes the linkage between child, father and mother id
#' 
#' @param d4_studycohort A data.table containing the D4 study cohort
#' @param d3_father_child A data.table containing the D3_FatherChild dataset
#' @return A data.table containing the D4_StudyCohort_Child
create_d4_child_cohort <- function(d4_studycohort, d3_father_child) {
  # In the child cohort, we only want the offspring of fathers with a conception within 3 years after T0. Therefore, we will filter the child cohort to include only those fathers.
  d4_studycohort <- d4_studycohort[conception_within_3_years == TRUE]

  # Remove variables that are not needed in the child cohort
  d4_studycohort[, c("first_date_of_birth", "conception_within_3_years", "livebirth_within_3_years_9_months") := NULL]

  # 3) Create child cohort: D4_StudyCohort_Child (children-trial units)
  logger::log_info("Creating child cohort: D4_StudyCohortChild (children-trial units)")

  # Person id is renamed to father id
  d4_studycohort_child <- data.table::merge.data.table(
    x = d3_father_child,
    y = d4_studycohort,
    by.x = c("father_id", "estimated_conception_date"),
    by.y = c("person_id", "earliest_conception_date"),
    all.x = FALSE,
    all.y = TRUE,
    allow.cartesian = TRUE
  )


  # D4 studycohort child will contains all colums in D3 (father id, child id, date of birth, mother id, pregnancy id and estimated conception date)
  # as well as the previous d4_studycohort info (the one not removed)
  # using those names, but each row will consist of every father-trial unit (father-T0 combination),
  # and there will be multiple rows per father trial unit if the father has multiple children at a given point

  return(d4_studycohort_child)
}
