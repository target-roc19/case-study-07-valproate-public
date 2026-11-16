# ---------------------------------------------------------------------------
# cohort_analytic_lookup_functions.R
# Helper functions for create_cohort_analytic_lookup
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# prepare_aesifup: reshape one FUP data.table for a given estimand and merge
# weights. Converts person-years to person-months so that incidence rates are
# reported per 100,000 person-months.
# output is divided into lists, listed by parameter 'listed_by'
# ---------------------------------------------------------------------------
library("geeM")
library("survival")
library("msm")

prepare_aesifup <- function(fup_dt, estimand_n, weight_dt = NULL, weight_col = NULL, listed_by = NULL) {
  dt <- data.table::copy(fup_dt)
  listed_by_col <- if (!is.null(listed_by) && nzchar(trimws(listed_by))) listed_by else NULL

  data.table::setnames(dt, paste0("fup_length_days_estimand", estimand_n), "fup")
  data.table::setnames(dt, paste0("fup_length_months_estimand", estimand_n), "pm")
  data.table::setnames(dt, paste0("event_estimand", estimand_n), "eventCount")
  dt[, eventCount := as.integer(as.character(eventCount))]

  # Remove persons with trimmed weights if the column exists in the FUP dataset
  if ("include_after_trimming" %in% names(dt)) {
    trimmed_count <- sum(dt$include_after_trimming == FALSE, na.rm = TRUE)
    dt <- dt[include_after_trimming == TRUE]
    logger::log_info(glue::glue("Removed {trimmed_count} persons with trimmed weights from the FUP dataset."))
  }

  keep <- c("person_id", "father_id", "child_id", "T0", "group", "trial_id", "fup", "pm", "eventCount")
  if (!is.null(listed_by_col)) {
    if (!(listed_by_col %in% names(dt))) {
      stop(glue::glue("Column '{listed_by_col}' was not found in follow-up data."))
    }
    keep <- c(keep, listed_by_col)
  }
  dt <- dt[, ..keep]
  dt[, id := trial_id]

  if (!is.null(weight_dt) && !is.null(weight_col) && nzchar(trimws(weight_col))) {
    # Set person_id to father_id in the weight dataset to match the FUP dataset
   # dt[, person_id := father_id] 

    # call unique to drop duplicate rows (can happen for multiplets)
    wt <- data.table::copy(weight_dt)
    if (!(weight_col %in% names(wt))) {
      stop(glue::glue("Weight column '{weight_col}' was not found in weight data."))
    }
    data.table::setnames(wt, weight_col, "ip_weight")
    wt <- wt[, .(person_id,  father_id, child_id,T0, group, ip_weight)]

    n.imputation <- length(unique(dt$imputation_id))
    # If length of FUP and weight object is different, throw error
    if (! (nrow(wt) %in% c(nrow(dt)/n.imputation, nrow(dt)/4))) {
      logger::log_error(glue::glue("The number of rows in the FUP dataset ({nrow(dt)}) does not match the number of rows in the weight dataset ({nrow(wt)}). Please check the data."))
      stop("The number of rows in the FUP dataset does not match the number of rows in the weight dataset.")
    }
    dt <- data.table::merge.data.table(
      x = dt, # fup object
      y = wt, # weight object
      by = c("father_id",'child_id', "T0", "group"),
      all.x = TRUE,
      all.y = TRUE
    )

    # Restore person_id to original value in the FUP dataset
    dt[, person_id := child_id]
  } else {
    dt[, ip_weight := 1.0]
  }

  
  dt[, group := factor(group, levels = c("CONTROL", "EXPOSED"))]
  dt[, person_id_num := as.numeric(as.factor(person_id))]
  data.table::setorder(dt, person_id_num)

  # As per protocol the offset is set to 0 since outcomes due
  # to non-admin censoring have already been imputed.
  dt[, pm_offset := log(1)]
  if (nrow(dt[pm == 0]) > 0) {
    logger::log_warn(glue::glue("Detected {nrow(dt[pm == 0])} individuals with 0 follow up time, check that they correspond to censoring due to treatment switch or treatment discontinuation more than three monhts before conception."))
  }
  # dt[pm == 0, pm_offset := -Inf]

  if (!is.null(listed_by_col)) {
    split_idx <- dt[, .(row_id = list(.I)), by = listed_by_col]
    split_list <- lapply(split_idx$row_id, function(idx) {
      dt[idx]
    })
    split_names <- as.character(split_idx[[listed_by_col]])
    split_names[is.na(split_names)] <- "NA"
    names(split_list) <- split_names
    return(split_list)
  }

  list(all = dt)
}

# ---------------------------------------------------------------------------
# iter_cohort_analytic_lookup: iterate over all unique combinations of
# (source_D4, estimand, source_weight) defined in outcome_tables, compute
# incidence rates and log-binomial risk ratios via CohortAnalytics, and
# assemble one output row per outcome_tables entry.
# ---------------------------------------------------------------------------
iter_cohort_analytic_lookup <- function(fup_datasets,
                                        weight_datasets,
                                        outcome_analysis_types,
                                        aesi_name,
                                        aesi_label,
                                        scale_IR = 100000,
                                        n_bootstrap = 50,
                                        resample_col = "father_id",
                                        seed = 42) {
  outcome_analysis_types <- data.table::as.data.table(outcome_analysis_types)
  results_by_analysis <- vector("list", nrow(outcome_analysis_types))
  names(results_by_analysis) <- as.character(outcome_analysis_types$analysis_index)

  for (i in seq_len(nrow(outcome_analysis_types))) {
    combo <- outcome_analysis_types[i]
    analysis_results <- list()
    analysis_out_idx <- 1L
    risk_type <- combo$risk_type
    analysis_description <- combo$analysis_description
    logger::log_info(glue::glue("Computing: {combo$analysis_type} analysis, estimand {combo$estimand} with {combo$source_fup}"))

    fup_dt <- data.table::copy(fup_datasets[[combo$source_fup]])
    listed_by_col <- if (!is.null(combo$listed_by) && nzchar(trimws(combo$listed_by))) combo$listed_by else NULL
    has_weight <- !is.null(combo$source_weight) && nzchar(trimws(combo$source_weight))
    wt_dt <- if (has_weight) data.table::copy(weight_datasets[[combo$source_weight]]) else NULL

    aesifup_list <- prepare_aesifup(
      fup_dt,
      estimand_n = combo$estimand,
      weight_dt = wt_dt,
      weight_col = combo$weight_col,
      listed_by = combo$listed_by
    )

    split_names <- names(aesifup_list)
    for (j in seq_along(aesifup_list)) {
      aesifup <- aesifup_list[[j]]
      split_name <- split_names[[j]]

      logger::log_info(glue::glue(
        "Running analysis_index={combo$analysis_index} {ifelse(is.null(listed_by_col), '', paste0('for ', listed_by_col, '=', split_name))}"
      ))

      res <- tryCatch(
        CohortAnalytics::compute_rates_cohort(
          aesifup_input                 = aesifup,
          fupCol                        = "fup",
          pyrCol                        = "pm",
          pyr_offset                    = "pm_offset",
          eventCol                      = "eventCount",
          iptw                          = "ip_weight",
          target_aesi                   = aesi_name,
          type                          = "incidence",
          CImethod                      = "wilson",
          risk_type                     = risk_type,
          CumulativeInc                 = FALSE,
          comparison_measures           = TRUE,
          scale_IR                      = scale_IR,
          model_based_control           = TRUE,
          weighted_IR                   = TRUE,
          end_risk                      = NULL,
          output_format                 = "data.frame",
          minimum_count_for_comparative = 3
        ),
        error = function(e) {
          logger::log_error(glue::glue(
            "Error for analysis index {combo$analysis_index}{ifelse(is.null(listed_by_col), '', paste0(' (', listed_by_col, '=', split_name, ')'))}: {conditionMessage(e)}"
          ))
          NULL
        }
      )

      if (is.null(res)) {
        next
      }

      # Store the original (non-bootstrapped) results before bootstrap loop
      # The n_pat values should come from the original data, not bootstrap resamples
      res_original <- data.table::as.data.table(res)

      #----------------------------------------
      # Bootstrapping for confidence intervals
      #----------------------------------------

      # Set progress bar for bootstrapping iterations
      pb <- utils::txtProgressBar(min = 0, max = n_bootstrap, style = 3)
      on.exit(close(pb), add = TRUE)

      # Set seed for reproducibility of bootstrapping
      set.seed(seed)

      for (boot_iter in 1:n_bootstrap) {
        utils::setTxtProgressBar(pb, boot_iter)

        # if (boot_iter %% 50 == 0) {
        #   logger::log_info(glue::glue("Bootstrapping iteration {boot_iter} for analysis_index={combo$analysis_index} {ifelse(is.null(listed_by_col), '', paste0('for ', listed_by_col, '=', split_name))}"))
        # }

        # Only if we can successfully compute the rates, we perform bootstrapping of the data, compute rates over the bootstrapped data, and compute the confidence intervals for the rates and risk ratios

        # Resample person ids with replacement to create a bootstrap sample of the data
        resamples_persons <- sample(unique(aesifup[[resample_col]]), size = length(unique(aesifup[[resample_col]])), replace = TRUE)

        # Treat the vector of resampled person_ids as a data.table with one column named "father_id" and join it with the original data.table to create a new data.table with the resampled person ids
        resamples_dt <- data.table::data.table()
        resamples_dt[, (resample_col) := resamples_persons]

        # Select rows from the original data.table based on the resampled person ids. We should
        # use a left join such that resampled person_ids get repeated in the new data.table,
        # and we can compute the rates over the bootstrapped data.
        aesifup_boot <- data.table::copy(aesifup)
        aesifup_boot <- data.table::merge.data.table(
          aesifup_boot,
          resamples_dt,
          by = (resample_col), # or person_id?
          all.x = FALSE,
          all.y = TRUE,
          allow.cartesian = TRUE
        )

        # Now compute the rates over the bootstrapped data
        res_boot_iter <- tryCatch(
          CohortAnalytics::compute_rates_cohort(
            aesifup_input                 = aesifup_boot,
            fupCol                        = "fup",
            pyrCol                        = "pm",
            pyr_offset                    = "pm_offset",
            eventCol                      = "eventCount",
            iptw                          = "ip_weight",
            target_aesi                   = aesi_name,
            type                          = "incidence",
            CImethod                      = "wilson",
            risk_type                     = risk_type,
            CumulativeInc                 = FALSE,
            comparison_measures           = TRUE,
            scale_IR                      = scale_IR,
            model_based_control           = TRUE,
            weighted_IR                   = TRUE,
            end_risk                      = NULL,
            output_format                 = "data.frame",
            minimum_count_for_comparative = 3
          ),
          error = function(e) {
            logger::log_error(glue::glue(
              "Error for analysis index {combo$analysis_index}{ifelse(is.null(listed_by_col), '', paste0(' (', listed_by_col, '=', split_name, ')'))}: {conditionMessage(e)} bootstrapping iteration {boot_iter}"
            ))
            NULL
          }
        )

        if (is.null(res_boot_iter)) {
          next
        }

        # rbind the results of the bootstrapped iteration to the main results data.table
        if (boot_iter == 1) {
          res_boot <- data.table::as.data.table(res_boot_iter)
        } else {
          res_boot <- data.table::rbindlist(list(res_boot, data.table::as.data.table(res_boot_iter)), use.names = TRUE, fill = TRUE)
        }
      }

      # Now that we completed a bootstrap loop for an imputated dataset, we can
      # extract the 95% CIs for the cumulative incidences and risk ratios and
      # add them to the main results data.table.

      # We will keep the original assymptotic CIs and add the bootstrapped CIs
      # as new columns to the results data.table. The bootstrapped CIs will be
      # named with a suffix "_boot" to distinguish them from the original CIs.

      # define safe quantile function that returns NA if the input vector is empty or contains only NA values
      q_safe <- function(x, p) {
        x <- x[!is.na(x) & !x %in% c(-77, -88, -99)]
        if (length(x) == 0) {
          return(NA_real_)
        }
        quantile(x, p, names = FALSE)
      }

      # compute confidence intervals and valid est counts
      ci_result <- res_boot[
        ,
        .(
          ir_lb_exp_boot = q_safe(ir_est_exp, 0.025),
          ir_ub_exp_boot = q_safe(ir_est_exp, 0.975),
          ir_lb_con_boot = q_safe(ir_est_con, 0.025),
          ir_ub_con_boot = q_safe(ir_est_con, 0.975),
          rr_lb_crude_boot = q_safe(rr_est_crude, 0.025),
          rr_ub_crude_boot = q_safe(rr_est_crude, 0.975),
          rr_lb_adj_boot = q_safe(rr_est_adj, 0.025),
          rr_ub_adj_boot = q_safe(rr_est_adj, 0.975),
          ir_exp_n_boot = sum(!is.na(ir_est_exp) & !ir_est_exp %in% c(-77, -88, -99)),
          ir_con_n_boot = sum(!is.na(ir_est_con) & !ir_est_con %in% c(-77, -88, -99)),
          rr_crude_n_boot = sum(!is.na(rr_est_crude) & !rr_est_crude %in% c(-77, -88, -99)),
          rr_adj_n_boot = sum(!is.na(rr_est_adj) & !rr_est_adj %in% c(-77, -88, -99))
        )
      ]

      #----------- end of the bootstrap loop ------------#

      # Clean up the results data.table to remove unnecessary columns and add analysis description
      # Use the original (non-bootstrapped) results for n_pat and other statistics
      res_dt <- data.table::as.data.table(res_original)

      # drop columns with a name that contains the string "cuminc" as they are not needed for the final output
      if (!is.null(res_dt) && any(grepl("cuminc", names(res_dt)))) {
        cuminc_cols <- grep("cuminc", names(res_dt), value = TRUE)
        res_dt[, (cuminc_cols) := NULL]
      }

      # drop column with a name that contains the string "rd_" as they are not needed for the final output
      if (!is.null(res_dt) && any(grepl("rd_", names(res_dt)))) {
        rd_cols <- grep("rd_", names(res_dt), value = TRUE)
        res_dt[, (rd_cols) := NULL]
      }

      # bind the bootstrapped confidence intervals to the main results data.table
      res_dt <- cbind(res_dt, ci_result)

      # Add analysis desciption to results table
      res_dt[, analysis_description := analysis_description]

      if (!is.null(listed_by_col) && listed_by_col %in% names(aesifup)) {
        res_dt[, (listed_by_col) := aesifup[[listed_by_col]][1]]
      }

      analysis_results[[analysis_out_idx]] <- res_dt
      analysis_out_idx <- analysis_out_idx + 1L
    }

    results_by_analysis[[i]] <- if (length(analysis_results) == 0L) {
      data.table::data.table()
    } else {
      data.table::rbindlist(analysis_results, fill = TRUE, use.names = TRUE)
    }
  }

  results_by_analysis
}

# ---------------------------------------------------------------------------
# pool_cohort_analytic_lookup: apply metadata-driven pooling rules per
# analysis list element.
# - pooling_method == "rubin": Rubin pooling across split rows (MI analyses)
# - pooling_method == "subset": keep rows matching pooling_condition
# ---------------------------------------------------------------------------
pool_cohort_analytic_lookup <- function(lookup_list, outcome_analysis_types) {
  meta <- data.table::as.data.table(data.table::copy(outcome_analysis_types))

  if (length(lookup_list) == 0L) {
    return(list())
  }

  pool_metric <- function(est, lb, ub, log_scale = FALSE) {
    ok <- (is.finite(est) & !(est %in% c(-77, -88, -99))) & (is.finite(lb) & !(lb %in% c(-77, -88, -99))) & (is.finite(ub) & !(ub %in% c(-77, -88, -99)))
    if (!any(ok)) {
      return(list(est = NA_real_, lb = NA_real_, ub = NA_real_, n = 0L))
    }

    est <- est[ok]
    lb <- lb[ok]
    ub <- ub[ok]

    if (length(est) == 1L) {
      return(list(est = est[1], lb = lb[1], ub = ub[1], n = 1L))
    }

    if (log_scale && any(est <= 0 | lb <= 0 | ub <= 0)) {
      log_scale <- FALSE
    }

    q <- if (log_scale) log(est) else est
    se <- if (log_scale) {
      (log(ub) - log(lb)) / (2 * stats::qnorm(0.975))
    } else {
      (ub - lb) / (2 * stats::qnorm(0.975))
    }

    keep <- is.finite(q) & is.finite(se)
    if (!any(keep)) {
      return(list(est = NA_real_, lb = NA_real_, ub = NA_real_, n = 0L))
    }

    n_effective <- sum(keep)
    pooled <- mice::pool.scalar(Q = q[keep], U = se[keep]^2, n = Inf, k = 1)
    crit <- if (is.finite(pooled$df)) stats::qt(0.975, pooled$df) else stats::qnorm(0.975)
    lo <- pooled$qbar - crit * sqrt(pooled$t)
    hi <- pooled$qbar + crit * sqrt(pooled$t)

    if (log_scale) {
      list(est = exp(pooled$qbar), lb = exp(lo), ub = exp(hi), n = n_effective)
    } else {
      list(est = pooled$qbar, lb = lo, ub = hi, n = n_effective)
    }
  }

  pool_analysis_rubin <- function(dt) {
    out <- data.table::copy(dt[1])
    est_cols <- grep("_est_", names(dt), value = TRUE)
    n_pooled_values <- c()

    for (est_col in est_cols) {
      lb_col <- sub("_est_", "_lb_", est_col)
      ub_col <- sub("_est_", "_ub_", est_col)
      if (!(lb_col %in% names(dt) && ub_col %in% names(dt))) {
        next
      }

      log_scale <- sub("_est_.*$", "", est_col) %in% c("rr", "ir")
      pooled <- pool_metric(dt[[est_col]], dt[[lb_col]], dt[[ub_col]], log_scale)
      out[[est_col]] <- pooled[["est"]]
      out[[lb_col]] <- pooled[["lb"]]
      out[[ub_col]] <- pooled[["ub"]]
      n_pooled_values <- c(n_pooled_values, pooled[["n"]])
    }

    numeric_cols <- names(dt)[vapply(dt, is.numeric, logical(1))]
    pooled_cols <- unique(c(est_cols, sub("_est_", "_lb_", est_cols), sub("_est_", "_ub_", est_cols)))
    mean_cols <- setdiff(numeric_cols, pooled_cols)
    for (col in mean_cols) {
      vals <- dt[[col]]
      out[[col]] <- if (all(is.na(vals))) NA_real_ else mean(vals, na.rm = TRUE)
    }

    if ("imputation_id" %in% names(out)) {
      out[, imputation_id := NA_integer_]
    }

    # Add n_pooled column: minimum across all pooled metrics, or nrow(dt) if no metrics were pooled
    if (length(n_pooled_values) > 0L) {
      out[, n_pooled := min(n_pooled_values)]
    } else {
      out[, n_pooled := as.integer(nrow(dt))]
    }

    out
  }

  apply_subset_condition <- function(dt, condition_text) {
    cond <- if (is.null(condition_text)) "" else trimws(condition_text)
    if (!nzchar(cond)) {
      return(data.table::copy(dt))
    }

    tryCatch(
      dt[eval(parse(text = cond))],
      error = function(e) {
        logger::log_warn(glue::glue("Invalid pooling_condition '{cond}', keeping unfiltered rows: {conditionMessage(e)}"))
        data.table::copy(dt)
      }
    )
  }

  n_items <- nrow(meta)
  out_list <- vector("list", n_items)

  for (i in seq_len(n_items)) {
    dt <- lookup_list[[i]]
    if (!data.table::is.data.table(dt) || nrow(dt) == 0L) {
      out_list[[i]] <- data.table::data.table()
      next
    }

    combo <- meta[i]
    method <- if ("pooling_method" %in% names(combo)) as.character(combo$pooling_method[[1]]) else ""
    method <- trimws(ifelse(is.na(method), "", method))

    if (identical(method, "rubin")) {
      out_list[[i]] <- pool_analysis_rubin(data.table::copy(dt))
    } else if (identical(method, "subset")) {
      cond <- if ("pooling_condition" %in% names(combo)) as.character(combo$pooling_condition[[1]]) else ""
      subset_dt <- apply_subset_condition(data.table::copy(dt), cond)
      subset_dt[, n_pooled := as.integer(nrow(subset_dt))]
      out_list[[i]] <- subset_dt
    } else {
      dt[, n_pooled := as.integer(nrow(dt))]
      out_list[[i]] <- data.table::copy(dt)
    }
  }

  out_list
}
