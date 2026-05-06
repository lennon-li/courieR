test_that("list_packages returns correct format", {
  res <- list_packages(format = "data.table", timeout_sec = 120L)
  expect_s3_class(res, "data.table")
  expect_true("package" %in% names(res))
  expect_true("version" %in% names(res))
  expect_true("source" %in% names(res))
})