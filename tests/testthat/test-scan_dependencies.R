test_that("scan_dependencies works", {
  withr::local_tempdir("test_dir")
  writeLines(c("Package: testpkg", "Version: 1.0", "Imports: jsonlite"), "DESCRIPTION")
  
  res <- scan_dependencies(".")
  expect_true("jsonlite" %in% res$package)
  expect_equal(res$source[res$package == "jsonlite"], "Imports")
})