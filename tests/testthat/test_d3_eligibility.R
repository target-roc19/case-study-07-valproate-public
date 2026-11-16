library(testthat)
library(data.table)
library(yaml)

# Load the function
source("transformations/T3_study_design/source_code/functions/create_eligibility_function.R")

test_that("compute_eligibility produces expected D3_ELIGIBILITY output", {
  # Load test data
  d3_episodes <- data.table::fread("tests/testthat/test_data/D3_multivariate_episodes/D3_multivariate_episodes.csv")
  d3_fatherchild <- data.table::fread("tests/testthat/test_data/D3_FatherChild/D3_FatherChild.csv")
  expected <- data.table::fread("tests/testthat/test_data/D3_ELIGIBILITY/D3_ELIGIBILITY.csv")


  # Convert dates to Date class
  d3_episodes[, `:=`(start = as.Date(start), end = as.Date(end))]
  d3_fatherchild[, `:=`(
    date_of_birth = as.Date(date_of_birth),
    estimated_conception_date = as.Date(estimated_conception_date)
  )]
  expected[, `:=`(
    start = as.Date(start),
    end = as.Date(end),
    first_date_of_birth = data.table::as.IDate(first_date_of_birth)
  )]

  # Create config
  config <- yaml::read_yaml("configuration/config_values.yaml")

  # Run function
  result <- compute_eligibility(d3_episodes, d3_fatherchild, config)

  # Order data.tables in the same way for comparison
  data.table::setorder(expected, person_id, start, end)
  data.table::setorder(result, person_id, start, end)
  expected[, person_id := as.character(person_id)]
  # Check dimensions
  expect_equal(nrow(result), nrow(expected), info = "Number of rows should match")
  expect_equal(ncol(result), ncol(expected), info = "Number of columns should match")

  # Check column names
  expect_true(all(colnames(result) %in% colnames(expected)), info = "Column names should match")

  # Check key columns match
  expect_equal(result$person_id, expected$person_id, info = "person_id should match")
  expect_equal(result$start, expected$start, info = "start dates should match")
  expect_equal(result$end, expected$end, info = "end dates should match")

  # Check computed columns (allowing for NA handling)
  expect_equal(result$in_study_period, expected$in_study_period,
    info = "in_study_period should match"
  )
  expect_equal(result$receives_exposure, expected$receives_exposure,
    info = "receives_exposure should match"
  )
  expect_equal(result$receives_control, expected$receives_control,
    info = "receives_control should match"
  )
  expect_equal(result$in_eligible_pop, expected$in_eligible_pop,
    info = "in_eligible_pop should match"
  )
  expect_equal(result$eligible_exposed, expected$eligible_exposed,
    info = "eligible_exposed should match"
  )
  expect_equal(result$eligible_control, expected$eligible_control,
    info = "eligible_control should match"
  )

  # Check outcome columns
  expect_equal(result$livebirth_within_3years, expected$livebirth_within_3years,
    info = "livebirth_within_3years should match"
  )
  expect_equal(result$n_pregnancies, expected$n_pregnancies,
    info = "n_pregnancies should match"
  )
  expect_equal(result$n_infants, expected$n_infants,
    info = "n_infants should match"
  )

  # Check first_date_of_birth (allowing for NA)
  expect_equal(is.na(result$first_date_of_birth), is.na(expected$first_date_of_birth),
    info = "NA pattern for first_date_of_birth should match"
  )
  non_na_idx <- !is.na(expected$first_date_of_birth)
  if (any(non_na_idx)) {
    expect_equal(result$first_date_of_birth[non_na_idx], expected$first_date_of_birth[non_na_idx],
      info = "Non-NA first_date_of_birth values should match"
    )
  }
})
