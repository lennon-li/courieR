test_that("run_r_command works", {
  withr::local_tempdir("test_dir")
  res <- run_r_command(".", "1+1", "baseline", "test")
  expect_equal(res$status, "running")
  expect_true(inherits(res$process, "r_process"))
  res$process$wait()
})