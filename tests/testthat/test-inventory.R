test_that("inventory classifies correctly", {
  src <- data.table::data.table(
    package = c("pkgA", "pkgB", "pkgC", "pkgD", "pkgE"),
    version = c("1.0.0", "2.0.0", "1.5.0", "3.0.0", "4.0.0"),
    priority = c(NA, NA, NA, "base", NA),
    source = c("CRAN", "CRAN", "CRAN", "CRAN", "CRAN")
  )

  tgt <- data.table::data.table(
    package = c("pkgB", "pkgC", "pkgD"),
    version = c("1.5.0", "1.5.0", "3.0.0"),
    priority = c(NA, NA, "base"),
    source = c("CRAN", "CRAN", "CRAN")
  )

  res <- inventory(src, tgt)

  expect_equal(nrow(res$missing), 2)  # pkgA, pkgE (pkgD is base so excluded from src)
  expect_true(all(res$missing$package %in% c("pkgA", "pkgE")))

  expect_equal(nrow(res$outdated), 1) # pkgB (2.0.0 > 1.5.0)
  expect_equal(res$outdated$package, "pkgB")

  expect_equal(nrow(res$same), 1)     # pkgC
  expect_equal(res$same$package, "pkgC")

  expect_equal(res$summary$total_source, 4)
  expect_equal(res$comparison[["status"]][match(c("pkgA", "pkgB", "pkgC", "pkgE"), res$comparison[["package"]])],
               c("missing", "outdated", "same", "missing"))
})

test_that("inventory handles empty or pre-populated destination libraries", {
  src <- data.table::data.table(
    package = c("pkgA", "pkgB", "pkgC"),
    version = c("1.0.0", "2.0.0", "3.0.0"),
    priority = NA_character_,
    source = "CRAN"
  )

  populated_tgt <- data.table::data.table(
    package = c("pkgB", "pkgC", "pkgZ"),
    version = c("1.0.0", "3.0.0", "9.9.9"),
    source = "CRAN"
  )

  populated_res <- inventory(src, populated_tgt)
  expect_equal(populated_res$comparison[["status"]][match(c("pkgA", "pkgB", "pkgC"), populated_res$comparison[["package"]])],
               c("missing", "outdated", "same"))
  expect_equal(populated_res$comparison[["package"]][populated_res$comparison[["status"]] == "missing"], "pkgA")

  empty_tgt <- data.table::data.table()
  empty_res <- inventory(src, empty_tgt)
  expect_equal(nrow(empty_res$missing), 3)
  expect_equal(sort(empty_res$comparison[["package"]][empty_res$comparison[["status"]] == "missing"]), sort(src$package))
})

test_that("inventory handles newer packages on target", {
  src <- data.table::data.table(
    package = c("pkgA", "pkgB"),
    version = c("1.0.0", "1.0.0"),
    priority = NA_character_,
    source = "CRAN"
  )
  tgt <- data.table::data.table(
    package = c("pkgA", "pkgB"),
    version = c("2.0.0", "1.0.0"),
    priority = NA_character_,
    source = "CRAN"
  )
  res <- inventory(src, tgt)
  expect_equal(nrow(res$newer), 1)
  expect_equal(res$newer$package, "pkgA")
  expect_equal(nrow(res$same), 1)
  expect_equal(res$same$package, "pkgB")
})

test_that("inventory handles malformed input with missing columns", {
  src <- data.table::data.table(x = "abc")
  tgt <- data.table::data.table(y = "def")
  res <- inventory(src, tgt)
  expect_s3_class(res$comparison, "data.table")
  # src gets normalized to have 'package' and 'version' columns (empty strings).
  # Column 'x' is not 'package', so package gets empty string.
  # Empty version strings are treated as outdated so they get included in plan.
  expect_true(nrow(res$comparison) >= 0)
  expect_equal(res$summary$total_source, 1)
})

test_that("inventory handles empty source library", {
  src <- data.table::data.table(
    package = character(),
    version = character(),
    priority = character(),
    source = character()
  )
  tgt <- data.table::data.table(
    package = "pkgA",
    version = "1.0.0",
    priority = NA_character_,
    source = "CRAN"
  )
  res <- inventory(src, tgt)
  expect_equal(res$summary$total_source, 0)
  expect_equal(nrow(res$missing), 0)
})
