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
  expect_equal(res$comparison[["status"]][match(c("pkgA", "pkgB", "pkgC", "pkgE"), res$comparison[["package"]])],
               c("missing", "outdated", "same", "missing"))
})

test_that("inventory handles empty or pre-populated destination libraries", {
  src <- data.table::data.table(
    package = c("pkgA", "pkgB", "pkgC"),
    version = c("1.0.0", "2.0.0", "3.0.0"),
    priority = NA_character_,
    source = "CRAN"
  )

  populated_tgt <- data.table::data.table(
    package = c("pkgB", "pkgC", "pkgZ"),
    version = c("1.0.0", "3.0.0", "9.9.9"),
    source = "CRAN"
  )

  populated_res <- inventory(src, populated_tgt)
  expect_equal(populated_res$comparison[["status"]][match(c("pkgA", "pkgB", "pkgC"), populated_res$comparison[["package"]])],
               c("missing", "outdated", "same"))
  expect_equal(populated_res$comparison[["package"]][populated_res$comparison[["status"]] == "missing"], "pkgA")

  empty_tgt <- data.table::data.table()
  empty_res <- inventory(src, empty_tgt)
  expect_equal(nrow(empty_res$missing), 3)
  expect_equal(sort(empty_res$comparison[["package"]][empty_res$comparison[["status"]] == "missing"]), sort(src$package))
})

test_that("wrap works", {
  expect_equal(wrap("pkg"), "pkg")
  expect_equal(wrap("pkg", "1.0.0"), "pkg@1.0.0")
  expect_equal(wrap("pkg", source_hint = "Bioconductor"), "bioc::pkg")
  expect_equal(wrap("pkg", source_hint = "GitHub", github_ref = "user/pkg@main"), "user/pkg@main")
})
