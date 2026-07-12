# Regression test for A4: Custom Dispatch must ship by package NAME
# (input$ship_cb_pkgs), not by positional row index into a possibly-stale
# filtered view. Uses shiny::testServer against the real module, following the
# pattern in test-app-refresh.R.

mod_path <- testthat::test_path("..", "..", "inst", "app", "modules", "mod_depot_ship.R")
if (!file.exists(mod_path)) {
  mod_path <- system.file("app/modules/mod_depot_ship.R", package = "courieR")
}
helpers_path <- testthat::test_path("..", "..", "inst", "app", "modules", "app_helpers.R")
if (!file.exists(helpers_path)) {
  helpers_path <- system.file("app/modules/app_helpers.R", package = "courieR")
}

test_that("Ship button resolves checked packages by name, ignoring stale/unknown selections", {
  skip_on_cran()
  skip_if_not_installed("shiny")
  skip_if_not_installed("DT")
  skip_if(mod_path == "" || !file.exists(mod_path), "mod_depot_ship.R not found")

  library(shiny)
  `%||%` <- function(a, b) if (is.null(a)) b else a
  source(helpers_path, local = TRUE)
  source(mod_path, local = TRUE)

  comp <- data.frame(
    package            = c("pkgA", "pkgB", "pkgC"),
    status             = c("missing-from-target", "same", "missing-from-target"),
    version_in_source  = c("1.0", "1.0", "1.0"),
    version_in_target  = c(NA, "1.0", NA),
    repo_in_source     = c("CRAN", "CRAN", "CRAN"),
    repo_in_target     = c(NA, "CRAN", NA),
    stringsAsFactors   = FALSE
  )

  seen_batches <- NULL
  mockery::stub(
    mod_depot_ship_server, ".build_depot_ship_batches",
    function(actions, comp, direction, from_path, to_path) {
      seen_batches <<- names(actions)[actions != "skip"]
      list()  # empty batches: short-circuits before any real ship() call
    }
  )

  testServer(mod_depot_ship_server, args = list(
    comparison_rv     = reactiveVal(comp),
    from_r_path       = reactiveVal("/usr/bin/Rscript"),
    to_r_path         = reactiveVal("/usr/bin/Rscript"),
    sync_direction_rv = reactiveVal("source_to_target"),
    transfer_mode_rv  = reactiveVal("online"),
    push_error        = function(...) NULL
  ), {
    session$flushReact()
    # Simulate the browser sending package names for the checked rows,
    # including one name that is no longer in the current comparison (as if
    # the table had re-filtered after the checkbox was ticked).
    session$setInputs(ship_cb_pkgs = c("pkgA", "stale-package-not-in-comp"))
    session$setInputs(ship_mode = "online")
    session$setInputs(depot_ship_btn = 1)
    session$flushReact()
  })

  expect_equal(seen_batches, "pkgA")
})
