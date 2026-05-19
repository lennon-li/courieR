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

test_that("ship package filtering works", {
  mockery::stub(ship, "manifest", function(...) data.table::data.table())
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(package = c("pkgA", "pkgB"), version.x = c("1.0", "2.0"), source = "CRAN"),
      outdated = data.table::data.table(package = "pkgC", version.x = "3.0", source = "CRAN")
    )
  })
  mockery::stub(ship, "fs::file_exists", function(...) TRUE)

  res <- ship("dummy_src", "dummy_tgt", packages = "pkgA", dry_run = TRUE)

  expect_equal(nrow(res$plan), 1)
  expect_equal(res$plan$package, "pkgA")
})

test_that("ship empty plan returns early", {
  mockery::stub(ship, "manifest", function(...) data.table::data.table())
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(),
      outdated = data.table::data.table()
    )
  })
  mockery::stub(ship, "fs::file_exists", function(...) TRUE)

  res <- ship("dummy_src", "dummy_tgt", dry_run = TRUE)

  expect_equal(nrow(res$plan), 0)
  expect_equal(nrow(res$results), 0)
  expect_true(res$dry_run)
})

test_that("ship errors on nonexistent source path", {
  expect_error(
    ship("/nonexistent/src/Rscript", "dummy_tgt", dry_run = TRUE),
    "Source Rscript not found"
  )
})

test_that("ship errors on nonexistent target path", {
  mockery::stub(ship, "fs::file_exists", function(path) {
    grepl("src", path)  # only source exists
  })

  expect_error(
    ship("dummy_src", "dummy_tgt", dry_run = TRUE),
    "Target Rscript not found"
  )
})
