test_that("detect_project_type works", {
  withr::local_tempdir("test_dir")
  writeLines(c("Package: testpkg", "Version: 1.0"), "DESCRIPTION")
  fs::dir_create("tests")
  
  res <- detect_project_type(".")
  expect_true(res$has_description)
  expect_true(res$is_package)
  expect_true(res$has_tests)
  expect_false(res$has_renv)
})