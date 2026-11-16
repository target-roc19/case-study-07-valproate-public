# ---------------------------------------------------------------
# Step: create_iptw_tables
#
# Input:  D4_StudyCohort_IPTW
#         D4_StudyCohort_IPTW_Mother
#         D4_StudyCohort_IPTW_MotherFather
#         D4_StudyCohort_Covariates
#         D4_StudyCohort_Covariates_Mother
#         D4_StudyCohort_Covariates_MotherFather
#         D5_PS_Coef.csv
#         D5_PS_Coef_MotherFather.csv
#         BaselineDescriptives_Metadata.csv
#         BaselineDescriptives_Metadata_Mother.csv
#         BaselineDescriptives_Metadata.csv (for fathers and mothers)
#
# Output: 
#
# Diagnostics for propensity scores and IPT weights.
# ---------------------------------------------------------------

# --- Initial setup of the environment ----
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("create_iptw_tables.R")
  lm$start_capturing_prints()
}

logger::log_info("[create_iptw_tables] - START")

# --- Config loading ---
picard::load_config()
config_iptw_tables <- config_project$create_iptw_tables

# --- Source functions ---
#source(file.path(config_iptw_tables$functions_dir, "baseline_table_function.R"))
source(file.path(config_iptw_tables$functions_dir, "create_iptw_helpers.R"))

# Load d4_IPTW, d4_covariates, d5_ps_coef, and ps_variables codebooks for males
d4_male_covariates <- picard::load(config_iptw_tables$males$d4_covariates)
d4_male_iptw       <- picard::load(config_iptw_tables$males$d4_iptw)
d5_male_ps_coef    <- picard::load(config_iptw_tables$males$d5_ps_coef)
ps_variables_male  <- picard::load(config_iptw_tables$males$ps_variables, sep = ";")
# Load mother cvoariates and ps variable codebooks
d4_mother_covariates <- picard::load(config_iptw_tables$mothers$d4_covariates)
d4_mother_iptw <- picard::load(config_iptw_tables$mothers$d4_iptw)
ps_variables_mother  <- picard::load(config_iptw_tables$mothers$ps_variables, sep = ";")
# Load combined father and mothers (child) cohort with covariates, weights, and ps coefficient
d4_combined_covariates <- picard::load(config_iptw_tables$combined_mother_father$d4_covariates) # combined father + mother; person_id is child_id
d4_combined_iptw       <- picard::load(config_iptw_tables$combined_mother_father$d4_iptw)
d5_combined_ps_coef    <- picard::load(config_iptw_tables$combined_mother_father$d5_ps_coef)
# Load principal stratum weights, coefficients, and variables
d4_ipsmw <- picard::load(config_iptw_tables$principal_stratum_models$d4_ipsmw)
d4_principal_stratum_coef <- picard::load(config_iptw_tables$principal_stratum_models$d5_principal_stratum_coef)
principal_stratum_variables <- picard::load(config_iptw_tables$principal_stratum_models$d5_principal_stratum_coef, sep = ";")


# Update metadata so that age, calendar year and ASM previous categories
# are based on the ones observed in the covariates table
# Males / fathers 
metadata_descriptives_males <- picard::load(config_iptw_tables$males$baseline_metadata)
metadata_descriptives_males <- update_metadata_categories(
  covariates   = d4_combined_covariates <- picard::load(config_iptw_tables$combined_mother_father$d4_covariates) # combined father + mother; person_id is child_id
,
  metadata     = metadata_descriptives_males,
  age_var      = "SV_AGE_FATHER_CAT",
  cohort_label = "father"
)
# Mother
metadata_descriptives_mothers <- picard::load(config_iptw_tables$mothers$baseline_metadata)
metadata_descriptives_mothers <- update_metadata_categories(
  covariates   = d4_mother_covariates,
  metadata     = metadata_descriptives_mothers,
  age_var      = "SV_AGE_MOTHER_CAT",
  cohort_label = "mother"
)

########## Created objects merging covariate and IPTW
# Merge covariates with truncated weights to have the study cohort population

# This cohort is not duplicated by children 
cov_with_weight_males <- data.table::merge.data.table(
  d4_male_covariates,
  d4_male_iptw[, .(person_id, T0, stabilized_trunc_iptw)],
  by = c("person_id", "T0")
)

cov_with_weights_mothers <- data.table::merge.data.table(
  d4_mother_covariates,
  d4_mother_iptw[, .(mother_id, child_id, T0, stabilized_trunc_iptw)],
  by = c("mother_id", "T0", 'child_id') # merge on mother id,
                                          # adding child_id prevents duplicates in the merge, as mothers can have multiple children
)

cov_with_stratum_weights_males <- data.table::merge.data.table(
  d4_male_covariates,
  d4_ipsmw[, .(person_id, T0, ipsmw_raw)], 
  by = c("person_id", "T0")
)

cov_with_weights_combined_analyses <- data.table::merge.data.table(
  x = d4_combined_covariates,
  y = d4_combined_iptw[, .(person_id, father_id, mother_id, child_id, T0, stabilized_trunc_iptw)],
  by = c("father_id", 'mother_id', 'child_id', "T0")
)

if(any(
  nrow(cov_with_weight_males) > nrow(d4_male_covariates),
  nrow(cov_with_weights_mothers) > nrow(d4_mother_covariates),
  nrow(cov_with_stratum_weights_males) > nrow(d4_male_covariates)
)) {
  logger::log_error("Some covariates have more rows than the original covariates table. Check for duplicates.")
}

# ==============================================================================================
################################################################################################
#################### Table 3. Baseline descriptives before and after weighting #################
################################################################################################
# ==============================================================================================
logger::log_info("Computing Tables of Baseline descriptives before and after weigthing")


table3_males <- baseline_descriptives(covariates_with_weights = cov_with_weight_males,
metadata = metadata_descriptives_males)

table3_fathers <- baseline_descriptives(covariates_with_weights = cov_with_weight_males[conception_within_3_years == TRUE],
metadata = metadata_descriptives_males)

table3_mothers <- baseline_descriptives(covariates_with_weights = cov_with_weights_mothers,
metadata = metadata_descriptives_mothers)

# This needs to be based on
combined_metadata <- rbind(metadata_descriptives_males, metadata_descriptives_mothers)
# Metadata should be combined (maybe row bind the two metadata tables?)

table3_combined <- baseline_descriptives(covariates_with_weights = cov_with_weights_combined_analyses,
metadata = combined_metadata)

picard::save(
  data = table3_males,
  file_path = 'data/D5_results',
  file_name = paste0(config_iptw_tables$output_names$table_baseline_descriptives, '_MALES.csv')
)

picard::save(
  data = table3_fathers,
  file_path = 'data/D5_results',
  file_name = paste0(config_iptw_tables$output_names$table_baseline_descriptives, '_FATHERS.csv')
)

picard::save(
  data = table3_mothers,
  file_path = 'data/D5_results',
  file_name = paste0(config_iptw_tables$output_names$table_baseline_descriptives, '_MOTHERS.csv')
)

picard::save(
  data = table3_combined,
  file_path = 'data/D5_results',
  file_name = paste0(config_iptw_tables$output_names$table_baseline_descriptives, '_COMBINED_MOTHER_FATHER.csv')
)



# ==============================================================================================
################################################################################################
#################### # Table 6. Description of propensity score model to compute weights in ####
####################### terms of prevalences of categorical variables.      ####################
################################################################################################
# ==============================================================================================

# reported for males, combined and principal stratum
logger::log_info("Table 6 - Description of propensity score model to compute weights in terms of prevalences of categorical variables")

table6_males <- create_prevalence_coefficients_table(table3 = table3_males, ps_coef = d5_male_ps_coef)

combined_table3 <- data.table::rbindlist(list(table3_males, table3_mothers), use.names = TRUE, fill = TRUE)
table6_fathermothers <- create_prevalence_coefficients_table(table3 = combined_table3, ps_coef = d5_combined_ps_coef)
table6_principalstratum <- create_prevalence_coefficients_table(table3 = table3_males, ps_coef = d4_principal_stratum_coef)

# save
picard::save(
  table6_males,
  file_path = config_iptw_tables$output_dir,
  file_name = paste0(config_iptw_tables$output_names$table_estimates_and_prevalance, 'MALES.csv')
)

picard::save(
  table6_fathermothers,
  file_path = config_iptw_tables$output_dir,
  file_name = paste0(config_iptw_tables$output_names$table_estimates_and_prevalance, 'FATHERS_AND_MOTHERS.csv')
)

picard::save(
  table6_principalstratum,
  file_path = config_iptw_tables$output_dir,
  file_name = paste0(config_iptw_tables$output_names$table_estimates_and_prevalance, 'PRINCIPAL_STRATUM.csv')
)

#################################################################################################
#################### # Table 7.  Description and diagnostics for propensity scores and stabilised
# ################## IPT weights valproate vs levetiracetam cohort in VID     ###################
#################################################################################################

logger::log_info("Creating weight description table")

table7_main <- table7(selected_iptw = d4_male_iptw, 
                    weights_column_name = 'stabilized_trunc_iptw', 
                    propensity_score_name = 'p_score', 
                    truncation_bounds = config_iptw_tables$ps_truncation_bounds)

table7_combined <- table7(selected_iptw = d4_combined_iptw, 
                    weights_column_name = 'stabilized_trunc_iptw', 
                    propensity_score_name = 'p_score', 
                    truncation_bounds = config_iptw_tables$ps_truncation_bounds)

table7_principalstratum <- table7(selected_iptw = d4_ipsmw[conception_within_3_years == TRUE], 
                    weights_column_name = 'ipsmw_raw', 
                    propensity_score_name = 'psm_score', 
                    truncation_bounds = config_iptw_tables$ps_truncation_bounds)

picard::save(
  table7_main,
  file_path = config_iptw_tables$output_dir,
  file_name = paste0(config_iptw_tables$output_names$table_ps_and_iptw_summary, 'MALES.csv')
)

picard::save(
  table7_principalstratum,
  file_path = config_iptw_tables$output_dir,
  file_name = paste0(config_iptw_tables$output_names$table_ps_and_iptw_summary, 'PRINCIPAL_STRATUM.csv')
)

picard::save(
  table7_combined,
  file_path = config_iptw_tables$output_dir,
  file_name = paste0(config_iptw_tables$output_names$table_ps_and_iptw_summary, 'COMBINED_MOTHERS-FATHERS.csv')
)


################################################################################################
########################## Plot of weighted vs unweighted ASDs  ################################
################################################################################################

logger::log_info("Creating ASD comparison plot")
# Start by computing weighted ASDs
logger::log_info("First step - Computing weighted and unweighted ASDs")

asd_males <- plot_asd_weighted(cov_with_weight = cov_with_weight_males,
  metadata = metadata_descriptives_males,
  weight_var = "stabilized_trunc_iptw",
  exclude_vars = 'SV_ASM_PREVIOUS',
  asd_threshold = 0.1,
  colors = c("darkblue", "darkred"))

ggplot2::ggsave(
  filename = paste0(config_iptw_tables$output_names$figure_asd_before_after_weighting, "_MALES.png"),
  path = config_iptw_tables$output_dir,
  plot = asd_males$fig_asd,
  width = 20,
  height = 14,
  dpi = 300,
  units = "cm"
)

asd_mothers <- plot_asd_weighted(cov_with_weight = cov_with_weights_mothers,
  metadata = metadata_descriptives_mothers,
  weight_var = "stabilized_trunc_iptw",
  exclude_vars = 'SV_ASM_PREVIOUS',
  asd_threshold = 0.1,
  colors = c("darkblue", "darkred"))

ggplot2::ggsave(
  filename = paste0(config_iptw_tables$output_names$figure_asd_before_after_weighting, "_MOTHERS.png"),
  path = config_iptw_tables$output_dir,
  plot = asd_mothers$fig_asd,
  width = 20,
  height = 14,
  dpi = 300,
  units = "cm"
)

logger::log_info("Creating ASD comparison plot")



###################################################################################
######## Propensity scores density kernels across groups ##########################
###################################################################################

logger::log_info("Creating PS density plot")

propensity_score_density_males <- plot_density_ps(weights_object = d4_male_iptw)

ggplot2::ggsave(
  filename = paste0(config_iptw_tables$output_names$figure_ps_density, "_MALES.png"),
  path = config_iptw_tables$output_dir,
  plot = propensity_score_density_males,
  width = 20,
  height = 14,
  dpi = 300,
  units = "cm"
)

propensity_score_density_combined <- plot_density_ps(weights_object = d4_combined_iptw)

ggplot2::ggsave(
  filename = paste0(config_iptw_tables$output_names$figure_ps_density, "_COMBINED_MOTHERS-FATHERS.png"),
  path = config_iptw_tables$output_dir,
  plot = propensity_score_density_combined,
  width = 20,
  height = 14,
  dpi = 300,
  units = "cm"
)
#######################################################################################
########################## Figures 5 ############################################
######## Figure 5. Density IPTW weights before and after truncation at 1 at 99%  ######
#######################################################################################

logger::log_info("Creating IPTW density plot")

iptw_stage_levels <- c("Before truncation", "After truncation at P1/P99")
iptw_plot_data <- data.table::melt(
  d4_male_iptw[include_after_trimming == TRUE],
  id.vars = c("person_id", "group"),
  measure.vars = c("stabilized_iptw", "stabilized_trunc_iptw"),
  variable.name = "stage",
  value.name = "weight"
)
iptw_plot_data[
  ,
  stage := factor(
    stage,
    levels = c("stabilized_iptw", "stabilized_trunc_iptw"),
    labels = iptw_stage_levels
  )
]
iptw_plot_data[
  ,
  group_label := factor(
    group,
    levels = c("CONTROL", "EXPOSED"),
    labels = c("Control", "Exposed")
  )
]

fig_iptw_density <- ggplot2::ggplot(iptw_plot_data, ggplot2::aes(x = weight)) +
    ggplot2::geom_histogram(
    ggplot2::aes(color = group_label, fill = group_label),
    bins = 30,
    position = "identity",
    alpha = 0.4
  ) +
  ggplot2::scale_fill_manual(values = c("darkblue", "darkred")) +
  ggplot2::scale_color_manual(values = c("darkblue", "darkred")) +
  ggplot2::facet_wrap(~stage, ncol = 1, scales = "free") +
  ggplot2::theme_minimal() +
  ggplot2::theme(
    legend.title = ggplot2::element_blank(),
    legend.position = "bottom",
    legend.text = ggplot2::element_text(size = 10),
    axis.text = ggplot2::element_text(size = 10),
    axis.title = ggplot2::element_text(size = 10)
  ) +
  ggplot2::labs(x = "Stabilized IPT weight", y = "Frequency")

ggplot2::ggsave(
  filename = paste0(config_iptw_tables$output_names$figure_distribution_iptw_before_after_truncation, '_MALES.png'),
  path = config_iptw_tables$output_dir,
  plot = fig_iptw_density,
  width = 20,
  height = 14,
  dpi = 300,
  units = "cm"
)

# remove data objects from memory
remove(list = c("combined_table3",
  "cov_with_stratum_weights_males",
  "cov_with_weight_males",
  "cov_with_weights_mothers",
  "d4_combined_covariates",
  "d4_combined_iptw",
  "d4_ipsmw",
  "d4_male_covariates",
  "d4_male_iptw",
  "d4_mother_covariates",
  "d4_mother_iptw",
  "d4_principal_stratum_coef",
  "d5_combined_ps_coef",
  "d5_male_ps_coef",
  "iptw_plot_data",
  "metadata_descriptives_males",
  "metadata_descriptives_mothers",
  "principal_stratum_variables",
  "ps_variables_male",
  "ps_variables_mother",
  "table3_males",
  "table3_fathers",
  "table3_mothers",
  "table6_males",
  "table6_fathermothers",
  "table6_principalstratum",
  "table7_main",
  "table7_principalstratum"))



logger::log_info("[create_iptw_tables] - SUCCEED")

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
  