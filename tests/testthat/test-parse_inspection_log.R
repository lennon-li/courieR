test_that("parse_inspection_log returns empty data.table for missing file", {
  res <- parse_inspection_log("nonexistent.txt")
  expect_s3_class(res, "data.table")
  expect_equal(nrow(res), 0L)
  expect_equal(names(res), c("severity", "message", "file", "line", "raw_block"))
})

test_that("parse_inspection_log parses ERROR, WARNING, NOTE blocks", {
  tmp <- withr::local_tempfile(lines = c(
    "* using R Under development (unstable) (2024-01-01 r85777)",
    "* checking package dependencies ... OK",
    "* checking R code for possible problems ... NOTE",
    "my_func: no visible binding for global variable 'x'",
    "",
    "* checking for missing documentation entries ... WARNING",
    "Rd files with missing documentation:",
    "utils.Rd:42: undocumented S4 methods",
    "",
    "* checking Rd line widths ... ERROR",
    "Rd file utils.Rd",
    "Rd lines wider than 90 characters:",
    "utils.Rd:55: some very long line",
    "",
    "* checking for non-standard things ... OK",
    "* DONE"
  ), fileext = ".log")

  res <- parse_inspection_log(tmp)
  expect_s3_class(res, "data.table")
  expect_equal(nrow(res), 3L)

  expect_equal(res$severity, c("NOTE", "WARNING", "ERROR"))

  # NOTE block: no file:line
  expect_equal(res$message[1], "my_func: no visible binding for global variable 'x'")
  expect_equal(res$file[1], "")
  expect_equal(res$line[1], "")

  # WARNING block: has file:line
  expect_equal(res$file[2], "utils.Rd")
  expect_equal(res$line[2], "42")

  # ERROR block: has file:line
  expect_equal(res$file[3], "utils.Rd")
  expect_equal(res$line[3], "55")

  # raw_block includes the header line
  expect_match(res$raw_block[3], "checking Rd line widths")
})

test_that("parse_inspection_log returns empty data.table for log with no issues", {
  tmp <- withr::local_tempfile(lines = c(
    "* checking package dependencies ... OK",
    "* checking for non-standard things ... OK",
    "* DONE"
  ), fileext = ".log")

  res <- parse_inspection_log(tmp)
  expect_equal(nrow(res), 0L)
})

test_that("parse_inspection_log does not mistake host:port for file:line (A8)", {
  tmp <- withr::local_tempfile(lines = c(
    "* checking examples ... WARNING",
    "  trying URL 'http://127.0.0.1:8080/' failed",
    "  Package example calls example.com:443 during a live test",
    "  see R/foo.R:12 for the actual offending call"
  ), fileext = ".log")

  res <- parse_inspection_log(tmp)
  expect_equal(nrow(res), 1L)
  # Must resolve to the real source reference, not the host:port strings.
  expect_equal(res$file, "foo.R")
  expect_equal(res$line, "12")
})

test_that("parse_inspection_log extracts file.R patterns", {
  tmp <- withr::local_tempfile(lines = c(
    "* checking tests ... ERROR",
    "  Running the tests in 'tests/testthat.R' failed.",
    "  Last 13 lines of output:",
    "  test-broken.R:42: failure: something is wrong",
    "  test-broken.R:55: failure: another thing"
  ), fileext = ".log")

  res <- parse_inspection_log(tmp)
  expect_equal(nrow(res), 1L)
  expect_equal(res$severity, "ERROR")
  # should capture the first file:line match
  expect_equal(res$file, "test-broken.R")
  expect_equal(res$line, "42")
})
