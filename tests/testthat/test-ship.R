test_that("ship dry_run works", {
  skip_if_not_installed("mockery")

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
  skip_if_not_installed("mockery")

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
  skip_if_not_installed("mockery")

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

test_that("ship installs through target Rscript", {
  skip_if_not_installed("mockery")

  manifest_calls <- 0L
  process_calls <- list()

  mockery::stub(ship, "fs::file_exists", function(...) TRUE)
  mockery::stub(ship, "manifest", function(...) {
    manifest_calls <<- manifest_calls + 1L
    if (manifest_calls == 3L) {
      return(data.table::data.table(package = "pkgA", version = "1.0", source = "CRAN"))
    }
    data.table::data.table()
  })
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(package = "pkgA", version.x = "1.0", source = "CRAN"),
      outdated = data.table::data.table(),
      comparison = data.table::data.table()
    )
  })
  mockery::stub(ship, "find_target_lib", function(...) tempdir())
  mockery::stub(ship, ".run_pak_plan", function(plan, target_path, ...) {
    process_calls[[length(process_calls) + 1L]] <<- list(command = target_path, plan = plan)
    data.table::data.table(package = plan$package, status = "success", message = "pak completed")
  })

  res <- ship("dummy_src", "dummy_tgt", dry_run = FALSE)

  expect_equal(res$results$status, "success")
  expect_equal(length(process_calls), 1L)
  expect_equal(process_calls[[1L]]$command, "dummy_tgt")
})

test_that("ship errors on nonexistent source path", {
  expect_error(
    ship("/nonexistent/src/Rscript", "dummy_tgt", dry_run = TRUE),
    "Source Rscript not found"
  )
})

test_that("ship errors on nonexistent target path", {
  skip_if_not_installed("mockery")

  mockery::stub(ship, "fs::file_exists", function(path) {
    grepl("src", path)  # only source exists
  })

  expect_error(
    ship("dummy_src", "dummy_tgt", dry_run = TRUE),
    "Target Rscript not found"
  )
})

test_that("ship calls log_callback before and after pak subprocess", {
  skip_if_not_installed("mockery")

  calls <- character()
  cb <- function(msg) calls <<- c(calls, msg)
  manifest_calls <- 0L

  mockery::stub(ship, "fs::file_exists", function(...) TRUE)
  mockery::stub(ship, "manifest", function(...) {
    manifest_calls <<- manifest_calls + 1L
    if (manifest_calls == 3L) {
      return(data.table::data.table(package = "pkgA", version = "1.0", source = "CRAN"))
    }
    data.table::data.table()
  })
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(package = "pkgA", version.x = "1.0", source = "CRAN"),
      outdated = data.table::data.table(),
      comparison = data.table::data.table()
    )
  })
  mockery::stub(ship, "find_target_lib", function(...) tempdir())
  mockery::stub(ship, ".run_pak_plan", function(plan, target_path, log_callback = NULL, ...) {
    log_callback("Running pak in the target R installation; first-time metadata loading may take 1-2 minutes.")
    log_callback("pak activity")
    log_callback("pak subprocess finished successfully.")
    data.table::data.table(package = plan$package, status = "success", message = "pak completed")
  })

  res <- ship("dummy_src", "dummy_tgt", dry_run = FALSE, log_callback = cb)

  expect_equal(res$results$status, "success")
  expect_true(any(grepl("Running pak", calls)))
  expect_true(any(grepl("pak activity", calls)))
  expect_true(any(grepl("finished successfully", calls)))
})

test_that("ship() mode='offline' with dry_run=TRUE returns correctly", {
  skip_if_not_installed("mockery")

  mockery::stub(ship, "manifest", function(...) data.table::data.table())
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(package = "pkgA", version.x = "1.0", source = "CRAN"),
      outdated = data.table::data.table(),
      comparison = data.table::data.table()
    )
  })
  mockery::stub(ship, "fs::file_exists", function(...) TRUE)

  result <- ship("dummy_src", "dummy_tgt", mode = "offline", dry_run = TRUE)
  expect_true(result$dry_run)
})

test_that("ship() plan has mode column", {
  skip_if_not_installed("mockery")

  mockery::stub(ship, "manifest", function(...) data.table::data.table())
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(package = "pkgA", version.x = "1.0", source = "CRAN"),
      outdated = data.table::data.table(),
      comparison = data.table::data.table()
    )
  })
  mockery::stub(ship, "fs::file_exists", function(...) TRUE)

  result <- ship("dummy_src", "dummy_tgt", dry_run = TRUE, mode = "online")
  expect_true("mode" %in% names(result$plan))
  expect_true(all(result$plan$mode == "online"))
})

test_that("ship() rejects invalid mode", {
  skip_if_not_installed("mockery")

  mockery::stub(ship, "fs::file_exists", function(...) TRUE)
  expect_error(
    ship("dummy_src", "dummy_tgt", mode = "turbo"),
    "mode"
  )
})
