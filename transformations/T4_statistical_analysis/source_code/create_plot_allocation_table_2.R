
################################################################
# plot exclusion flowchart
# Aim: 
# Create Figure 1, a flowchart that represents the information of Table 1 into a table
#
# Input files: ---
# - configuration/config_project.yaml
# - .csv created by create_attrition_tables.R
# Output
## Flowchat

# Initial setup ---
## Load necessary libraries ---
library(ggplot2)
library(data.table)

## Script logger ---
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("plot_matches_by_date")
  lm$start_capturing_prints()
}

logger::log_info("Start of the plot exclusion flowchart script.")

config_project <- picard::load_config("configuration/config_project.yaml")

## Audit setup ---
picard::audit_start(
  file_name = "create_plot_allocation_table_2",
  deap_name = config_project$DEAP_configuration$name
)

# Load input datasets ---
d4_males_cohort <- picard::load(
  file_path = config_project$create_plot_allocation_table_2$input$dir_d4,
  file_name = config_project$create_plot_allocation_table_2$input$file_name_males_cohort)

counts_per_trial <- as.data.frame(d4_males_cohort[, .N, by = .(group, trial_start)])

if(config_project$create_plot_allocation_table_2$test_mode){
  # randomly allocate people to trials in uneven fashion for testing the plot
  set.seed(123)
  counts_per_trial$N <- sample(1:100, nrow(counts_per_trial), replace = TRUE)
  counts_per_trial$group <- sample(c("EXPOSED", "CONTROL"), nrow(counts_per_trial), replace = TRUE)
}

fig2 <- ggplot(data = counts_per_trial) +
  geom_col(
    aes(x = trial_start, y = N, fill = group)
  ) +
  theme_bw() +
  # change legend labels
  scale_fill_manual(
    values = c("EXPOSED" = "#E69F00", "CONTROL" = "#0072B2"),
    labels = c("EXPOSED" = "Valproate", "CONTROL" = "Levetiracetam"),
    name = "Treatment Group"
  ) +
  labs(
    title = NULL,
    y = 'Number of males',
    x = 'Start date of sequential monthly date'
  ) +
  # scale_x_date start Jan 2010, end March 2016
  scale_x_date(date_labels = "%b %Y", date_breaks = "3 months",
         #    limits = as.Date(c("2009-12-31", "2016-04-31")),
            expand = c(0, 0)) +
  # rotate x labels 45 degrees and move x axis title down a bit
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "top",
    axis.title.x = element_text(margin = margin(t = 10))
  ) 




# Save Table 2
logger::log_info("Saving Figure 2.")

ggsave(
  plot = fig2,
  filename = config_project$create_plot_allocation_table_2$output$file_name,
    path = config_project$create_plot_allocation_table_2$output$dir_d5,
    width = 20,
    height = 14,
    dpi = 300,
    units = "cm"
  )


picard::audit_end()

rm(d4_males_cohort, fig2)
gc()
