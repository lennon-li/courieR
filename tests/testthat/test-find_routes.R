test_that("find_routes runs without error", {
  res <- find_routes()
  expect_s3_class(res, "data.frame")
  expect_true(any(res$is_current))
})
