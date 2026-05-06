test_that("parse_check_log works", {
  res <- parse_check_log("nonexistent.txt")
  expect_s3_class(res, "data.table")
})