test_that("take_inventory works", {
  withr::local_tempdir("test_dir")
  writeLines(c("Package: testpkg", "Version: 1.0", "Imports: jsonlite"), "DESCRIPTION")

  res <- take_inventory(".")
  expect_true("jsonlite" %in% res$package)
  expect_equal(res$source[res$package == "jsonlite"], "Imports")
})
