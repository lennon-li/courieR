test_that("ship_rates falls back to defaults and reads calibration", {
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir())

  r <- ship_rates()
  expect_true(all(c("copy", "binary", "source", "overhead") %in% names(r)))
  expect_true(all(vapply(r, is.numeric, logical(1))))

  record_ship_rate("copy", 150)
  r2 <- ship_rates()
  expect_equal(r2$copy, 0.4 * r$copy + 0.6 * 150)
  # Other routes untouched
  expect_equal(r2$binary, r$binary)
})

test_that("record_ship_rate ignores junk", {
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir())
  before <- ship_rates()
  record_ship_rate("copy", NA_real_)
  record_ship_rate("copy", -5)
  record_ship_rate("nonsense", 10)
  expect_equal(ship_rates(), before)
})

test_that("estimate_ship_secs scales with plan and formats a range", {
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir())

  small <- estimate_ship_secs(n_copy = 1L)
  big   <- estimate_ship_secs(n_copy = 50L)
  expect_lt(small$high, big$high)
  expect_match(small$text, "^~")

  # Calibration changes the estimate: a machine where copies take 150s each
  # must estimate 15 copies at far more than the uncalibrated default.
  before <- estimate_ship_secs(n_copy = 15L)
  record_ship_rate("copy", 150)
  est <- estimate_ship_secs(n_copy = 15L)
  expect_gt(est$low, before$low * 3)
  expect_match(est$text, "min|h")
})
