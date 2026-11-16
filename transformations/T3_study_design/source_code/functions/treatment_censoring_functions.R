#' Compute treatment discontinuation dates for each T0 in the follow-up dataset
#' 
#' This function computes the treatment discontinuation dates for each T0 in the follow-up dataset based on the univariate episodes for the treatment. It identifies consecutive runs of TRUE/FALSE episodes and determines the discontinuation date as the end of the last consecutive TRUE episode. The discontinuation dates are then merged back into the follow-up dataset.
#' @param d4_fup_father A data.table containing the follow-up dataset with T0 dates
#' @param d3_episodes A data.table containing the univariate episodes for the treatment
#' @returns A data.table with the treatment discontinuation dates added for each T0
#' 
compute_treatment_discontinuation <- function(d4_fup_father, d3_episodes) {

  # Ensure episodes are ordered
  data.table::setorder(
    d3_episodes,
    person_id,
    start_episode
  )

  # 1. Identify consecutive runs of TRUE/FALSE episodes
  d3_episodes[
    ,
    run_id := data.table::rleid(value),
    by = person_id
  ]

  # 2. For each TRUE run, compute the discontinuation date
  #    (= end of the last consecutive TRUE episode)
  true_runs <- d3_episodes[
    value == TRUE,
    .(
      treatment_discontinuation = max(end_episode)
    ),
    by = .(person_id, run_id)
  ]

  # 3. Attach the discontinuation date to every TRUE episode
  episode_lookup <- data.table::merge.data.table(
    x = d3_episodes[
      value == TRUE,
      .(
        person_id,
        start_episode,
        end_episode,
        run_id
      )
    ],
    y = true_runs,
    by = c("person_id", "run_id"),
    all.x = TRUE,
    sort = FALSE
  )

  # 4. For each T0, find the TRUE episode containing it
  disc_dates <- data.table::merge.data.table(
    x = d4_fup_father,
    y = episode_lookup[
      ,
      .(
        person_id,
        start_episode,
        end_episode,
        treatment_discontinuation
      )
    ],
    by = "person_id",
    all.x = TRUE,
    allow.cartesian = TRUE
  )[
    T0 >= start_episode &
      T0 <= end_episode,
    .(
      person_id,
      T0,
      treatment_discontinuation
    )
  ]

  return(disc_dates)
}

#' Compute treatment switch dates for each T0 in the follow-up dataset
#' Construct "treatment switch" by looking at the univariate episodes of IS_ON_LEV and of IS_ON_OT_OSM. For each, find the episode with TRUE value, with earliest start date after T0. You will get two start dates (switch to levi, switch to other). take the earliest of these two dates. This is your "treatment switch" intercurrent event date.
#' @param d4_fup_father A data.table containing the follow-up dataset with T0 dates
#' @param d3_episodes A data.table containing the univariate episodes for the treatment
#' @param rename_to A string specifying the name of the new column for treatment switch dates
#' @returns A data.table with the treatment switch dates added for each T0
#' 
compute_treatment_switch <- function(d4_fup_father, d3_episodes, rename_to = "treatment_switch") {
  # Ensure episodes are ordered
  data.table::setorder(
    d3_episodes,
    person_id,
    start_episode
  )

  # 1. Identify treatment initiation episodes
  treatment_initiation <- d3_episodes[value == TRUE]

  # 2. For each T0, find the earliest treatment initiation episode after T0
  switch_dates <- data.table::merge.data.table(
    x = d4_fup_father,
    y = treatment_initiation,
    by = "person_id",
    all.x = TRUE,
    allow.cartesian = TRUE
  )[
    start_episode > T0,
    .(
      switch_date = min(start_episode)
    ),
    by = .(person_id, T0)
  ] 

  # 3. Rename the switch_date column to the specified name
  data.table::setnames(switch_dates, "switch_date", rename_to)

  # 4. Merge back to the follow-up dataset
  d4_fup_father <- data.table::merge.data.table(
    x = d4_fup_father,
    y = switch_dates,
    by = c("person_id", "T0"),
    all.x = TRUE,
    sort = FALSE
  )

  return(d4_fup_father)
}
