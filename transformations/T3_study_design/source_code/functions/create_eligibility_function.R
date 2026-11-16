#' Compute D3 Eligibility Dataset
#'
#' @description
#' Computes D3_ELIGIBILITY from D3_MULTIVARIATE_EPISODES and D3_FatherChild.
#' Creates binary indicators for study inclusion criteria, as well as fatherhood outcomes.
#'
#' @param d3_episodes A data.table with person_id, start, end, and SV_* variables
#' @param d3_fatherchild A data.table with father-child relationships and conception dates
#' @param config_values A list with study period dates (start_inclusion_males, end_inclusion_males)
#'
#' @return A data.table (D3_ELIGIBILITY) with computed eligibility and outcome columns
#'
#' @details
#' Computed columns:
#' - in_study_period: spell overlaps with male enrollment period
#' - receives_exposure: on valproate only (not lev, not other ASM)
#' - receives_control: on levetiracetam only (not VPA, not other ASM)
#' - in_eligible_pop: meets all eligibility criteria
#' - eligible_exposed/eligible_control: in eligible population AND receives respective exposure
#' - Fatherhood outcomes: births within 3y9m, n pregnancies, n infants conceived after spell start, first date of birth
#'


compute_eligibility <- function(d3_episodes, d3_fatherchild, config_values) {
  # Set data.table keys
  data.table::setDT(d3_episodes)
  data.table::setDT(d3_fatherchild)

  # Extract study dates from config
  start_inclusion_males <- as.Date(lubridate::ymd(config_values$start_inclusion_males))
  end_inclusion_males <- as.Date(lubridate::ymd(config_values$end_inclusion_males))

  # Compute eligibility indicators
  # Assign `in_study_period` first so it can be referenced below
  d3 <- d3_episodes[, in_study_period := (start < end_inclusion_males) & (end > start_inclusion_males)]

  # Now compute the remaining indicators (these can safely reference `in_study_period`)
  d3[, `:=`(
    receives_exposure = (SV_IS_ON_VPA & !SV_IS_ON_LEV & !SV_IS_ON_OT_ASM),
    receives_control = (SV_IS_ON_LEV & !SV_IS_ON_VPA & !SV_IS_ON_OT_ASM),
    in_eligible_pop = (SV_AGE_BETWEEN_18_50 & SV_SEX & SV_GENEPILEPSY &
      SV_ENROLLED_12M & !SV_CONTRA_VALPROATE & !SV_INFERTILITY & in_study_period)
  )]

  # Compute eligible_exposed and eligible_control
  d3[, `:=`(
    eligible_exposed = (in_eligible_pop & receives_exposure),
    eligible_control = (in_eligible_pop & receives_control)
  )]

  # Compute fatherhood outcomes by joining with D3_FatherChild
  # For each person id and multivariate episode, find children conceived after episode start and indicator if within 3y9m
  # , n.pregnancies, n.infants, first date of birth
  # Steps:
  # 1) the by statement ensures that the expression is evaluated once for each unique combination of person_id, start, and end in d3_episodes, i.e., once per row in d3_multivariate_episodes.
  # 2) For each person_id and episode, we filter d3_fatherchild to find children where the father_id matches the person_id and the estimated_conception_date is after the episode start date.
  # 3) We then compute the outcomes based on the children found in the window:
  #    - livebirth_within_3_years: TRUE if any child was born with estimated conception data 3 years after the episode end date.
  #    - first_date_of_birth: the earliest date of birth among the children in the window.
  #    - n_pregnancies: the number of unique pregnancies (using pregnancy_id) with estimated conception after start
  #    - n_infants: the number of unique infants with estimated conception after start (using child_id)
  ### If no children is found in the window, we return FALSE for livebirth_within_3_years, NA for first_date_of_birth, and 0 for n_pregnancies and n_infants.
  # 4) Finally, we merge these computed outcomes back to the main d3 table
  d3_results <- d3[,
    {
      # Find children conceived after spell start
      children_in_window <- d3_fatherchild[
        father_id == person_id &
          estimated_conception_date > start
      ]

      if (nrow(children_in_window) == 0) {
        list(
          conception_within_3_years = FALSE,
          first_date_of_birth = data.table::as.IDate(NA_character_),
          n_pregnancies = 0L,
          n_infants = 0L
        )
      } else {
        list(
          conception_within_3_years = any(
            children_in_window$estimated_conception_date <= (as.Date(end) + lubridate::period(years = 3))
          ),
          first_date_of_birth = data.table::as.IDate(min(children_in_window$date_of_birth)),
          n_pregnancies = as.integer(length(unique(children_in_window$pregnancy_id))),
          n_infants = as.integer(length(unique(children_in_window$child_id)))
        )
      }
    },
    by = .(person_id, start, end)
  ]


  # Merge fatherhood outcomes back to main table
  d3[d3_results, on = .(person_id, start, end), `:=`(
    conception_within_3_years = i.conception_within_3_years,
    first_date_of_birth = i.first_date_of_birth,
    n_pregnancies = i.n_pregnancies,
    n_infants = i.n_infants
  )]

  d3[, person_id := as.character(person_id)]

  return(d3)
}
