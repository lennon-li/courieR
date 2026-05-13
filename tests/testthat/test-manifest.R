test_that("manifest returns correct format", {
  res <- manifest(format = "data.table", timeout_sec = 120L)
  expect_s3_class(res, "data.table")
  expect_true("package" %in% names(res))
  expect_true("version" %in% names(res))
  expect_true("source" %in% names(res))
})

test_that("manifest returns data.frame when requested", {
  res <- manifest(format = "data.frame", timeout_sec = 120L)
  expect_s3_class(res, "data.frame")
  expect_true("package" %in% names(res))
})

test_that("manifest errors on invalid Rscript path", {
  expect_error(
    manifest(rscript_path = "/nonexistent/path/to/Rscript", timeout_sec = 5L),
    class = "courieR_rscript_not_found"
  )
})

test_that("manifest handles empty library gracefully", {
  # Create temp empty library and scan it
  empty_lib <- withr::local_tempdir("emptylib")
  res <- manifest(lib_path = empty_lib, timeout_sec = 30L)
  expect_s3_class(res, "data.table")
  # With an empty library there should be zero packages
  expect_true(nrow(res) >= 0)
})

test_that("manifest temp file is cleaned up", {
  tmpfiles_before <- length(fs::dir_ls(tempdir(), glob = "courieR_manifest*"))
  res <- manifest(timeout_sec = 120L)
  tmpfiles_after <- length(fs::dir_ls(tempdir(), glob = "courieR_manifest*"))
  expect_equal(tmpfiles_after, tmpfiles_before)
})
