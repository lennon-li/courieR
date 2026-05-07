test_that("dispatch works", {
  withr::local_tempdir("test_dir")
  res <- dispatch(".", "1+1", "baseline", "test")
  expect_equal(res$status, "running")
  expect_true(inherits(res$process, "r_process"))
  res$process$wait()
})
