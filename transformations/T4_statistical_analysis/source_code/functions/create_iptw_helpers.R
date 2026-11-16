#' Update expectedCat in descriptive metadata from observed covariate categories
#'
#' Computes the observed categories of SV_CALENDAR_YEAR, an age-category
#' variable, and SV_ASM_PREVIOUS from a covariates table, logs them, and
#' writes them into the `expectedCat` column of the metadata table.
#'
#' @param covariates data.table with columns SV_CALENDAR_YEAR, `age_var`,
#'   and SV_ASM_PREVIOUS.
#' @param metadata data.table as loaded via picard::load(), with a `var`
#'   column and an `expectedCat` column to update. Empty strings are
#'   converted to NA.
#' @param age_var character. Name of the age-category column in
#'   `covariates`, e.g. "SV_AGE_FATHER_CAT" or "SV_AGE_MOTHER_CAT".
#' @param cohort_label character. Label used only in log messages,
#'   e.g. "father", "mother".
#'
#' @return The updated metadata data.table.
update_metadata_categories <- function(covariates, metadata, age_var, cohort_label) {

  # Make sure empty strings are read as NA
  metadata[metadata == ""] <- NA

  # Get all values of categorical variables for display in the table
  study_years_all         <- sort(unique(covariates$SV_CALENDAR_YEAR))
  age_categories          <- sort(unique(covariates[[age_var]]))
  asm_previous_categories <- unique(covariates$SV_ASM_PREVIOUS)

  logger::log_info(paste0("Study years in the ", cohort_label, " cohort: ",
                           paste(study_years_all, collapse = ", ")))
  logger::log_info(paste0("Age categories in the ", cohort_label, " cohort: ",
                           paste(age_categories, collapse = ", ")))
  logger::log_info(paste0("ASM previous categories in the ", cohort_label, " cohort: ",
                           paste(asm_previous_categories, collapse = ", ")))

  # Update expectedCat in metadata
  metadata[var == "SV_CALENDAR_YEAR", expectedCat := paste(study_years_all, collapse = ", ")]
  metadata[var == age_var, expectedCat := paste(age_categories, collapse = ", ")]
  metadata[var == "SV_ASM_PREVIOUS", expectedCat := paste(asm_previous_categories, collapse = ", ")]

  return(metadata)
}


#' Compute and plot unweighted vs. weighted Absolute Standardized Differences (ASD)
#'
#' @param cov_with_weight   Covariates data (with weights) passed to compute_asd() from DescriptiveTables.
#' @param metadata          Metadata data.table with columns var, type, label.
#' @param weight_var        Name of the weight column to use for the weighted ASD
#'                          (passed as `use_weights` to compute_asd()).
#' @param exclude_vars      Character vector of `var` values to drop before plotting
#'                          (default "SV_ASM_PREVIOUS").
#' @param asd_threshold     Numeric threshold to draw as a dashed reference line
#'                          (default 0.1).
#' @param colors            Vector of 2 colors for c("Before weighting", "After weighting").
#'
#' @return A list with the plot (`fig_asd`) and the underlying long-format
#'         plotting data (`asd_plot_data`).
#' 
plot_asd_weighted <- function(cov_with_weight,
                               metadata,
                               weight_var = "stabilized_trunc_iptw",
                               exclude_vars = "SV_ASM_PREVIOUS",
                               asd_threshold = 0.1,
                               colors = c("darkred", "darkblue")) {

  # Compute unweighted and weighted ASDs
  asd_unweighted <- DescriptiveTable::compute_asd(
    CovariatesInformation = cov_with_weight,
    metadata = metadata,
    referenceExtension = "unweighted",
    use_weights = FALSE # assumes groups are control, exposed.
  )

  asd_weighted <- DescriptiveTable::compute_asd(
    CovariatesInformation = cov_with_weight,
    metadata = metadata,
    referenceExtension = "weighted",
    use_weights = weight_var
  )

  # Merge
  asd_combined <- data.table::merge.data.table(
    asd_unweighted,
    asd_weighted,
    by = c("var", "type")
  )

  # Merge with metadata to get labels for the variables
  asd_combined <- data.table::merge.data.table(
    asd_combined,
    metadata[, .(var, type, label)],
    by = c("var", "type"),
    all.x = TRUE
  )

  # Shape from wide to long for plotting
  asd_plot_data <- data.table::melt(
    asd_combined,
    id.vars = c("var", "type", "label"),
    measure.vars = c("asd_unweighted", "asd_weighted"),
    variable.name = "method",
    value.name = "asd"
  )

  asd_plot_data[, asd := as.numeric(asd)] # make sure asd is numerical

  asd_plot_data[
    , # Change method to factor with levels and labels for plotting
    method := factor(
      method,
      levels = c("asd_unweighted", "asd_weighted"),
      labels = c("Before weighting", "After weighting")
    )
  ]

  asd_plot_data[, label := data.table::fifelse(is.na(label), var, label)]

  # Order variables by unweighted ASD (ascending)
  var_order <- asd_plot_data[method == "Before weighting"][order(asd), label]
  asd_plot_data[, label := factor(label, levels = var_order)]

  # Remove excluded variables
  if (!is.null(exclude_vars)) {
    asd_plot_data <- asd_plot_data[!var %in% exclude_vars, ]
  }

  logger::log_info("Second step  - Plotting weighted and ASDs")

  fig_asd <- ggplot2::ggplot(
    asd_plot_data[!is.na(asd)],
    ggplot2::aes(x = label, y = asd, color = method, shape = method, group = method)
  ) +
    ggplot2::geom_point(size = 3) +
    ggplot2::geom_line(linewidth = 0.5) +
    ggplot2::geom_hline(
      yintercept = asd_threshold,
      linetype = "dashed",
      color = "black",
      linewidth = 0.5
    ) +
    ggplot2::coord_flip() +
    ggplot2::scale_shape_manual(values = c(1, 1)) +
    ggplot2::scale_color_manual(values = colors) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      legend.position = "right",
      legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = 10),
      axis.text = ggplot2::element_text(size = 10),
      axis.title = ggplot2::element_text(size = 10)
    ) +
    ggplot2::labs(x = NULL, y = "Absolute Standardised Difference")

  list(fig_asd = fig_asd, asd_plot_data = asd_plot_data)
}

#' Plot propensity score density by group
#'
#' Creates a density plot of propensity scores by group
#' (control vs. exposed) to assess overlap
#'
#' @param weights_object A data frame containing at least the columns `p_score` (numeric propensity scores) and `group` (a two-level
#'   factor/character identifying control vs. exposed units).
#'
#' @return A `ggplot` object showing overlaid density curves of
#'   `p_score` by `group`.
#'

plot_density_ps <- function(weights_object) {
  logger::log_info("Creating PS density plot")

  fig_ps_density <- ggplot2::ggplot(weights_object, ggplot2::aes(x = p_score)) +
    ggplot2::geom_density(
      ggplot2::aes(color = group, fill = group),
      linewidth = 0.8,
      alpha = 0.1
    ) +
    ggplot2::scale_fill_manual(
      values = c("darkblue", "darkred"),
      labels = c("Control", "Exposed")
    ) +
    ggplot2::scale_color_manual(
      values = c("darkblue", "darkred"),
      labels = c("Control", "Exposed")
    ) +
    ggplot2::scale_x_continuous(breaks = seq(0, 1, 0.2)) +
    ggplot2::theme_minimal() +
    ggplot2::coord_cartesian(xlim = c(0, 1)) +
    ggplot2::theme(
      legend.title = ggplot2::element_blank(),
      legend.position = "bottom",
      legend.text = ggplot2::element_text(size = 10),
      axis.text = ggplot2::element_text(size = 10),
      axis.title = ggplot2::element_text(size = 10)
    ) +
    ggplot2::labs(x = "Propensity Score", y = "Density")
  return(fig_ps_density)
}

#' Summarize Stabilized IPTW Weights by Group
#'
#' Creates a compact summary table of stabilized inverse probability of treatment
#' weights for each study group.
#'
#' @param p_matrix A data.table/data.frame containing at least `group` and the
#'   weight column specified in `stab_weight_col`.
#' @param groups Character vector of group names to summarize. Defaults to
#'   `c("CONTROL", "EXPOSED")`.
#' @param stab_weight_col Character scalar; name of the stabilized weight
#'   column in `p_matrix`.
#' @param custom_truncation Numeric length-2 vector with optional lower and
#'   upper truncation cutoffs to report.
#' @param digits Integer; number of decimal places for rounded output.
#'
#' @return A data.frame with summary rows (mean/sd, quartiles, median, range,
#'   p1-p99, truncation cutoffs) and two columns per group.
#' @export
describe_iptw <- function(p_matrix,
                          groups = c("CONTROL", "EXPOSED", "all"), # names of groups
                          stab_weight_col = "IPTW_full_corr", # column name stabilised weights
                          custom_truncation = c(NA, NA), # if additional truncation used, specify here
                          digits = 1) {
  for (gname in groups) {
    # calculate statistics
    if (gname == "all") {
      subset <- "TRUE"
    } else {
      subset <- glue::glue("group == '{gname}'")
    }
    mean_weight <- mean(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    median_weight <- median(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    sd_weight <- sd(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    quants <- quantile(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], c(0.01, 0.25, 0.75, 0.99), na.rm = TRUE)
    min_weight <- min(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    max_weight <- max(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], na.rm = TRUE)
    quants_custom <- quantile(p_matrix[eval(parse(text = subset)), get(stab_weight_col)], custom_truncation, na.rm = TRUE)

    # collect into a data.frame
    gtemp <- data.frame(
      labels = c(
        "Mean (SD)",
        "Q1-Q3",
        "Median",
        "Range (Min-Max)",
        "P1-P99",
        "If truncated cut-offs"
      ),
      V1 = round(c(
        mean_weight,
        quants[2],
        median_weight,
        min_weight,
        quants[1],
        quants_custom[1]
      ), digits),
      V2 = round(c(
        sd_weight,
        quants[3],
        NA,
        max_weight,
        quants[4],
        quants_custom[2]
      ), digits)
    )

    # change row names
    colnames(gtemp)[c(2, 3)] <- paste0(gname, c("_V1", "_V2"))

    if (gname == groups[1]) {
      gout <- gtemp
    } else {
      gout <- cbind(gout, gtemp[, -1])
    }
  } # end loop over groups

  return(gout)
}


#' Compute Absolute Standardized Differences and Descriptive Counts
#'
#' Builds a descriptive/ASD table from weighted covariates, handling both
#' two-group (control vs exposed) and single-group outputs (to get totals), rounding numeric
#' columns, and formatting combined "value (stat)" summary columns.
#'
#' @param covariates_with_weights Data frame/data.table of covariates with weights and group column.
#' @param use_weights Character. Name of the weight column to use. Default `'stabilized_trunc_iptw'`.
#' @param weighted_stats Logical. Whether to compute weighted statistics. Default `TRUE`.
#' @param calculate_asd Logical. Whether to calculate ASD. Default `TRUE` (currently unused directly; passed via `output_asd`).
#' @param output_asd Logical. Whether to output ASD values. Default `TRUE`.
#' @param metadata Table metadata passed to `DescriptiveTable::DescriptivesTable`.
#'
#' @return A `data.table` with variable, category, type, rounded stats columns,
#'   ASD (if two groups), and formatted `outcome_col`/`outcome_col_control`/`outcome_col_exposed`.
#'
#' @export
compute_asd_and_counts <- function(covariates_with_weights,
                                    use_weights = 'stabilized_trunc_iptw',
                                    weighted_stats = TRUE,
                                    calculate_asd = TRUE,
                                    output_asd = TRUE,
                                    asd_per_level = TRUE,
                                    metadata){

baseline_descriptives <- DescriptiveTable::DescriptivesTable(
  popdf = covariates_with_weights,
  table_metadata = metadata,
  groupcol = "group",
  output_format = 'raw',
  calculate_asd = output_asd,
  keep_varinfo = TRUE,
  label_lookup = NULL,
  control_types = FALSE,
  missing_vars = NULL,
   missing_flag = NULL,
  round_decimals = 2,
  use_weights = use_weights,
  weighted_stats = weighted_stats,
  output_asd = output_asd,
  asd_per_level = asd_per_level)

  if(!data.table::is.data.table(baseline_descriptives)){
  tab <- baseline_descriptives$table
  } else {
  tab <- baseline_descriptives
  }
  
  # Detect whether this is a two-group (CONTROL/EXPOSED) or single-group (All) table
  has_two_groups <- "V1_EXPOSED" %in% names(tab)

  if (has_two_groups) {
    tab <- tab[, .(var, cat, type, V1_CONTROL, V1_EXPOSED, V2_CONTROL, V2_EXPOSED, V3_CONTROL, V3_EXPOSED, asd_1)]
    numeric_cols <- c('V1_CONTROL', 'V1_EXPOSED', 'V2_CONTROL', 'V2_EXPOSED', 'V3_CONTROL', 'V3_EXPOSED', 'asd_1')
  } else {
    tab <- tab[, .(var, cat, type, V1_All, V2_All, V3_All)]
    numeric_cols <- c('V1_All', 'V2_All', 'V3_All')
  }

  # Round all numeric columns to 2 decimal places
  tab[, (numeric_cols) := lapply(.SD, function(x) round(as.numeric(x), 2)), .SDcols = numeric_cols]

  # Create outcome_col, using the right column names for each case
  if (has_two_groups) {
    tab[, outcome_col_control := data.table::fcase(
     type == "NUM1" & cat == 'STATS1', sprintf("%s (%s)", V1_CONTROL, V2_CONTROL),
      type == "NUM1" & cat == 'STATS2', sprintf("%s (%s, %s)", V1_CONTROL, V2_CONTROL, V3_CONTROL),
      default = sprintf("%s (%s)", V1_CONTROL, V2_CONTROL)
    )]
    tab[, outcome_col_exposed := data.table::fcase(
      type == "NUM1" & cat == 'STATS1', sprintf("%s (%s)", V1_EXPOSED, V2_EXPOSED),
      type == "NUM1" & cat == 'STATS2', sprintf("%s (%s, %s)", V1_EXPOSED, V2_EXPOSED, V3_EXPOSED),
      default = sprintf("%s (%s)", V1_EXPOSED, V2_EXPOSED)
    )]
  } else {
    tab[, outcome_col := data.table::fcase(
      type == "NUM1" & cat == 'STATS1', sprintf("%s (%s)", V1_All, V2_All),
      type == "NUM1" & cat == 'STATS2', sprintf("%s (%s, %s)", V1_All, V2_All, V3_All),
      default = sprintf("%s (%s)", V1_All, V2_All)
    )]
}
return(tab)
                
}

#' Build Combined Weighted/Unweighted Baseline Descriptives Table
#'
#' Computes weighted and unweighted descriptive/ASD tables for both the
#' group comparison (control vs exposed) and the overall ("All") sample,
#' then merges them into a single summary table with labels from metadata.
#'
#' @param covariates_with_weights Data frame/data.table of covariates with weights and group column.
#' @param metadata Table metadata passed to `compute_asd_and_counts()`, including `var`, `type`, and `label`.
#'
#' @return A `data.table` with one row per `var`/`cat`/`type`, containing
#'   unweighted/weighted total, exposed, and control summary columns, ASD
#'   columns, and a merged `label` column.
#'
#' @export
baseline_descriptives <- function(covariates_with_weights,
                                  metadata){

weighted_groups <- compute_asd_and_counts(covariates_with_weights,
                            metadata = metadata,
                            use_weights = 'stabilized_trunc_iptw',
                            weighted_stats = TRUE,
                            calculate_asd = TRUE,
                            output_asd = TRUE,
                            asd_per_level = TRUE)
unweighted_groups <- compute_asd_and_counts(covariates_with_weights,
                            metadata = metadata,
                            use_weights = FALSE,
                            weighted_stats = FALSE,
                            calculate_asd = TRUE,
                            output_asd = TRUE,
                            asd_per_level = TRUE)

covariates_no_group <- covariates_with_weights
covariates_no_group$group <- 'All'
unweighted_totals <- compute_asd_and_counts(covariates_with_weights = covariates_no_group,
                            metadata = metadata,
                            use_weights = FALSE,
                            weighted_stats = FALSE,
                            calculate_asd = FALSE,
                            output_asd = FALSE,
                            asd_per_level = FALSE)
weighted_totals <- compute_asd_and_counts(covariates_with_weights = covariates_no_group,
                            metadata = metadata,
                            use_weights = 'stabilized_trunc_iptw',
                            weighted_stats = TRUE,
                            calculate_asd = FALSE,
                            output_asd = FALSE,
                            asd_per_level = FALSE)

# Extract & rename the relevant column from each table
uw_total   <- unweighted_totals[, .(var, cat, type, unweighted_total   = outcome_col)]
uw_exposed <- unweighted_groups[, .(var, cat, type, unweighted_exposed = outcome_col_exposed)]
uw_control <- unweighted_groups[, .(var, cat, type, unweighted_control = outcome_col_control)]
uw_asd     <- unweighted_groups[, .(var, cat, type, asd_unweighted = asd_1)]
w_total    <- weighted_totals[,   .(var, cat, type, weighted_total     = outcome_col)]
w_exposed  <- weighted_groups[,   .(var, cat, type, weighted_exposed   = outcome_col_exposed)]
w_control  <- weighted_groups[,   .(var, cat, type, weighted_control   = outcome_col_control)]
w_asd      <- weighted_groups[,   .(var, cat, type, asd_weighted = asd_1)]

# merge all
step1 <- data.table::merge.data.table(uw_total, uw_exposed, by = c("var", "cat", "type"), all = TRUE, sort = FALSE)
step2 <- data.table::merge.data.table(step1, uw_control, by = c("var", "cat", "type"), all = TRUE, sort = FALSE)
step3 <- data.table::merge.data.table(step2, uw_asd, by = c("var", "cat", "type"), all = TRUE, sort = FALSE)
step4 <- data.table::merge.data.table(step3, w_total, by = c("var", "cat", "type"), all = TRUE, sort = FALSE)
step5 <- data.table::merge.data.table(step4, w_exposed, by = c("var", "cat", "type"), all = TRUE, sort = FALSE)
step6 <- data.table::merge.data.table(step5, w_control, by = c("var", "cat", "type"), all = TRUE, sort = FALSE)
final_table <- data.table::merge.data.table(step6, w_asd, by = c("var", "cat", "type"), all = TRUE, sort = FALSE)
# Reorder so asd_1 is last column
final_table <- final_table[, .(var, cat, type, unweighted_total, unweighted_exposed, unweighted_control,
                                weighted_total, weighted_exposed, weighted_control, asd_unweighted, asd_weighted)]

# Merge with metadata using var to add label
final_table <- data.table::merge.data.table(final_table, 
  metadata[, .(var, type, label)],
   by = c("var", 'type'),
    all.x = TRUE, 
    all.y = FALSE,
    sort = FALSE)
return(final_table)
}


#' Create Prevalence Table with Propensity Score Odds Ratios
#'
#' Merges a prevalence/descriptives table with propensity score model
#' coefficients, matching variables by constructing equivalent names
#' (e.g. `TRUE`-suffixed or category-suffixed) (on the table as the model cofficients)
#' outputted from the model and adding computed
#' odds ratios with 95% confidence intervals.
#'
#' @param table3 Data.table of prevalence data, containing `var`, `type`, `cat`,
#'   `unweighted_total`, and `label` columns (the output of `baseline_descriptives()`).
#' @param ps_coef Data.table of propensity score model coefficients, containing
#'   `coefficient`, `exp_estimate`, `estimate`, and `std_error` columns. (the D5_PS_COEF objects estimated)
#'    # via compute_IPTW scripts
#' @return A `data.table` merging prevalence rows with matching odds ratios
#'   and formatted `OR_ci` (odds ratio with 95% CI) column.
#'
#' @export
create_prevalence_coefficients_table <- function(table3, ps_coef) {
  prevalence <- table3[, .(var, type, cat, unweighted_total, label)]
  # Remove total
  prevalence <- prevalence[var != 'Total']
  # In prevalence tables, we need to create equal variable names as in the propensity score model (d5_ps_coef)
  # For that we create a new colum table.var
  # If true-false, add true to var
  prevalence[, table.var := ifelse(
    type == "TF", paste0(var, "TRUE"), NA
  )]
  
  # If cat, add label to var
  prevalence[, table.var := ifelse(
   type == "CAT", paste0(var, cat),
    table.var
  )]

  # 2. Extract OR for each coefficient
  odd_ratios_per_var <- ps_coef[, .(coefficient, exp_estimate, estimate, std_error)]
  # Remove intercept row, as it is not needed for the table
  odd_ratios_per_var <- odd_ratios_per_var[!coefficient %in% c("(Intercept)")]

  # Compute 95% CI for each OR
  odd_ratios_per_var[,exp_estimate_lower := exp(estimate + qnorm(0.025) * std_error)]
  odd_ratios_per_var[,exp_estimate_upper := exp(estimate + qnorm(0.975) * std_error)]
  odd_ratios_per_var[, OR_ci := sprintf("%.2f (%.2f-%.2f)", round(exp_estimate, 2), round(exp_estimate_lower, 2), round(exp_estimate_upper, 2))]

  # 3. Merge
  output_table <- data.table::merge.data.table(
    x = prevalence,
    y = odd_ratios_per_var,
    by.x = "table.var",
    by.y = "coefficient",
    all.x = TRUE, # make sure all rows from prevalence table are kept, even if no match in OR table
    all.y = TRUE, # make sure all rows from OR table are kept, even if no match in prevalence table
    sort = FALSE
  )
  return(output_table)
}

#' Build Combined Propensity Score and IPTW Summary Table
#'
#' Produces per-group (control/exposed/all) descriptive summaries of both
#' the propensity score and the (truncated) IPTW weights, and stacks them
#' into a single labeled table with section headers.
#'
#' @param selected_iptw Data frame/matrix of the cohort, including group,
#'   weight, and propensity score/principal strata columns (weight objects)
#' @param weights_column_name Character. Name of the (stabilized) weight column
#' @param propensity_score_name Character. Name of the propensity score or principal stratum column.
#' @param truncation_bounds Custom truncation bounds passed to `describe_iptw()`.
#'
#' @return A character matrix stacking the propensity score summary and the
#'   IPTW summary, each preceded by a section header row.
#'
#' @export
table7 <- function(selected_iptw, weights_column_name, propensity_score_name, truncation_bounds){

  weight_table <- describe_iptw(
    p_matrix = selected_iptw, # selected_iptw,
    groups = c("CONTROL", "EXPOSED", "all"),
    stab_weight_col = weights_column_name,
    custom_truncation = truncation_bounds,
    digits = 3
  )
  # Per-group summary of propensity scores on the full (pre-trim) cohort.
  ps_description <- describe_iptw(
    p_matrix = selected_iptw,
    groups = c("CONTROL", "EXPOSED", "all"),
    stab_weight_col = propensity_score_name,
    custom_truncation = truncation_bounds,
    digits = 3
  )
  combined_table <-
    rbind(
      t(c("Propensity score", rep("", 6))),
      as.matrix(ps_description),
      t(c("IPTW", rep("", 6))),
      as.matrix(weight_table))
  
  return(combined_table)
}
