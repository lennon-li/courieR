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

  # pkgA has compiled code (a libs/ dir), so online mode reinstalls it via pak.
  compiled_lib <- file.path(tempdir(), "courieR_test_pkgA")
  dir.create(file.path(compiled_lib, "libs"), recursive = TRUE, showWarnings = FALSE)

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
      missing = data.table::data.table(package = "pkgA", version.x = "1.0", source = "CRAN", libpath = compiled_lib),
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

  compiled_lib <- file.path(tempdir(), "courieR_test_logcb_pkgA")
  dir.create(file.path(compiled_lib, "libs"), recursive = TRUE, showWarnings = FALSE)

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
      missing = data.table::data.table(package = "pkgA", version.x = "1.0", source = "CRAN", libpath = compiled_lib),
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

test_that("ship() online mode copies unknown-source packages instead of poisoning the pak batch", {
  skip_if_not_installed("mockery")

  manifest_calls <- 0L
  pak_plan_seen <- NULL
  copy_plan_seen <- NULL

  mockery::stub(ship, "fs::file_exists", function(...) TRUE)
  mockery::stub(ship, "manifest", function(...) {
    manifest_calls <<- manifest_calls + 1L
    if (manifest_calls == 3L) {
      return(data.table::data.table(package = "pkgCRAN", version = "1.0", source = "CRAN"))
    }
    data.table::data.table()
  })
  # pkgCRAN has compiled code -> reinstalled via pak; pkgLocal is unknown -> copied.
  compiled_lib <- file.path(tempdir(), "courieR_test_pkgCRAN")
  dir.create(file.path(compiled_lib, "libs"), recursive = TRUE, showWarnings = FALSE)

  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(
        package   = c("pkgCRAN", "pkgLocal"),
        version.x = c("1.0", "0.0.0.9000"),
        source    = c("CRAN", "unknown"),
        libpath   = c(compiled_lib, NA_character_)
      ),
      outdated = data.table::data.table(),
      comparison = data.table::data.table()
    )
  })
  mockery::stub(ship, "find_target_lib", function(...) tempdir())
  mockery::stub(ship, ".run_pak_plan", function(plan, target_path, ...) {
    pak_plan_seen <<- plan
    data.table::data.table(package = plan$package, status = "success", message = "pak completed")
  })
  mockery::stub(ship, "copy_packages", function(plan, target_lib, ...) {
    copy_plan_seen <<- plan
    data.table::data.table(package = plan$package, status = "success", message = "copied")
  })

  res <- ship("dummy_src", "dummy_tgt", dry_run = FALSE, mode = "online")

  # The unresolvable local package must NOT be in the pak solve.
  expect_equal(pak_plan_seen$package, "pkgCRAN")
  # It must be routed to a direct copy instead.
  expect_true("pkgLocal" %in% copy_plan_seen$package)
  # And reported in results as copied.
  local_row <- res$results[res$results$package == "pkgLocal", ]
  expect_equal(nrow(local_row), 1)
  expect_equal(local_row$message, "copied")
})

test_that("ship() reuses provided manifests and skips scanning", {
  skip_if_not_installed("mockery")

  manifest_calls <- 0L
  mockery::stub(ship, "fs::file_exists", function(...) TRUE)
  mockery::stub(ship, "manifest", function(...) {
    manifest_calls <<- manifest_calls + 1L
    data.table::data.table()
  })
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(package = "pkgA", version.x = "1.0", source = "CRAN"),
      outdated = data.table::data.table()
    )
  })

  src <- data.table::data.table(package = "pkgA", version = "1.0", source = "CRAN")
  tgt <- data.table::data.table()
  res <- ship("dummy_src", "dummy_tgt", dry_run = TRUE, source_pkgs = src, target_pkgs = tgt)

  # Both sides supplied -> no manifest() subprocess scans.
  expect_equal(manifest_calls, 0L)
  expect_true(res$dry_run)
})

test_that("ship() online mode copies pure-R CRAN packages instead of invoking pak", {
  skip_if_not_installed("mockery")

  pak_called <- FALSE
  copy_plan_seen <- NULL

  pure_r_lib <- file.path(tempdir(), "courieR_test_pure_r_pkg")
  dir.create(pure_r_lib, recursive = TRUE, showWarnings = FALSE)

  mockery::stub(ship, "fs::file_exists", function(...) TRUE)
  mockery::stub(ship, "manifest", function(...) {
    data.table::data.table(package = "exact", version = "3.3", source = "CRAN")
  })
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(
        package = "exact",
        version.x = "3.3",
        source = "CRAN",
        libpath = pure_r_lib
      ),
      outdated = data.table::data.table(),
      comparison = data.table::data.table()
    )
  })
  mockery::stub(ship, "find_target_lib", function(...) tempdir())
  mockery::stub(ship, ".run_pak_plan", function(...) {
    pak_called <<- TRUE
    data.table::data.table(package = character(), status = character(), message = character())
  })
  mockery::stub(ship, "copy_packages", function(plan, target_lib, ...) {
    copy_plan_seen <<- plan
    data.table::data.table(package = plan$package, status = "success", message = "copied")
  })

  res <- ship("dummy_src", "dummy_tgt", packages = "exact", dry_run = FALSE, mode = "online")

  expect_false(pak_called)
  expect_equal(copy_plan_seen$package, "exact")
  expect_equal(res$results$message, "copied")
})

test_that("ship() passes upgrade flag through to pak for compiled online packages", {
  skip_if_not_installed("mockery")

  upgrade_seen <- NULL
  compiled_lib <- file.path(tempdir(), "courieR_test_compiled_upgrade_flag")
  dir.create(file.path(compiled_lib, "libs"), recursive = TRUE, showWarnings = FALSE)

  mockery::stub(ship, "fs::file_exists", function(...) TRUE)
  mockery::stub(ship, "manifest", function(...) {
    data.table::data.table(package = "pkgA", version = "1.0", source = "CRAN")
  })
  mockery::stub(ship, "inventory", function(...) {
    list(
      missing = data.table::data.table(
        package = "pkgA",
        version.x = "1.0",
        source = "CRAN",
        libpath = compiled_lib
      ),
      outdated = data.table::data.table(),
      comparison = data.table::data.table()
    )
  })
  mockery::stub(ship, "find_target_lib", function(...) tempdir())
  mockery::stub(ship, ".run_pak_plan", function(plan, target_path, upgrade = FALSE, ...) {
    upgrade_seen <<- upgrade
    data.table::data.table(package = plan$package, status = "success", message = "pak completed")
  })

  res <- ship("dummy_src", "dummy_tgt", packages = "pkgA", dry_run = FALSE, mode = "online", upgrade = FALSE)

  expect_false(upgrade_seen)
  expect_equal(res$results$status, "success")
})

test_that("ship() rejects invalid mode", {
  skip_if_not_installed("mockery")

  mockery::stub(ship, "fs::file_exists", function(...) TRUE)
  expect_error(
    ship("dummy_src", "dummy_tgt", mode = "turbo"),
    "mode"
  )
})
