#' Create D4 Study Cohort with Monthly Trial Structure
#'
#' @description
#' Creates a monthly trial structure from January 2010 to March 2016 and identifies
#' study cohort members by checking for overlaps between individual eligibility spells
#' and trial periods. Also assigns individuals to treatment group (EXPOSED or CONTROL) in each trial.
#'
#' @param d3_eligiblity A data.table containing eligibility information (d3 codebook object)
#' @return A data.table with one row per person-trial combination containing (d4 codebook objetc)
#'
#' @details
#' The function performs the following steps:
#' 1. Generates monthly trial periods from 2010-01-01 to 2016-03-01
#' 2. Filters individual spells with eligible_exposed or eligible_control status
#' 3. Uses data.table::foverlaps to identify spell-trial overlaps
#' 4. Keeps only the first spell when multiple spells overlap with the same trial
#' 5. Assigns treatment group based on eligible_exposed status
#'
#' @importFrom data.table data.table setkey foverlaps setorder
#' @importFrom lubridate ymd days_in_month
library(data.table)
create_d4_studycohort <- function(d3.eligibility, bootstrap = FALSE, current.boot.id = 1) {
  # 1. Create a sequence of monthly trials (Jan 2010 to Mar 2016)
  # Generate trial start dates for each month in the specified range
  trial_start_dates <- seq(lubridate::ymd("2010-01-01"), lubridate::ymd("2016-03-01"), by = "month")
  # Create data.table with trial IDs and corresponding start and end dates
  trials <- data.table::data.table(
    trial_id = 1:length(trial_start_dates),
    trial_start = trial_start_dates,
    trial_end = trial_start_dates + lubridate::days_in_month(trial_start_dates) - 1
  )
  # 2. Filter eligible spells from D3_ELIGIBILITY
  d3.eligibility <- d3.eligibility[eligible_exposed == TRUE | eligible_control == TRUE, ]

  # 3. Checking for overlaps between spells and trial periods using data.table's foverlaps function
  data.table::setkey(d3.eligibility, start, end)
  data.table::setkey(trials, trial_start, trial_end)

  results <- data.table::foverlaps(d3.eligibility[, .(person_id, start, end, eligible_exposed)],
    trials,
    by.x = c("start", "end"),
    by.y = c("trial_start", "trial_end"),
    type = "any",
    nomatch = 0L
  )
  # Assing treatment group based on eligibility_exposed
  results[, group := ifelse(eligible_exposed == TRUE, "EXPOSED", "CONTROL")]

  # When multiple spells overlap with the same trial, we will keep only the first spell (i.e., the one with the earliest start date) to avoid a person entering a trial more than once. This is done by ordering the overlaps by trial_id, person_id, and start (spell start), and then keeping only the first occurrence of each person_id within each trial_id.
  data.table::setorder(results, trial_id, person_id, start)

  results <- results[!duplicated(results[, .(person_id, trial_id)]), ]

  # Generate T0 as the later of the trial start date and the spell start date
  results[, T0 := pmax(start, trial_start)]
  if (bootstrap) {
    # extract unique person_ids from results table
    unique.ids <- unique(results$person_id)
    # each bootstrap resample sample size is equal to the number of unique ids
    n_persons <- length(unique.ids)
    # create a bootstrap resample: sample ids with replacement from the unique person_ids object
    # Store into a data.table for merge
    resample <- data.table(person_id = as.character(sample(unique.ids, size = n_persons, replace = TRUE)))

    # Now we add the information on how many times each person_id was resampled in
    # a new variable, boot_person_id, which is a combination of the person_id and the number of times it was resampled (e.g., if person_id 123 was resampled 3 times, we will have boot_person_id values of "123_1", "123_2", "123_3" for that person_id in the bootstrap sample).
    ## Create a dataset with one row per resample occurrence
    bootstrap.rows <- resample[, .(person_id)]
    # Add sequential numbering within each person_id (1, 2, 3, ..., N)
    bootstrap.rows[, occurrence := seq_len(.N), by = person_id]
    # Create boot_person_id using the sequential number
    bootstrap.rows[, boot_person_id := paste0(person_id, "_", occurrence)]
    # Select only the needed columns
    bootstrap.rows <- bootstrap.rows[, .(person_id, boot_person_id)]

    # Merge to finalize bootstrap
    ## In the results table, keep only the rows for the person_ids that were resampled, as many times as they were resampled
    ## (It's a left_join: we keep all rows in bootstrap.rows, which has one row per resampled person_id, and we add the columns from results for the corresponding person_id. If a person_id was resampled multiple times, we will have multiple rows for that person_id in bootstrap.rows, and we will keep all those rows in the final dataset, with the corresponding info from results)
    results[, person_id := as.character(person_id)] # Ensure person_id is character for the join
    results <- results[bootstrap.rows, on = "person_id", allow.cartesian = TRUE]

    # Add the current bootstrap iteration ID to the results
    results[, boot_id := current.boot.id]
  } else {
    results[, boot_id := 0]
    results[, boot_person_id := paste0(person_id, "_", 1)]
  }

  ## Order the final dataset by person_id, trial_start, boot_person_id to ensure consistency
  data.table::setorder(results, person_id, trial_start, boot_person_id)
  ## Change data.types according to codebook
  results[, boot_id := as.character(boot_id)]
  results[, trial_start := as.IDate(trial_start)]
  results[, trial_end := as.IDate(trial_end)]
  results[, person_id := as.character(person_id)]
  results[, T0 := as.IDate(T0)]
  results[, start := as.IDate(start)]
  results[, end := as.IDate(end)]
  results <- results[, .(trial_id, trial_start, trial_end, person_id, group, T0, start, end, boot_id, boot_person_id)]
  return(results)
}
