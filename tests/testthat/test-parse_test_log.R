test_that("parse_test_log works", {
  res <- parse_test_log("nonexistent.txt")
  expect_s3_class(res, "data.table")
})