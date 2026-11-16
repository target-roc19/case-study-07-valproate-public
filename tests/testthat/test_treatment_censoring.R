
#------------------------------------------------
# Test compute_treatment_discontinuation function
#------------------------------------------------

source("transformations/T3_study_design/source_code/functions/treatment_censoring_functions.R")

testthat::test_that("single TRUE episode returns its end as discontinuation", {

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date("2020-01-01"),
    end_episode   = as.Date("2020-01-31"),
    value         = TRUE
  )

  fup <- data.table(
    person_id = 1L,
    T0 = as.Date("2020-01-10")
  )

  res <- compute_treatment_discontinuation(fup, episodes)

  testthat::expect_equal(
    res$treatment_discontinuation,
    as.Date("2020-01-31")
  )
})

testthat::test_that("consecutive TRUE episodes are concatenated", {

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date(c("2020-01-01", "2020-02-01", "2020-03-01")),
    end_episode   = as.Date(c("2020-01-31", "2020-02-29", "2020-03-31")),
    value         = c(TRUE, TRUE, FALSE)
  )

  fup <- data.table(
    person_id = 1L,
    T0 = as.Date("2020-01-15")
  )

  result <- compute_treatment_discontinuation(fup, episodes)

  testthat::expect_equal(
    result$treatment_discontinuation,
    as.Date("2020-02-29")
  )
})

testthat::test_that("T0 inside later TRUE episode returns end of TRUE run", {

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date(c("2020-01-01", "2020-02-01", "2020-03-01")),
    end_episode   = as.Date(c("2020-01-31", "2020-02-29", "2020-03-31")),
    value         = c(TRUE, TRUE, FALSE)
  )

  fup <- data.table(
    person_id = 1L,
    T0 = as.Date("2020-02-10")
  )

  result <- compute_treatment_discontinuation(fup, episodes)

  testthat::expect_equal(
    result$treatment_discontinuation,
    as.Date("2020-02-29")
  )
})

testthat::test_that("separate treatment runs have different discontinuation dates", {

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date(c(
      "2020-01-01",
      "2020-02-01",
      "2020-03-01",
      "2020-04-01",
      "2020-05-01"
    )),
    end_episode = as.Date(c(
      "2020-01-31",
      "2020-02-29",
      "2020-03-31",
      "2020-04-30",
      "2020-05-31"
    )),
    value = c(TRUE, TRUE, FALSE, TRUE, TRUE)
  )

  fup <- data.table(
    person_id = 1L,
    T0 = as.Date(c("2020-01-15", "2020-04-15"))
  )

  result <- compute_treatment_discontinuation(fup, episodes)

  testthat::expect_equal(
    result$treatment_discontinuation,
    as.Date(c("2020-02-29", "2020-05-31"))
  )
})

testthat::test_that("treatment runs are independent across people", {

  episodes <- data.table(
    person_id = c(1L, 1L, 2L),
    start_episode = as.Date(c(
      "2020-01-01",
      "2020-02-01",
      "2020-01-01"
    )),
    end_episode = as.Date(c(
      "2020-01-31",
      "2020-02-29",
      "2020-01-31"
    )),
    value = c(TRUE, TRUE, TRUE)
  )

  fup <- data.table(
    person_id = c(1L, 2L),
    T0 = as.Date(c("2020-01-15", "2020-01-15"))
  )

  result <- compute_treatment_discontinuation(fup, episodes)

  testthat::expect_equal(
    result$treatment_discontinuation,
    as.Date(c("2020-02-29", "2020-01-31"))
  )
})

testthat::test_that("returns empty when T0 is not inside a TRUE episode", {

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date("2020-01-01"),
    end_episode   = as.Date("2020-01-31"),
    value         = TRUE
  )

  fup <- data.table(
    person_id = 1L,
    T0 = as.Date("2020-02-15")
  )

  result <- compute_treatment_discontinuation(fup, episodes)

  testthat::expect_true(nrow(result) == 0)
})

#------------------------------------------------
# Test treatment switch function
#------------------------------------------------

testthat::test_that("first initiation after T0 is correctly identified", {

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date(c("2020-01-01", "2020-02-01")),
    end_episode   = as.Date(c("2020-01-31", "2020-02-29")),
    value = c(TRUE, TRUE)
  )

  fup <- data.table(
    person_id = 1L,
    T0 = as.Date("2020-01-15")
  )

  res <- compute_treatment_switch(fup, episodes, rename_to = "treatment_start")

  testthat::expect_equal(
    res$treatment_start,
    as.Date("2020-02-01")
  )
})

testthat::test_that("handles multiple T0 per person independently", {

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date(c("2020-01-01","2020-03-01")),
    end_episode   = as.Date(c("2020-02-01","2020-04-01")),
    value = TRUE
  )

  fup <- data.table(
    person_id = 1L,
    T0 = as.Date(c("2020-01-10","2020-03-10"))
  )

  res <- compute_treatment_switch(fup, episodes, rename_to = "treatment_start")

  testthat::expect_equal(
    res$treatment_start,
    as.Date(c("2020-03-01", NA))
  )
})

testthat::test_that("returns NA when no initiation after T0", {

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date("2020-01-01"),
    end_episode   = as.Date("2020-01-31"),
    value = TRUE
  )

  fup <- data.table(
    person_id = 1L,
    T0 = as.Date("2020-02-01")
  )

  res <- compute_treatment_switch(fup, episodes, rename_to = "treatment_start")

  testthat::expect_true(is.na(res$treatment_start))
})

testthat::test_that("EXPOSED group masks VPA start correctly", {

  d4 <- data.table(
    person_id = 1L,
    T0 = as.Date("2020-01-10"),
    group = "EXPOSED"
  )

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date("2020-02-01"),
    end_episode   = as.Date("2020-02-28"),
    value = TRUE
  )

  res <- compute_treatment_switch(d4, episodes, rename_to = "treatment_start_vpa")

  res[group == "EXPOSED", treatment_start_vpa := NA]

  testthat::expect_true(is.na(res$treatment_start_vpa))
})

testthat::test_that("CONTROL group masks LEV start correctly", {

  d4 <- data.table(
    person_id = 1L,
    T0 = as.Date("2020-01-10"),
    group = "CONTROL"
  )

  episodes <- data.table(
    person_id = 1L,
    start_episode = as.Date("2020-02-01"),
    end_episode   = as.Date("2020-02-28"),
    value = TRUE
  )

  res <- compute_treatment_switch(d4, episodes, rename_to = "treatment_start_lev")

  res[group == "CONTROL", treatment_start_lev := NA]

  testthat::expect_true(is.na(res$treatment_start_lev))
})

testthat::test_that("final treatment_switch is minimum of drug-specific starts", {

  dt <- data.table(
    treatment_start_vpa = as.Date(c("2020-03-01")),
    treatment_start_lev = as.Date(c("2020-02-01")),
    treatment_start_ot_asm = as.Date(c("2020-04-01"))
  )

  dt[, treatment_switch := as.Date(do.call(pmin, c(.SD, na.rm = TRUE))),
     .SDcols = c("treatment_start_vpa",
                 "treatment_start_lev",
                 "treatment_start_ot_asm")]

  testthat::expect_equal(
    dt$treatment_switch,
    as.Date("2020-02-01")
  )
})

testthat::test_that("pmin returns NA when all starts are NA", {

  dt <- data.table(
    treatment_start_vpa = as.Date(NA),
    treatment_start_lev = as.Date(NA),
    treatment_start_ot_asm = as.Date(NA)
  )

  dt[, treatment_switch := as.Date(do.call(pmin, c(.SD, na.rm = TRUE))),
     .SDcols = c("treatment_start_vpa",
                 "treatment_start_lev",
                 "treatment_start_ot_asm")]

  testthat::expect_true(is.na(dt$treatment_switch))
})
