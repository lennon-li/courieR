test_that("detect_r_installations runs without error", {
  res <- detect_r_installations()
  expect_s3_class(res, "data.frame")
  expect_true(any(res$is_current))
})