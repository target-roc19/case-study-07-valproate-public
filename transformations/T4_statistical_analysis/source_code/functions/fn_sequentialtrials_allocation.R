## ################################################################
# create_sequential_trial_tables ---
# Aim:
# Create Table 2 using D4_StudyCohortMales and D4_StudyCohortChild
#
# Input files: ---
# - configuration/config_project.yaml
# - data/D3_study_variables/D3_Eligibility.fst
#
# Output: ---
# - data/D5_results/D5_<DEAP>_Attrition_Table1.csv
################################################################


## Source functions attrition table so helpers are avaible
base::source(file.path("transformations", "T4_statistical_analysis", "source_code", "functions", "fn_attrition_table.R"))

## Helper function to compute summary statistics for a vector, including percentiles and counts in specified ranges
## Input: vector of trials per person count, and optionally the total individuals in the exposure group (if group-specific percentages are desired)
## Outuput:
### - min, max, percentiles 10, 25, 50, 75 and 90
### - number of individuals with 1 to 5 trials, 6 to 20 trials, 21 to 50 trials, and more than 50 trials
### - if group_total is provided, also compute the percentage of individuals in each trial count range relative to the group total

compute_vector_summary <- function(vector, group_total = NULL) {
  
  result <- list(
    min     = min(vector),
    max     = max(vector),
    p10     = quantile(vector, probs = 0.10, type = 1),
    p25     = quantile(vector, probs = 0.25, type = 1),
    p50     = quantile(vector, probs = 0.50, type = 1),
    p75     = quantile(vector, probs = 0.75, type = 1),
    p90     = quantile(vector, probs = 0.90, type = 1),
    n_1_5   = sum(vector >= 1  & vector <= 5),
    n_6_20  = sum(vector >= 6  & vector <= 20),
    n_21_50 = sum(vector >= 21 & vector <= 50),
    n_gt_50 = sum(vector > 50),
    combination = paste0(min(vector), ", ",
                      quantile(vector, probs = 0.10, type = 1), ", ",
                      quantile(vector, probs = 0.25, type = 1), ", ",
                      quantile(vector, probs = 0.50, type = 1), ", ",
                      quantile(vector, probs = 0.75, type = 1), ", ",
                      quantile(vector, probs = 0.90, type = 1), ", ",
                      max(vector))
  )
  
  if (!is.null(group_total)) {
    result <- c(result, list(
      n_1_5_perc   = .pct(numerator = result$n_1_5,   denominator = group_total),
      n_6_20_perc  = .pct(numerator = result$n_6_20,  denominator = group_total),
      n_21_50_perc = .pct(numerator = result$n_21_50, denominator = group_total),
      n_gt_50_perc = .pct(numerator = result$n_gt_50, denominator = group_total)
    ))
  }
  
  return(result)
}

# Helper function to compute sequential trial allocation statistics per cohort
## Input: 
## Cohort data.table, name of person_id colum, and total number of exposed and control individuals in the cohort (for percentage calculations)
## Output: list of statistics including:
### - total number of trial person units in the cohort, and separately for exposed and control groups
### - summary statistics for the number of trials per individual in the cohort, and separately for exposed and control groups (using compute_vector_summary). Returns min number of tirals a person was allocated to, max number of trials, percentiles, and counts of individuals with 1-5, 6-20, 21-50, and >50 trials (with percentages)

compute_statistics_per_cohort <- function(cohort, person_id_col = 'person_id', n_exposed, n_control) {
          N_trial_units <- cohort[, .N]
          n_trial_units_exp <- cohort[group == "EXPOSED", .N]
          n_trial_units_control <- cohort[group == "CONTROL", .N]

          # trials per individual
          trials_per_individual <- cohort[, .N, by = person_id_col]
          trials_per_individual_exp <- cohort[group == "EXPOSED", .N, by = person_id_col]
          trials_per_individual_control <- cohort[group == "CONTROL", .N, by = person_id_col]
          trials_per_individual_summary <- compute_vector_summary(trials_per_individual$N)
          trials_per_individual_exp_summary <- compute_vector_summary(trials_per_individual_exp$N, group_total = n_exposed)
          trials_per_individual_control_summary <- compute_vector_summary(trials_per_individual_control$N, group_total = n_control)

          output <- list(
            N_trial_units = N_trial_units,
            n_trial_units_exp = n_trial_units_exp,
            n_trial_units_control = n_trial_units_control,
            trials_per_individual_summary = trials_per_individual_summary,
            trials_per_individual_exp_summary = trials_per_individual_exp_summary,
            trials_per_individual_control_summary = trials_per_individual_control_summary
          )
}


## Function to create sequential trials table 2
## Input:
## - d4_males_cohort: data.table of the D4 study cohort
## - d4_child_cohort: data.table of the D4 study cohort
## Output:
## - data.table with the sequential trials table 2, including counts and percentages for the overall cohort, exposed group, and control group for various metrics (number of unique eligible  males, number of unique pregnancies, number of unique children, number of trial units, and distribution of trials per individual)


create_sequential_trials_table2 <- function(d4_males_cohort, d4_child_cohort) {

N_a <- d4_males_cohort[, data.table::uniqueN(person_id)]
N_b <- d4_males_cohort[conception_within_3_years == TRUE, data.table::uniqueN(person_id)]
N_c <- d4_child_cohort[, data.table::uniqueN(pregnancy_id)]
N_d <- d4_child_cohort[, data.table::uniqueN(child_id)]

# Now same but per group

N_a1 <- d4_males_cohort[group == 'EXPOSED', data.table::uniqueN(person_id)]
N_b1 <- d4_males_cohort[group == 'EXPOSED' & conception_within_3_years == TRUE, data.table::uniqueN(person_id)]
N_c1 <- d4_child_cohort[group == 'EXPOSED', data.table::uniqueN(pregnancy_id)]
N_d1 <- d4_child_cohort[group == 'EXPOSED', data.table::uniqueN(child_id)]

N_a2 <- d4_males_cohort[group == 'CONTROL', data.table::uniqueN(person_id)]
N_b2 <- d4_males_cohort[group == 'CONTROL' & conception_within_3_years == TRUE, data.table::uniqueN(person_id)]
N_c2 <- d4_child_cohort[group == 'CONTROL', data.table::uniqueN(pregnancy_id)]
N_d2 <- d4_child_cohort[group == 'CONTROL', data.table::uniqueN(child_id)]


statistics_male_cohort <- compute_statistics_per_cohort(d4_males_cohort, person_id_col = 'person_id', n_exposed = N_a1, n_control = N_a2)
statistics_father_cohort <- compute_statistics_per_cohort(d4_males_cohort[conception_within_3_years == TRUE], person_id_col = 'person_id', n_exposed = N_b1, n_control = N_b2)
statistics_child_cohort <- compute_statistics_per_cohort(d4_child_cohort, person_id_col = 'child_id', n_exposed = N_c1, n_control = N_c2)

## Now organize in table

# Build shell-aligned row labels and values in final reporting order.
  table_2 <- data.table::data.table(
    Label = c(
          # Males
          "Number of unique eligible males exposed to one of the drugs",
          "Number of unique eligible males fathering at least one livebirth exposed to one of the drugs",
          # Pregnancies & children
          "Number of unique pregnancies that end in one or more livebirths included in the analysis",
          "Number of children born alive included in the analysis",
          # Male-trial units
          "Number of male-trial units",
          "Number of different trials an individual (male) was allocated to (min, percentiles 10%, 25%, 50%, 75%, 90%, max)",
          "1-5",
          "6-20",
          "21-50",
          "50+",
          # Father-trial units
          "Number of father-trial units (same as pregnancy-trial units)",
          "Number of different trials a male fathering a livebirth was allocated to (min, percentiles 10%, 25%, 50%, 75%, 90%, max)",
          "1-5",
          "6-20",
          "21-50",
          "50+",
          # Children-trial units
          "Number of children-trial units",
          "Number of different trials a child was allocated to (min, percentiles 10%, 25%, 50%, 75%, 90%, max)",
          "1-5",
          "6-20",
          "21-50",
          "50+"

          ),
    Count = c(.format_count(N_a), # Row 1 count.
              .format_count(N_b), # Row 2 count.
              .format_count(N_c), # Row 3 count.
              .format_count(N_d), # Row 4 count.
              .format_count(statistics_male_cohort$N_trial_units), # Row 5 count.
               statistics_male_cohort$trials_per_individual_summary$combination, # Row 6 count.
              .format_count(statistics_male_cohort$trials_per_individual_summary$n_1_5), # Row 7 count.
              .format_count(statistics_male_cohort$trials_per_individual_summary$n_6_20), # Row 8 count.
              .format_count(statistics_male_cohort$trials_per_individual_summary$n_21_50), # Row 9 count.
              .format_count(statistics_male_cohort$trials_per_individual_summary$n_gt_50), # Row 10 count.
              .format_count(statistics_father_cohort$N_trial_units), # Row 11 count.
              statistics_father_cohort$trials_per_individual_summary$combination, # Row 12 count.
              .format_count(statistics_father_cohort$trials_per_individual_summary$n_1_5), # Row 13 count.
              .format_count(statistics_father_cohort$trials_per_individual_summary$n_6_20), # Row 14 count.
              .format_count(statistics_father_cohort$trials_per_individual_summary$n_21_50), # Row 15 count.
              .format_count(statistics_father_cohort$trials_per_individual_summary$n_gt_50), # Row 16 count.
              .format_count(statistics_child_cohort$N_trial_units), # Row 17 count.
              statistics_child_cohort$trials_per_individual_summary$combination, # Row 18 count.
              .format_count(statistics_child_cohort$trials_per_individual_summary$n_1_5), # Row 19 count.
              .format_count(statistics_child_cohort$trials_per_individual_summary$n_6_20), # Row 20 count.
              .format_count(statistics_child_cohort$trials_per_individual_summary$n_21_50), # Row 21 count.
              .format_count(statistics_child_cohort$trials_per_individual_summary$n_gt_50) # Row 22 count.
              ),     
    Count_Valproate = c(.format_count(N_a1), # Row 1 count.
              .format_count(N_b1), # Row 2 count.
              .format_count(N_c1), # Row 3 count.
              .format_count(N_d1), # Row 4 count.
              .format_count(statistics_male_cohort$n_trial_units_exp), # Row 5 count.
              statistics_male_cohort$trials_per_individual_exp_summary$combination, # Row 6 count.
              .format_count(statistics_male_cohort$trials_per_individual_exp_summary$n_1_5), # Row 7 count.
              .format_count(statistics_male_cohort$trials_per_individual_exp_summary$n_6_20), # Row 8 count.
              .format_count(statistics_male_cohort$trials_per_individual_exp_summary$n_21_50), # Row 9 count.
              .format_count(statistics_male_cohort$trials_per_individual_exp_summary$n_gt_50), # Row 10 count.        
               .format_count(statistics_father_cohort$n_trial_units_exp), # Row 11 count.
               statistics_father_cohort$trials_per_individual_exp_summary$combination, # Row 12 count.
              .format_count(statistics_father_cohort$trials_per_individual_exp_summary$n_1_5), # Row 13 count.
              .format_count(statistics_father_cohort$trials_per_individual_exp_summary$n_6_20), # Row 14 count.
              .format_count(statistics_father_cohort$trials_per_individual_exp_summary$n_21_50), # Row 15 count.
              .format_count(statistics_father_cohort$trials_per_individual_exp_summary$n_gt_50), # Row 16 count.
              .format_count(statistics_child_cohort$n_trial_units_exp), # Row 17 count.
              statistics_child_cohort$trials_per_individual_exp_summary$combination, # Row 18 count.
              .format_count(statistics_child_cohort$trials_per_individual_exp_summary$n_1_5), # Row 19 count.
              .format_count(statistics_child_cohort$trials_per_individual_exp_summary$n_6_20), # Row 20 count.
              .format_count(statistics_child_cohort$trials_per_individual_exp_summary$n_21_50), # Row 21 count.     
              .format_count(statistics_child_cohort$trials_per_individual_exp_summary$n_gt_50) # Row 22 count.
              ),
    Percentage_Valproate = c(.pct(N_a1, N_a), # Row 1 percentage.
              .pct(N_b1, N_b), # Row 2 percentage.
              .pct(N_c1, N_c), # Row 3 percentage.
              .pct(N_d1, N_d), # Row 4 percentage.
              .pct(statistics_male_cohort$n_trial_units_exp, statistics_male_cohort$N_trial_units), # Row 5 percentage.
              NA,
              .pct(statistics_male_cohort$trials_per_individual_exp_summary$n_1_5, N_a1), # Row 7 percentage.
              .pct(statistics_male_cohort$trials_per_individual_exp_summary$n_6_20, N_a1), # Row 8 percentage.
              .pct(statistics_male_cohort$trials_per_individual_exp_summary$n_21_50, N_a1), # Row 9 percentage.
              .pct(statistics_male_cohort$trials_per_individual_exp_summary$n_gt_50, N_a1), # Row 10 percentage.
              .pct(statistics_father_cohort$n_trial_units_exp, statistics_father_cohort$N_trial_units), # Row 11 percentage.
              NA,
              .pct(statistics_father_cohort$trials_per_individual_exp_summary$n_1_5, N_b1), # Row 13 percentage.   
              .pct(statistics_father_cohort$trials_per_individual_exp_summary$n_6_20, N_b1), # Row 14 percentage.
              .pct(statistics_father_cohort$trials_per_individual_exp_summary$n_21_50, N_b1), # Row 15 percentage.
              .pct(statistics_father_cohort$trials_per_individual_exp_summary$n_gt_50, N_b1), # Row 16 percentage.,
              .pct(statistics_child_cohort$n_trial_units_exp, statistics_child_cohort$N_trial_units), # Row 17 percentage.
              NA,
              .pct(statistics_child_cohort$trials_per_individual_exp_summary$n_1_5, N_d1), # Row 19 percentage.
              .pct(statistics_child_cohort$trials_per_individual_exp_summary$n_6_20, N_d1), # Row 20 percentage.
              .pct(statistics_child_cohort$trials_per_individual_exp_summary$n_21_50, N_d1), # Row 21 percentage.
              .pct(statistics_child_cohort$trials_per_individual_exp_summary$n_gt_50, N_d1) # Row 22 percentage.
              ),
    Count_Control = c(.format_count(N_a2), # Row 1 count.
              .format_count(N_b2), # Row 2 count.
              .format_count(N_c2), # Row 3 count.
              .format_count(N_d2), # Row 4 count.                     
              .format_count(statistics_male_cohort$n_trial_units_control), # Row 5 count.
              statistics_male_cohort$trials_per_individual_control_summary$combination, # Row 6 count.
              .format_count(statistics_male_cohort$trials_per_individual_control_summary$n_1_5), # Row 7 count.
              .format_count(statistics_male_cohort$trials_per_individual_control_summary$n_6_20), # Row 8 count.
              .format_count(statistics_male_cohort$trials_per_individual_control_summary$n_21_50), # Row 9 count.
              .format_count(statistics_male_cohort$trials_per_individual_control_summary$n_gt_50), # Row 10 count.
              .format_count(statistics_father_cohort$n_trial_units_control), # Row 11 count.
              statistics_father_cohort$trials_per_individual_control_summary$combination, # Row 12 count.
              .format_count(statistics_father_cohort$trials_per_individual_control_summary$n_1_5), # Row 13 count.
              .format_count(statistics_father_cohort$trials_per_individual_control_summary$n_6_20), # Row 14 count.
              .format_count(statistics_father_cohort$trials_per_individual_control_summary$n_21_50), # Row 15 count.
              .format_count(statistics_father_cohort$trials_per_individual_control_summary$n_gt_50), # Row 16 count.
              .format_count(statistics_child_cohort$n_trial_units_control), # Row 17 count.
              statistics_child_cohort$trials_per_individual_control_summary$combination, # Row 18 count.
              .format_count(statistics_child_cohort$trials_per_individual_control_summary$n_1_5), # Row 19 count.
              .format_count(statistics_child_cohort$trials_per_individual_control_summary$n_6_20), # Row 20 count.
              .format_count(statistics_child_cohort$trials_per_individual_control_summary$n_21_50), # Row 21 count.
              .format_count(statistics_child_cohort$trials_per_individual_control_summary$n_gt_50) # Row 22 count.
              ),
          Percentage_Control = c(.pct(N_a2, N_a), # Row 1 percentage.
              .pct(N_b2, N_b), # Row 2 percentage.
              .pct(N_c2, N_c), # Row 3 percentage.
              .pct(N_d2, N_d), # Row 4 percentage.
              .pct(statistics_male_cohort$n_trial_units_control, statistics_male_cohort$N_trial_units), # Row 5 percentage.
                      NA,
              .pct(statistics_male_cohort$trials_per_individual_control_summary$n_1_5, N_a2), # Row 7 percentage.
              .pct(statistics_male_cohort$trials_per_individual_control_summary$n_6_20, N_a2), # Row 8 percentage.
              .pct(statistics_male_cohort$trials_per_individual_control_summary$n_21_50, N_a2), # Row 9 percentage.
              .pct(statistics_male_cohort$trials_per_individual_control_summary$n_gt_50, N_a2) # Row 10 percentage.
              ,
              .pct(statistics_father_cohort$n_trial_units_control, statistics_father_cohort$N_trial_units), # Row 11 percentage.
                      NA,
                      .pct(statistics_father_cohort$trials_per_individual_control_summary$n_1_5, N_b2), # Row 13 percentage.
                      .pct(statistics_father_cohort$trials_per_individual_control_summary$n_6_20, N_b2), # Row 14 percentage.
                              .pct(statistics_father_cohort$trials_per_individual_control_summary$n_21_50, N_b2), # Row 15 percentage.
                              .pct(statistics_father_cohort$trials_per_individual_control_summary$n_gt_50, N_b2), # Row 16 percentage.
                      .pct(statistics_child_cohort$n_trial_units_control, statistics_child_cohort$N_trial_units), # Row 17 percentage.
              NA,
              .pct(statistics_child_cohort$trials_per_individual_control_summary$n_1_5, N_d2), # Row 19 percentage.
              .pct(statistics_child_cohort$trials_per_individual_control_summary$n_6_20, N_d2), # Row 20 percentage.
              .pct(statistics_child_cohort$trials_per_individual_control_summary$n_21_50, N_d2), # Row 21 percentage.
              .pct(statistics_child_cohort$trials_per_individual_control_summary$n_gt_50, N_d2) # Row 22 percentage.
              ) )

return(table_2)

}
