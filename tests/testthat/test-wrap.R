test_that("wrap generates CRAN package spec", {
  expect_equal(wrap("dplyr"), "dplyr")
  expect_equal(wrap("dplyr", version = "1.1.4"), "dplyr@1.1.4")
  expect_equal(wrap("dplyr", version = "0.1"), "dplyr@0.1")
})

test_that("wrap generates Bioconductor spec", {
  expect_equal(wrap("limma", source_hint = "Bioconductor"), "bioc::limma")
})

test_that("wrap generates GitHub spec", {
  expect_equal(
    wrap("rlang", source_hint = "GitHub", github_ref = "r-lib/rlang@main"),
    "r-lib/rlang@main"
  )
})

test_that("wrap generates local spec", {
  skip_on_cran()
  tmp <- withr::local_tempfile()
  writeLines("", tmp)
  expect_equal(wrap("pkg", version = tmp, source_hint = "local"), paste0("local::", tmp))
})

test_that("wrap does not resolve a bare version string as a local path just because a same-named file exists (A9)", {
  skip_on_cran()
  # local_dir() (not just local_tempdir()) - local_tempdir() alone does NOT
  # change the working directory, so the stray "1.0.0" file below would
  # otherwise land directly in tests/testthat/.
  withr::local_dir(withr::local_tempdir())
  # A stray file that happens to share its name with the version string.
  writeLines("", "1.0.0")
  expect_equal(wrap("pkg", version = "1.0.0", source_hint = "local"), "pkg@1.0.0")
})

test_that("wrap returns package name for invalid version string", {
  expect_equal(wrap("pkg", version = ">= 1.0"), "pkg")
})

test_that("wrap returns package name when version is NULL", {
  expect_equal(wrap("mypackage"), "mypackage")
})
