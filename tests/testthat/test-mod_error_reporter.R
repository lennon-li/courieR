test_that(".build_issue_url() is callable via courieR::: as used by mod_error_reporter", {
  url <- courieR:::.build_issue_url("boom", context = "unit test")
  expect_true(grepl("^https://github.com/lennon-li/courieR/issues/new", url))
  expect_true(grepl("boom", url))
})

test_that("mod_error_reporter.R does not call the internal helper unqualified", {
  src <- readLines(system.file(
    "app", "modules", "mod_error_reporter.R",
    package = "courieR"
  ))
  offending <- grep("[^:]\\.build_issue_url\\(", src, value = TRUE)
  expect_length(offending, 0)
})
