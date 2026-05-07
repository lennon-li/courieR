test_that("ship dry_run works", {
  mockery::stub(ship, "manifest", function(...) data.table::data.table())
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(package = "pkgA", version.x = "1.0", source = "CRAN"),
      outdated = data.table::data.table(package = "pkgB", version.x = "2.0", source = "CRAN")
    )
  })

  mockery::stub(ship, "fs::file_exists", function(...) TRUE)

  res <- ship("dummy_src", "dummy_tgt", dry_run = TRUE)

  expect_true(res$dry_run)
  expect_equal(nrow(res$plan), 2)
  expect_equal(nrow(res$results), 0)
  expect_true("pak_spec" %in% names(res$plan))
})
