test_that("rig functions work", {
  expect_type(rig_available(), "logical")
  if (rig_available()) {
    expect_s3_class(rig_list(), "data.frame")
  }
})

test_that("rig_list keeps the active version marked with a leading '* '", {
  # `rig list` prefixes the active/default install with "* "; the version
  # regex must not require the line to start with a digit, or the active
  # install silently drops out of the returned data frame (A7).
  mockery::stub(rig_list, "rig_available", TRUE)
  mockery::stub(rig_list, "processx::run", list(
    status = 0,
    stdout = "* 4.5.0  (via env var RIG_DEFAULT_VERSION)\n  4.3.1 \n  devel\n"
  ))

  out <- rig_list()
  expect_true("4.5.0" %in% trimws(sub("\\s*\\(.*\\)$", "", out$version)))
  expect_true(any(grepl("^4\\.3\\.1", out$version)))
  expect_false(any(startsWith(out$version, "*")))
})