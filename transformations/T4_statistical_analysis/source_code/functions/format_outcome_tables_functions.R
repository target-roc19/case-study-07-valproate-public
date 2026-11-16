# Format outcome table 12 and 13 based on D5_CohortAnalyticLookup and outcome_parameter_lookup

# Fixed row design ---------------------------------------------------------

add_analysis_sections <- function(dt) {
  data.table::rbindlist(
    list(
      data.table::data.table(Description = "Main Analyses"),
      dt[1:2],
      data.table::data.table(Description = "Sensitivity Analyses"),
      dt[3:12]
      # data.table::data.table(Description = "Supplement Analyses"),
      # dt[5]
    ),
    fill = TRUE
  )
}

# Formatting helpers ------------------------------------------------------

fmt_num <- function(x, digits = 1) {
  x <- suppressWarnings(as.numeric(x))

  data.table::fifelse(
    is.na(x) | x %in% c(-99, -88),
    "",
    formatC(x, digits = digits, format = "f", big.mark = ",")
  )
}

fmt_ci <- function(lb, ub, digits = 1, style = c("lbub", "dash")) {
  style <- match.arg(style)

  lb <- fmt_num(lb, digits)
  ub <- fmt_num(ub, digits)

  data.table::fifelse(
    lb == "" | ub == "",
    "",
    if (style == "lbub") {
      paste0("Lb, ub: ", lb, ", ", ub)
    } else {
      paste0(lb, "-", ub)
    }
  )
}

add_table_attrs <- function(dt, params) {
  attr(dt, "title") <- params$Description
  attr(dt, "tab_group") <- params$tab_group
  dt
}

create_table8 <- function(D5_CohortAnalyticLookup, outcome_parameter, use_boot_ci = FALSE) {
  x <- data.table::as.data.table(D5_CohortAnalyticLookup)
  p <- as.list(outcome_parameter[1, ])

  # If use_boot_ci is TRUE, replace the original confidence intervals with the bootstrapped confidence intervals
  if (use_boot_ci) {
    x$ir_lb_exp <- x$ir_lb_exp_boot
    x$ir_ub_exp <- x$ir_ub_exp_boot
    x$ir_lb_con <- x$ir_lb_con_boot
    x$ir_ub_con <- x$ir_ub_con_boot
  }

  # Create the data.table with formatted values
  dt <- data.table::data.table(
    Description = x$analysis_description,
    `Exposed: N individuals` = fmt_num(x$n_pat_exp, 0),
    `Exposed: N events` = fmt_num(x$n_out_exp, 0),
    `Exposed: Person-Months` = fmt_num(x$py_exp, 4),
    `Exposed: Cumulative Incidence` = fmt_num(x$ir_est_exp, 2),
    `Exposed: 95% CI` = fmt_ci(x$ir_lb_exp, x$ir_ub_exp, 2, "dash"),
    `Control: N individuals` = fmt_num(x$n_pat_con, 0),
    `Control: N events` = fmt_num(x$n_out_con, 0),
    `Control: Person-Months` = fmt_num(x$py_con, 4),
    `Control: Cumulative Incidence` = fmt_num(x$ir_est_con, 2),
    `Control: 95% CI` = fmt_ci(x$ir_lb_con, x$ir_ub_con, 2, "dash")
  )

  # dt <- add_analysis_sections(dt)
  # add_table_attrs(dt, p)
}

create_table9 <- function(D5_CohortAnalyticLookup, outcome_parameter, use_boot_ci = FALSE) {
  x <- data.table::as.data.table(D5_CohortAnalyticLookup)
  p <- as.list(outcome_parameter[1, ])

  # If use_boot_ci is TRUE, replace the original confidence intervals with the bootstrapped confidence intervals
  if (use_boot_ci) {
    x$rr_lb_crude <- x$rr_lb_crude_boot
    x$rr_ub_crude <- x$rr_ub_crude_boot
    x$rr_lb_adj <- x$rr_lb_adj_boot
    x$rr_ub_adj <- x$rr_ub_adj_boot
  }

  dt <- data.table::data.table(
    Description = x$analysis_description,
    `Cumulative Incidence Ratio (crude)` = fmt_num(x$rr_est_crude, 2),
    `95%CI` = fmt_ci(x$rr_lb_crude, x$rr_ub_crude, 2, "dash"),
    `Cumulative Incidence Ratio (adjusted)` = fmt_num(x$rr_est_adj, 2),
    `95%CI` = fmt_ci(x$rr_lb_adj, x$rr_ub_adj, 2, "dash")
  )

  # dt <- add_analysis_sections(dt)

  # attr(dt, "rr_type") <- rr_type
  # add_table_attrs(dt, p)
}

create_table13 <- function(D5_CohortAnalyticLookup_bw, use_boot_ci = FALSE) {
  x <- data.table::as.data.table(D5_CohortAnalyticLookup_bw)
  x <- x[order(as.integer(bw_id))]

  scenario_lookup <- data.table::data.table(
    bw_id = 1:4,
    Scenario = as.character(1:4),
    `Exposed Group` = c(
      "Best case (lowest event rate)",
      "Worst case (highest event rate)",
      "Best case",
      "Worst case"
    ),
    `Unexposed Group` = c(
      "Worst case (highest event rate)",
      "Best case (lowest event rate)",
      "Best case",
      "Worst case"
    ),
    Interpretation = c(
      "Maximally favors intervention",
      "Maximally favors control",
      "Optimistic for both groups (primary analysis)",
      "Pessimistic for both groups"
    )
  )

  dt <- data.table::merge.data.table(
    scenario_lookup,
    x,
    by = "bw_id",
    all.x = TRUE,
    sort = FALSE
  )
  if (use_boot_ci) {
    dt$rr_lb_adj <- dt$rr_lb_adj_boot
    dt$rr_ub_adj <- dt$rr_ub_adj_boot
  }

  dt[, `Cumulative Incidence Ratio` := fmt_num(rr_est_adj, 2)]
  dt[, `95% CI` := fmt_ci(rr_lb_adj, rr_ub_adj, 2, "dash")]

  dt[, .(
    Scenario,
    `Exposed Group`,
    `Unexposed Group`,
    Interpretation,
    `Cumulative Incidence Ratio`,
    `95% CI`
  )]
}
