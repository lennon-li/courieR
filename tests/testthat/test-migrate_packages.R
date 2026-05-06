test_that("migrate_packages dry_run works", {
  mockery::stub(migrate_packages, "list_packages", function(...) data.table::data.table())
  mockery::stub(migrate_packages, "compare_libraries", function(...) {
    list(
      missing = data.table::data.table(package="pkgA", version.x="1.0", source="CRAN"),
      outdated = data.table::data.table(package="pkgB", version.x="2.0", source="CRAN")
    )
  })
  
  mockery::stub(migrate_packages, "fs::file_exists", function(...) TRUE)
  
  res <- migrate_packages("dummy_src", "dummy_tgt", dry_run = TRUE)
  
  expect_true(res$dry_run)
  expect_equal(nrow(res$plan), 2)
  expect_equal(nrow(res$results), 0)
  expect_true("pak_spec" %in% names(res$plan))
})