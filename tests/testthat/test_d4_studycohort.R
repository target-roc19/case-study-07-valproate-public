# load library and cohort creation function
library(testthat)
library(data.table)

cohort_function_path <- file.path("transformations", "T3_study_design", "source_code", "functions", "create_d4_cohort_function.R")
if (!file.exists(cohort_function_path)) {
  cohort_function_path <- file.path("..", "..", cohort_function_path)
}
source(cohort_function_path)
add_child_function_path <- file.path("transformations", "T3_study_design", "source_code", "functions", "add_child_to_d4_studycohort_function.R")
if (!file.exists(add_child_function_path)) {
  add_child_function_path <- file.path("..", "..", add_child_function_path)
}
source(add_child_function_path)

create_d4_child_cohort_function_path <- file.path("transformations", "T3_study_design", "source_code", "functions", "create_d4_child_cohort.R")

if (!file.exists(create_d4_child_cohort_function_path)) {
  create_d4_child_cohort_function_path <- file.path("..", "..", create_d4_child_cohort_function_path)
}
source(create_d4_child_cohort_function_path)

test_data_root <- file.path("tests", "testthat", "test_data")
if (!dir.exists(test_data_root)) {
  test_data_root <- "test_data"
}

test.data <- "test_data_csv" # Set to 'test_data' to use example datasets for testing, or set to '' to use actual datasets created by the pipeline

if (test.data == "test_data_csv") {
  ##### Load examples and assign correct data.types
  # load examples
  d3.eligibility <- fread(file.path(test_data_root, "D3_ELIGIBILITY", "D3_ELIGIBILITY.csv"))
  d3.eligibility.big <- d3.eligibility[rep(1:.N, each = 50000)]
  # Assign unique person_id by combining original person_id with repetition number
  d3.eligibility.big[, person_id := paste0(person_id, "_", rowid(person_id))]

  ## Add d3.eligibility.big for testing purposes (to test the function with a larger dataset, which is more similar to the actual dataset created by the pipeline)

  d4.studycohort <- fread(file.path(test_data_root, "D4_StudyCohort", "D4_StudyCohort.csv"))
  bootstrap_file <- file.path(test_data_root, "D4_StudyCohort", "D4_StudyCohort_bootstrap.csv")
  if (!file.exists(bootstrap_file)) {
    bootstrap_file <- file.path(test_data_root, "D4_StudyCohort", "D4_StudyCohort_bootstrap_Males.csv")
  }
  d4.studycohort.bootstrap <- fread(bootstrap_file)
  d4.studycohort_child <- fread(file.path(test_data_root, "D4_StudyCohort", "D4_StudyCohortChild.csv"))

  ## Examples have different order than function default,
  ## order by person_id, trial_start, boot_person_id to ensure consistency for testing
  # sort by person_id, trial_id, boot_person_id
  d4.studycohort <- d4.studycohort[order(person_id, trial_start, boot_person_id)]
  d4.studycohort.bootstrap <- d4.studycohort.bootstrap[order(person_id, trial_start, boot_person_id)]

  ## Homogeneize data types for comparison
  ## (this is needed for .csv test datasets, because they are stored as .csv tables.
  ## but D5_StudyCohort created by the pipeline already have these data types)
  d4.studycohort[, person_id := as.character(person_id)]
  d4.studycohort[, trial_start := as.IDate(trial_start)]
  d4.studycohort[, trial_end := as.IDate(trial_end)]
  d4.studycohort[, boot_id := as.character(boot_id)]
  d4.studycohort.bootstrap[, person_id := as.character(person_id)]
  d4.studycohort.bootstrap[, trial_start := as.IDate(trial_start)]
  d4.studycohort.bootstrap[, trial_end := as.IDate(trial_end)]
  d4.studycohort.bootstrap[, boot_id := as.character(boot_id)]

  # Load D3_FatherChild example dataset
  d3.father_child <- fread(file.path(test_data_root, "D3_FatherChild", "D3_FatherChild.csv"))
  d3.father_child[, father_id := as.character(father_id)]
  d3.father_child[, estimated_conception_date := as.IDate(estimated_conception_date)]
  d3.father_child[, date_of_birth := as.IDate(date_of_birth)]
}


## Actual tests
test_that("create_d4_studycohort produces expected example output", {
  # Create output
  output <- create_d4_studycohort(d3.eligibility)
  output <- add_child_to_d4_studycohort(output, d3.father_child)
  waldo::compare(output, d4.studycohort)
  setkey(output, NULL)
  setkey(d4.studycohort, NULL)
  expect_identical(output, d4.studycohort)
})
set.seed(30)
test_that("create_d4_studycohort creates resampled outputput", {
  # Create output
  output <- create_d4_studycohort(d3.eligibility, bootstrap = TRUE, current.boot.id = 1)
  output <- add_child_to_d4_studycohort(output, d3.father_child)
  data.table::setkey(output, person_id, T0)
  data.table::setkey(d4.studycohort.bootstrap, person_id, T0)
  waldo::compare(output, d4.studycohort.bootstrap)
  expect_identical(output, d4.studycohort.bootstrap)
})
test_that("create_d4_studycohort keeps only first spell per person-trial overlap", {
  overlap.input <- data.table(
    person_id = c("p1", "p1", "p2"),
    start = as.IDate(c("2010-01-05", "2010-01-20", "2010-02-01")),
    end = as.IDate(c("2010-01-31", "2010-02-15", "2010-02-28")),
    eligible_exposed = c(TRUE, FALSE, FALSE),
    eligible_control = c(FALSE, TRUE, TRUE)
  )

  output <- create_d4_studycohort(overlap.input)

  # No person can enter the same trial more than once.
  duplicated.person.trial <- output[, .N, by = .(person_id, trial_id)][N > 1]
  expect_equal(nrow(duplicated.person.trial), 0L)

  # For p1 in Jan-2010, the earliest overlapping spell must be retained.
  jan.p1 <- output[person_id == "p1" & trial_start == as.IDate("2010-01-01")]
  expect_equal(nrow(jan.p1), 1L)
  expect_identical(jan.p1$start, as.IDate("2010-01-05"))
  expect_identical(jan.p1$group, "EXPOSED")
})
test_that("create_d4_studycohort runs on large datasets", {
  # Create output
  output <- create_d4_studycohort(d3.eligibility.big)
  expect_true(nrow(output) > 0) # Check that output is not empty
})

test_that("earliest conceptions keeps NA when they take place before T0", {
  d3_father_child <- data.table(
    father_id = "p1",
    estimated_conception_date = as.IDate("2010-01-01"),
    date_of_birth = as.IDate("2010-10-01")
  )

  d4_studycohort <- data.table(
    person_id = "p1",
    T0 = as.IDate("2011-01-01")
  )

  result <- add_child_to_d4_studycohort(d4_studycohort, d3_father_child)

  expect_true(is.na(result$earliest_conception_date))
  expect_true(is.na(result$first_date_of_birth))
})

test_that("earliest conceptions keeps NA when no conception date is matched", {
  d3_father_child <- data.table(
    father_id = "p2",
    estimated_conception_date = as.IDate("2010-01-01"),
    date_of_birth = as.IDate("2010-10-01")
  )

  d4_studycohort <- data.table(
    person_id = "p1",
    T0 = as.IDate("2011-01-01")
  )

  result <- add_child_to_d4_studycohort(d4_studycohort, d3_father_child)

  expect_true(is.na(result$earliest_conception_date))
  expect_true(is.na(result$first_date_of_birth))
})

test_that("earliest conception aligns with child with earliest livebirth", {
  d3_father_child <- data.table(
    father_id = c("p1", "p1"),
    estimated_conception_date = as.IDate(c("2010-01-01", "2010-02-01")),
    date_of_birth = as.IDate(c("2010-12-01", "2010-10-01"))
  )

  d4_studycohort <- data.table(
    person_id = "p1",
    T0 = as.IDate("2009-01-01")
  )

  result <- add_child_to_d4_studycohort(d4_studycohort, d3_father_child)

  expect_identical(result$earliest_conception_date, as.IDate("2010-02-01"))
  expect_identical(result$first_date_of_birth, as.IDate("2010-10-01"))
})

test_that("earliest conception falls back to minimum conception when birth dates are missing", {
  d3_father_child <- data.table(
    father_id = c("p1", "p1"),
    estimated_conception_date = as.IDate(c("2010-03-01", "2010-01-15")),
    date_of_birth = as.IDate(c(NA, NA))
  )

  d4_studycohort <- data.table(
    person_id = "p1",
    T0 = as.IDate("2009-01-01")
  )

  result <- add_child_to_d4_studycohort(d4_studycohort, d3_father_child)

  expect_identical(result$earliest_conception_date, as.IDate("2010-01-15"))
  expect_true(is.na(result$first_date_of_birth))
})

test_that("d4_studycohort_child is created correctly", {
  # Create output
  output <- create_d4_studycohort(d3.eligibility)
  output <- add_child_to_d4_studycohort(output, d3.father_child)
  d4_studycohort_child <- create_d4_child_cohort(output, d3.father_child)

  # Check that the child cohort has the expected number of rows
  expect_equal(nrow(d4_studycohort_child), nrow(d4.studycohort_child))
  waldo::compare(d4_studycohort_child, d4.studycohort_child)
})
