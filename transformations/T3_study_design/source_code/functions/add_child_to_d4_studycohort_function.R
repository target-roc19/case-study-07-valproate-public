#' Add child to D4 study cohort
#' This function adds the earliest conception date and first date of birth to the D4 study cohort by merging
#' with the D3 father-child dataset. It also creates two new variables: "conception_within_3_years" and "livebirth_within_3_years_9_months".
#' @param d4_studycohort A data.table containing the D4 study cohort.
#' @param d3_father_child A data.table containing the D3 father-child dataset.
#' @return A data.table containing the updated D4 study cohort with the new variables.
#'
add_child_to_d4_studycohort <- function(d4_studycohort, d3_father_child) {
  # 1) Add variable "earliest_conception_date" to d4_studycohort by merging with
  # D3_FatherChild to get the earliest estimated conception date for each
  # person_id.

  logger::log_info("Adding variable 'earliest_conception_date' to d4_studycohort by merging with D3_FatherChild")

  # Keep only records with a conception date
  d3_father_child <- d3_father_child[!is.na(estimated_conception_date)]

  # Convert variables from Date format to IDate
  variable_types <- lapply(d3_father_child, class)
  for (var_name in names(variable_types)) {
    if ("Date" %in% variable_types[[var_name]]) {
      logger::log_info(paste("Converting variable", var_name, "from Date to IDate format"))
      d3_father_child[, (var_name) := as.IDate(get(var_name))]
    }
  }

  # Match conception dates that fall within [T0, Inf+) and aggregate only true matches.
  matched_conceptions <- d3_father_child[
    d4_studycohort,
    on = .(
      father_id = person_id,
      estimated_conception_date >= T0
    ),
    nomatch = 0L,
    allow.cartesian = TRUE,
    .(
      person_id = i.person_id,
      T0 = i.T0,
      estimated_conception_date = x.estimated_conception_date,
      date_of_birth = x.date_of_birth
    )
  ]

  earliest_conceptions <- matched_conceptions[
    ,
    .(
      # As earliest_conception_date, we want the earliest estimated conception
      # date for each person_id and T0
      earliest_conception_date = {
        # If there is a valid date_of_birth, we want the estimated_conception_date
        # that corresponds to the earliest date_of_birth.
        has_valid_birth <- any(!is.na(date_of_birth))
        if (has_valid_birth) {
          non_missing_birth_idx <- which(!is.na(date_of_birth))
          earliest_birth_idx <- non_missing_birth_idx[which.min(date_of_birth[non_missing_birth_idx])]
          estimated_conception_date[earliest_birth_idx]
        } else {
          # If there is no valid date_of_birth, we want the earliest
          # estimated_conception_date.
          min(estimated_conception_date, na.rm = TRUE)
        }
      },
      first_date_of_birth =
        if (any(!is.na(date_of_birth))) min(date_of_birth, na.rm = TRUE) else as.IDate(NA)
    ),
    by = .(person_id, T0)
  ]

  rm(matched_conceptions)

  # Add earliest_conception_date to d4_studycohort by merging with earliest_conceptions
  d4_studycohort <- data.table::merge.data.table(
    d4_studycohort,
    earliest_conceptions,
    by = c("person_id", "T0"),
    all.x = TRUE
  )

  # 2) Create variable "conception_within_3_years" based on whether the earliest
  # conception date is within 3 years after T0
  logger::log_info("Creating variable 'conception_within_3_years' based on earliest conception date and T0")
  d4_studycohort[, conception_within_3_years :=
    !is.na(earliest_conception_date) &
      earliest_conception_date <= (T0 + lubridate::years(3))]

  # 3) Create variable "livebirth_within_3_years_9_months" based on whether the first
  # date of birth is within 3.75 years after T0 and the earliest conception date
  # is within 3 years after T0
  logger::log_info("Creating variable 'livebirth_within_3_years_9_months' based on first date of birth and earliest conception date")
  d4_studycohort[, livebirth_within_3_years_9_months :=
    !is.na(first_date_of_birth) &
      first_date_of_birth <= (T0 + lubridate::period(years = 3, months = 9)) &
      conception_within_3_years]

  return(d4_studycohort)
}
