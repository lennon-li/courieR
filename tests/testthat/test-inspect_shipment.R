test_that("inspect_shipment works", {
  # local_dir() (not just local_tempdir()) - local_tempdir() alone does NOT
  # change the working directory, so relative writeLines()/inspect_shipment(".")
  # calls would otherwise land in tests/testthat/ and mutate its tracked
  # DESCRIPTION fixture (and leave a stray "tests" dir behind).
  withr::local_dir(withr::local_tempdir("test_dir"))
  writeLines(c("Package: testpkg", "Version: 1.0"), "DESCRIPTION")
  fs::dir_create("tests")

  res <- inspect_shipment(".")
  expect_true(res$has_description)
  expect_true(res$is_package)
  expect_true(res$has_tests)
  expect_false(res$has_renv)
})

test_that("inspect_shipment warns (rather than silently swallowing) a malformed DESCRIPTION", {
  withr::local_dir(withr::local_tempdir("test_dir_malformed"))
  writeLines(c("this is not", "a valid DESCRIPTION file", ":::garbage:::"), "DESCRIPTION")

  expect_warning(inspect_shipment("."), class = "rlang_warning")
})
