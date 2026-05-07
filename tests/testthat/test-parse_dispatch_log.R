test_that("parse_dispatch_log returns empty data.table for missing file", {
  res <- parse_dispatch_log("nonexistent.txt")
  expect_s3_class(res, "data.table")
  expect_equal(nrow(res), 0L)
  expect_equal(names(res), c("file", "test", "status", "message"))
})

test_that("parse_dispatch_log parses failure, success, and skip entries", {
  tmp <- withr::local_tempfile(lines = c(
    "==> devtools::test()",
    "",
    "Loading courieR",
    "Testing courieR",
    "v | F W S  OK | Context",
    "",
    "-- Failure (test-foo.R:12): addition works ----",
    "`actual` not equal to `expected`.",
    "1/1 mismatches",
    "[1] 3 - 4 == -1",
    "",
    "-- Skip (test-foo.R:20): division skips ----",
    "Reason: requires database connection",
    "",
    "-- Success (test-bar.R:5): multiplication works ----",
    "",
    "",
    "-- Failure (test-baz.R:8): something else ----",
    "unexpected error"
  ), fileext = ".log")

  res <- parse_dispatch_log(tmp)
  expect_s3_class(res, "data.table")
  expect_equal(nrow(res), 4L)

  expect_equal(res$file,   c("test-foo.R", "test-foo.R", "test-bar.R", "test-baz.R"))
  expect_equal(res$test,   c("addition works", "division skips", "multiplication works", "something else"))
  expect_equal(res$status, c("failure", "skip", "success", "failure"))

  expect_match(res$message[1], "not equal")
  expect_match(res$message[2], "database connection")
  expect_equal(res$message[3], "")
  expect_match(res$message[4], "unexpected error")
})

test_that("parse_dispatch_log returns empty data.table for log with no entries", {
  tmp <- withr::local_tempfile(lines = c(
    "Loading courieR",
    "Testing courieR",
    "v | F W S  OK | Context",
    "All tests passed."
  ), fileext = ".log")

  res <- parse_dispatch_log(tmp)
  expect_equal(nrow(res), 0L)
})

test_that("parse_dispatch_log returns empty data.table for empty file", {
  tmp <- withr::local_tempfile(lines = character(), fileext = ".log")
  res <- parse_dispatch_log(tmp)
  expect_equal(nrow(res), 0L)
})
