

GROUPS <- c("OVERALL", "EXPOSED", "CONTROL")

# Weighted N/perc/aux for a single output row
weighted_row_stats <- function(x, w, type, label, lvl, tw) {
  if (all(is.na(x))) {
    return(rep(NA_real_, 3))
  }
  key <- if (type %in% c("TF", "CAT")) type else label
  switch(
    key,
    TF = {
      n <- sum(w[!is.na(x) & x == TRUE], na.rm = TRUE)
      c(n, 100 * n / tw, NA_real_)
    },
    CAT = {
      n <- sum(w[!is.na(x) & x == lvl], na.rm = TRUE)
      c(n, 100 * n / tw, NA_real_)
    },
    "Median (Q1, Q3)" = {
      q <- Hmisc::wtd.quantile(x, w, c(0.25, 0.5, 0.75), na.rm = TRUE)
      c(q[2], q[1], q[3])
    },
    "Min, Max" = c(
      suppressWarnings(min(x, na.rm = TRUE)),
      suppressWarnings(max(x, na.rm = TRUE)),
      NA_real_
    ),
    "Mean (SD)" = {
      mu <- stats::weighted.mean(x, w, na.rm = TRUE)
      sdw <- sqrt(sum(w * (x - mu)^2, na.rm = TRUE) / sum(w, na.rm = TRUE))
      c(mu, sdw, NA_real_)
    },
    rep(NA_real_, 3)
  )
}

#' Baseline characteristics table for TARGET CS02
#'
#' Restricts cohort to `include_after_trimming == TRUE`, calls
#' `DescriptiveTable::DescriptivesTable()` for the unweighted layout
#' (Overall + EXPOSED + CONTROL N/perc/aux, NUM2 median/IQR,
#' expectedCat handling), computes the matching IPTW-weighted N/perc/aux
#' row-by-row (DescriptiveTable's count_* ignore weights), and attaches
#' unweighted + IPTW-weighted aSMD columns from
#' `DescriptiveTable::compute_asd()`.
#'
#' Output columns:
#'   label, var, type,
#'   N/perc/aux unwt × {overall, exposed, control},
#'   N/perc/aux wt   × {overall, exposed, control},
#'   asd_unwt, asd_wt.
#'
#' @param d4_covariates D4_StudyCohort_Covariates.
#' @param d4_iptw D4_StudyCohort_IPTW.
#' @param metadata DescriptiveTable-style metadata; columns
#' @param fathers Optional flag to restrict population to individuals who father a livebirth
#' @param remove.NA.weights Flag, remove rows with NA weights (TRUE) or keep them (FALSE)
#' @param weight_col_name
#' 
#'   `var; type; expectedCat; label; parent; parent_cat; header`.
build_baseline_table <- function(
  d4_covariates,
  d4_iptw,
  metadata,
  mask = FALSE,
  fathers = FALSE,
  remove.NA.weights = TRUE,
  weight_col_name = 'stabilized_trunc_iptw'
) {
  metadata <- data.table::as.data.table(metadata)
  cov_dt <- data.table::as.data.table(d4_covariates)
  iptw <- data.table::as.data.table(d4_iptw)
  cov_dt[, `:=`(person_id = as.character(person_id), T0 = as.Date(T0))]
  iptw[, `:=`(person_id = as.character(person_id), T0 = as.Date(T0))]

  # cohort and iptw
  cohort <- data.table::merge.data.table(
    cov_dt,
    iptw[,
      # include_after_trimming == TRUE, do not include after trimming
      .(person_id, T0, w = as.numeric(get(weight_col_name)))
    ],
    by = c("person_id", "T0")
  )

  if(remove.NA.weights){
    cohort <- cohort[!is.na(w)]
    logger::log_warn("Removed ", sum(is.na(cohort$w)), " rows with NA weights to create baseline descriptive table")
  }

  if(fathers){
  cohort <- cohort[conception_within_3_years == TRUE]
  }

  cohort <- cohort[,
    intersect(c("group", "w", metadata$var), names(cohort)),
    with = FALSE
  ]

  # Coerce each metadata column to the type that DescriptivesTable expects
  for (i in seq_len(nrow(metadata))) {
    v <- metadata$var[i]
    if (!v %in% names(cohort)) {
      next
    }
    coerce <- switch(
      metadata$type[i],
      TF = as.logical,
      CAT = as.character,
      NUM1 = ,
      NUM2 = function(x) suppressWarnings(as.numeric(x)),
      identity
    )
    data.table::set(cohort, j = v, value = coerce(cohort[[v]]))
  }

  # Create group = "OVERALL" so DescriptivesTable creates
  # V*_OVERALL
  pop <- data.table::rbindlist(list(
    cohort,
    data.table::copy(cohort)[, group := "OVERALL"]
  ))
  out <- data.table::as.data.table(DescriptiveTable::DescriptivesTable(
    popdf = pop,
    table_metadata = metadata,
    groupcol = "group",
    output_format = "processed",
    calculate_asd = FALSE,
    keep_varinfo = TRUE,
    control_types = FALSE,
    round_decimals = 3,
    output_asd = FALSE
  ))

  # Weighted N/perc/aux per row
  pop_by_g <- list(
    OVERALL = cohort,
    EXPOSED = cohort[group == "EXPOSED"],
    CONTROL = cohort[group == "CONTROL"]
  )
  # Commpute total weight by group
  total_w <- round(sapply(pop_by_g, function(p) sum(p$w, na.rm = TRUE)), 3)
  # Add placeholder columns with weights overall, exposed, control
  # 1,2,,3 for N, percentage, aux
  for (g in GROUPS) {
    out[, paste0("W", 1:3, "_", g) := NA_real_]
  }

  for (r in seq_len(nrow(out))) {
    v <- out$var[r]
    if (is.na(v)) {
      next
    } # header row
    if (v == "Total") {
      for (g in GROUPS) {
        out[r, (paste0("W1_", g)) := total_w[[g]]]
      }
      next
    }
    if (!v %in% names(cohort)) {
      next
    }
    for (g in GROUPS) {
      p <- pop_by_g[[g]]
      s <- weighted_row_stats(
        p[[v]],
        p$w,
        out$type[r],
        out$label[r],
        out$cat[r],
        total_w[[g]]
      )
      out[r, (paste0("W", 1:3, "_", g)) := as.list(round(s, 3))]
    }
  }

  # aSMDs: compute_asd returns one row per variable
  asd_unwt <- DescriptiveTable::compute_asd(
    CovariatesInformation = cohort,
    metadata = metadata[, .(var, type)],
    group_names = c("EXPOSED", "CONTROL"),
    referenceExtension = "unwt",
    use_weights = FALSE
  )
  asd_wt <- DescriptiveTable::compute_asd(
    CovariatesInformation = cohort,
    metadata = metadata[, .(var, type)],
    group_names = c("EXPOSED", "CONTROL"),
    referenceExtension = "wt",
    use_weights = "w"
  )
  idx <- match(out$label, metadata$label)
  out[, `:=`(
    asd_unwt = round(as.numeric(asd_unwt$asd_unwt)[idx], 3),
    asd_wt = round(as.numeric(asd_wt$asd_wt)[idx], 3)
  )]

  # mask the unweighted EXPOSED/CONTROL cell counts
  # + percentages
  if (isTRUE(mask)) {
    out <- data.table::as.data.table(DescriptiveTable::mask_vector_wrapper(
      out,
      threshold = 5,
      count.names = c("V1_CONTROL", "V1_EXPOSED"),
      pct.names = c("V2_CONTROL", "V2_EXPOSED"),
      table_metadata = metadata
    ))
  }

  # Drop DescriptiveTable varinfo
  out[, c("id", "cat", "parentv", "parent_catv", "m_id") := NULL]
  for (g in GROUPS) {
    data.table::setnames(
      out,
      c(paste0("V", 1:3, "_", g), paste0("W", 1:3, "_", g)),
      c(
        paste0(c("N", "perc", "aux"), "_unwt_", tolower(g)),
        paste0(c("N", "perc", "aux"), "_wt_", tolower(g))
      )
    )
  }
  data.table::setcolorder(
    out,
    c(
      "label",
      "var",
      "type",
      "N_unwt_overall",
      "perc_unwt_overall",
      "aux_unwt_overall",
      "N_unwt_exposed",
      "perc_unwt_exposed",
      "aux_unwt_exposed",
      "N_unwt_control",
      "perc_unwt_control",
      "aux_unwt_control",
      "N_wt_overall",
      "perc_wt_overall",
      "aux_wt_overall",
      "N_wt_exposed",
      "perc_wt_exposed",
      "aux_wt_exposed",
      "N_wt_control",
      "perc_wt_control",
      "aux_wt_control",
      "asd_unwt",
      "asd_wt"
    )
  )
  out[]
}

