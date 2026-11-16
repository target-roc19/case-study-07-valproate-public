# Processing child linkage ----
# Aim:
# Processing the child linkage information.

# Initial setup ----
## Script logger ----
if (
  !base::exists("lm", inherits = TRUE) ||
    !base::inherits(lm, "LoggerManager")
) {
  lm <- NULL
}
if (!base::is.null(lm)) {
  lm$start_script("process_child_linkage.R")
  lm$start_capturing_prints()
}

## Config loading ----
picard::load_config()

## Audit setup ----
picard::audit_start(
  file_name = "d3_child_linkage",
  deap_name = config_project$DEAP_configuration$name
)

dir_d3 <- config_project$output$dir_d3

### Load input data ----
d3_person_file <- config_project$process_child_linkage$D3_person_file
person_relationship_file <- file.path(
  config_project$DEAP_configuration$data_instance,
  config_project$process_child_linkage$person_relationship_file
)
survey_id_file <- file.path(
  config_project$DEAP_configuration$data_instance,
  config_project$process_child_linkage$survey_id_file
)
survey_observations_file <- file.path(
  config_project$DEAP_configuration$data_instance,config_project$process_child_linkage$survey_observations_file
)

person_relationship <- picard::load(person_relationship_file) 
survey_id <- picard::load(survey_id_file) 
d3_persons <- picard::load(d3_person_file)
survey_observations <- picard::load(survey_observations_file) 

# Step 1 ----
# Build one row per child with parent ids derived from PERSON_RELATIONSHIPS.
child_linkage <- person_relationship[
  meaning_of_relationship %in% c("registered_father", "birth_mother"),
  .(
    father_id = related_id[meaning_of_relationship == "registered_father"][1],
    mother_id = related_id[meaning_of_relationship == "birth_mother"][1]
  ),
  by = .(child_id = person_id)
]

picard::audit_add(
  paste(
    "number of children based on person_relationship:",
    nrow(child_linkage)
  )
)

picard::audit_add(
  paste(
    "number of children with linked mothers:",
    nrow(child_linkage[!is.na(mother_id)])
  )
)

picard::audit_add(
  paste(
    "number of children with linked fathers:",
    nrow(child_linkage[!is.na(father_id)])
  )
)

# Step 2 ----
# Add date of birth from D3_PERSONS.
child_linkage <- data.table::merge.data.table(
  x = child_linkage,
  y = d3_persons[, .(child_id = person_id, date_of_birth = birth_date)],
  by = "child_id",
  all.x = TRUE
)

picard::audit_add(
  paste(
    "number of children with linked birthdate from d3_persons:",
    nrow(child_linkage[!is.na(date_of_birth)])
  )
)

rm(d3_persons, person_relationship) # Cleanup

# Step 3 ----
# Pivot SURVEY_ID: child_id = person_id where survey_meaning == "birth_registry_child"
#                  mother_id = person_id where survey_meaning == "birth_registry_mother"
# Join on survey_id to produce one row per (survey_id, child_id, mother_id).
survey_id_children <- survey_id[
  survey_meaning == "birth_registry_child",
  .(child_id = person_id, survey_id)
]
survey_id_mothers <- survey_id[
  survey_meaning == "birth_registry_mother",
  .(mother_id = person_id, survey_id)
]
survey_id <- data.table::merge.data.table(
  x = survey_id_children,
  y = survey_id_mothers,
  by = "survey_id",
  all = FALSE
)

picard::audit_add(
  paste(
    "number of linked mother and child through survey_id:",
    nrow(survey_id)
  )
)
rm(survey_id_children, survey_id_mothers)

child_linkage <- data.table::merge.data.table(
  x = child_linkage,
  y = survey_id,
  by.x = c("child_id", "mother_id"),
  by.y = c("child_id", "mother_id"),
  all.x = TRUE
)

picard::audit_add(
  paste(
    "number of children with linked survey_id:",
    nrow(child_linkage[!is.na(survey_id)])
  )
)
# Add estimated conception date via SURVEY_ID when available.
estimated_conception <- survey_observations[
  so_source_table =="PREGNANCY_COHORT" &
  so_meaning == "birth_registry_mother" &
    so_source_column == "pregnancy_start_date",  
.(
    survey_id,
    estimated_conception_date = as.Date(so_source_value, format = "%Y%m%d"),
    person_id
  )
]

d3_father_child <- data.table::merge.data.table(
  x = child_linkage,
  y = estimated_conception,
  by.x = c("survey_id", "mother_id"),
  by.y = c("survey_id", "person_id"),
  all.x = TRUE
)

audit_add(
  paste(
    "number of children with linked estimated conception date:",
    nrow(d3_father_child[!is.na(estimated_conception_date)])
  )
)

# add pregnancy_id based on father_id and date_of_birth
d3_father_child <- d3_father_child[order(father_id, date_of_birth, child_id)]
d3_father_child[, pregnancy_id := data.table::rleid(father_id, date_of_birth)]

rm(child_linkage, survey_id, estimated_conception, survey_observations) 

output_columns <- c(
  "father_id",
  "child_id",
  "date_of_birth",
  "pregnancy_id",
  "estimated_conception_date",
  "mother_id"
)

d3_father_child <- d3_father_child[, ..output_columns]

## Saving output ----
picard::save(
  data = d3_father_child,
  file_path = dir_d3,
  file_name = "D3_FatherChild.parquet",
  create_plot = TRUE
)

## Cleanup ----
rm(d3_father_child)
picard::audit_end()

logger::log_info(c("[Processing D3 child linkage] - SUCCEED"))

if (!base::is.null(lm)) {
  lm$stop_capturing_prints()
  lm$end_script()
}
