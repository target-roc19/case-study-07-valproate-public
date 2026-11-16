#' Compute diagnostics for BMI based on d4_cohort
#'
#' Inputs d4_cohort and computes (overall and per exposed group):
#' - Percentage of individuals with at least one missing value in SV_BMI
#' - Median and interquartile range (Q1-Q3) of observed SV_BMI values at the earliest point
#'
#' The function is simple and unlikely to be reused, so the name of the variable (SV_BMI) is hardcoded.
#'
#' @param d4_cohort Data table containing cohort (person-trial) information, including SV_BMI and group indicators.
#'
#' @param digits Number of decimal places to round the results to.
#' @return Simple table storing percentage of individuals with one or more missing values in SV_BMI, and median and interquartile range of observed SV_BMI values, overall and by exposed group.

compute_bmi_diagnostics <- function(d4_cohort, digits = 1) {
  n_overall <- d4_cohort[, .N]
  n_exposed <- d4_cohort[group == "EXPOSED", .N]
  n_control <- d4_cohort[group == "CONTROL", .N]

  # Compute percentage of individuals with at least one missing value in SV_BMI, overall and by group
  missingness_counts <- list(
    Overall = d4_cohort[is.na(SV_BMI), .N],
    Exposed = d4_cohort[group == "EXPOSED" & is.na(SV_BMI), .N],
    Control = d4_cohort[group == "CONTROL" & is.na(SV_BMI), .N]
  )


  # BMI missigness is assessed at the person-trial level.
  observed_bmi_stats <- list(
    Overall = c(
      median = median(d4_cohort$SV_BMI, na.rm = TRUE),
      quantile(d4_cohort$SV_BMI, c(0.25, 0.75), na.rm = TRUE)
    ),
    Exposed = c(
      median = median(d4_cohort$SV_BMI[d4_cohort$group == "EXPOSED"], na.rm = TRUE),
      quantile(d4_cohort$SV_BMI[d4_cohort$group == "EXPOSED"], c(0.25, 0.75), na.rm = TRUE)
    ),
    Control = c(
      median = median(d4_cohort$SV_BMI[d4_cohort$group == "CONTROL"], na.rm = TRUE),
      quantile(d4_cohort$SV_BMI[d4_cohort$group == "CONTROL"], c(0.25, 0.75), na.rm = TRUE)
    )
  )

  # Build the table
  bmi_table <- data.table::data.table(
    Characteristic = "BMI",
    `Missing (Overall)` = paste0(round(missingness_counts$Overall / n_overall * 100, digits), "%"),
    `Missing (Exposed)` = paste0(round(missingness_counts$Exposed / n_exposed * 100, digits), "%"),
    `Missing (Control)` = paste0(round(missingness_counts$Control / n_control * 100, digits), "%"),
    `Median (Q1-Q3) Overall` = sprintf("%s (%s-%s)", round(observed_bmi_stats$Overall[[1]], digits), round(observed_bmi_stats$Overall[[2]], digits), round(observed_bmi_stats$Overall[[3]], digits)),
    `Median (Q1-Q3) Exposed` = sprintf("%s (%s-%s)", round(observed_bmi_stats$Exposed[[1]], digits), round(observed_bmi_stats$Exposed[[2]], digits), round(observed_bmi_stats$Exposed[[3]], digits)),
    `Median (Q1-Q3) Control` = sprintf("%s (%s-%s)", round(observed_bmi_stats$Control[[1]], digits), round(observed_bmi_stats$Control[[2]], digits), round(observed_bmi_stats$Control[[3]], digits))
  )

  return(bmi_table)
}
