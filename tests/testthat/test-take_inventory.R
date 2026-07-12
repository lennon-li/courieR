test_that("take_inventory works", {
  # local_dir() (not just local_tempdir()) - local_tempdir() alone does NOT
  # change the working directory, so relative writeLines()/take_inventory(".")
  # calls would otherwise land in tests/testthat/ and mutate its tracked
  # DESCRIPTION fixture.
  withr::local_dir(withr::local_tempdir("test_dir"))
  writeLines(c("Package: testpkg", "Version: 1.0", "Imports: jsonlite"), "DESCRIPTION")

  res <- take_inventory(".")
  expect_true("jsonlite" %in% res$package)
  expect_equal(res$source[res$package == "jsonlite"], "Imports")
})

test_that("take_inventory warns (rather than silently swallowing) a malformed DESCRIPTION", {
  withr::local_dir(withr::local_tempdir("test_dir_malformed"))
  # Not a valid DEBIAN-control-format file: desc::desc() should error on this.
  writeLines(c("this is not", "a valid DESCRIPTION file", ":::garbage:::"), "DESCRIPTION")

  expect_warning(take_inventory("."), class = "rlang_warning")
})

test_that("take_inventory warns (rather than silently swallowing) a malformed renv.lock", {
  withr::local_dir(withr::local_tempdir("test_dir_malformed_renv"))
  writeLines("{ not valid json", "renv.lock")

  expect_warning(take_inventory("."), class = "rlang_warning")
})
