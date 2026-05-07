test_that("inventory classifies correctly", {
  src <- data.table::data.table(
    package = c("pkgA", "pkgB", "pkgC", "pkgD", "pkgE"),
    version = c("1.0.0", "2.0.0", "1.5.0", "3.0.0", "4.0.0"),
    priority = c(NA, NA, NA, "base", NA),
    source = c("CRAN", "CRAN", "CRAN", "CRAN", "CRAN")
  )

  tgt <- data.table::data.table(
    package = c("pkgB", "pkgC", "pkgD"),
    version = c("1.5.0", "1.5.0", "3.0.0"),
    priority = c(NA, NA, "base"),
    source = c("CRAN", "CRAN", "CRAN")
  )

  res <- inventory(src, tgt)

  expect_equal(nrow(res$missing), 2)  # pkgA, pkgE (pkgD is base so excluded from src)
  expect_true(all(res$missing$package %in% c("pkgA", "pkgE")))

  expect_equal(nrow(res$outdated), 1) # pkgB (2.0.0 > 1.5.0)
  expect_equal(res$outdated$package, "pkgB")

  expect_equal(nrow(res$same), 1)     # pkgC
  expect_equal(res$same$package, "pkgC")

  expect_equal(res$summary$total_source, 4)
})

test_that("wrap works", {
  expect_equal(wrap("pkg"), "pkg")
  expect_equal(wrap("pkg", "1.0.0"), "pkg@1.0.0")
  expect_equal(wrap("pkg", source_hint = "Bioconductor"), "bioc::pkg")
  expect_equal(wrap("pkg", source_hint = "GitHub", github_ref = "user/pkg@main"), "user/pkg@main")
})
