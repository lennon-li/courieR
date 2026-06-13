# Integration test for the post-ship comparison refresh chain:
# refresh_request -> mod_sync observer -> scans (via shared cache) ->
# comparison_out. Uses two real R installations; skipped when unavailable.

mod_path <- testthat::test_path("..", "..", "inst", "app", "modules", "mod_sync.R")
if (!file.exists(mod_path)) {
  mod_path <- system.file("app/modules/mod_sync.R", package = "courieR")
}

test_that("refresh_request refreshes the comparison and reuses cached scans", {
  skip_on_cran()
  skip_if_not_installed("shiny")
  skip_if(mod_path == "" || !file.exists(mod_path), "mod_sync.R not found")

  src <- "/usr/local/bin/Rscript"
  tgt <- "/usr/bin/Rscript"
  skip_if_not(file.exists(src) && file.exists(tgt),
              "needs two local R installations")

  library(shiny)
  `%||%` <- function(a, b) if (is.null(a)) b else a
  source(mod_path, local = TRUE)

  # Shared scan cache mirroring server.R, instrumented to count real scans.
  scan_calls <- character(0)
  scan_store <- new.env(parent = emptyenv())
  shared_scans <- list(
    get = function(path, force = FALSE, log = NULL) {
      if (!force && !is.null(scan_store[[path]])) return(scan_store[[path]])
      scan_calls <<- c(scan_calls, path)
      m <- courieR::manifest(rscript_path = path, format = "data.table",
                             timeout_sec = 300L)
      if (!isTRUE(attr(m, "timed_out"))) scan_store[[path]] <- m
      m
    },
    invalidate = function(path) {
      if (!is.null(path) && nzchar(path) &&
          exists(path, envir = scan_store, inherits = FALSE)) {
        rm(list = path, envir = scan_store)
      }
    },
    clear = function() rm(list = ls(envir = scan_store), envir = scan_store)
  )

  comparison_seen <- NULL
  refresh_req <- reactiveVal(NULL)

  testServer(mod_sync_server, args = list(
    install_source_path = reactiveVal(NULL),
    install_target_path = reactiveVal(NULL),
    routes_cache        = reactiveVal(NULL),
    push_error          = function(...) NULL,
    comparison_out      = function(x) { comparison_seen <<- x },
    actionable_out      = function(x) NULL,
    sync_direction_out  = reactiveVal("source_to_target"),
    transfer_mode_out   = reactiveVal("online"),
    refresh_request     = refresh_req,
    shared_scans        = shared_scans
  ), {
    # Simulate the state after a Custom Dispatch ship: both libraries were
    # scanned during the ship, then the shipped-into target was invalidated.
    shared_scans$get(src)
    shared_scans$get(tgt)
    expect_equal(length(scan_calls), 2L)
    shared_scans$invalidate(tgt)

    refresh_req(list(source_path = src, target_path = tgt,
                     changed_paths = tgt, ts = Sys.time()))
    session$flushReact()
  })

  expect_false(is.null(comparison_seen))
  expect_gt(nrow(comparison_seen), 0L)
  expect_true("status" %in% names(comparison_seen))
  # The refresh must rescan ONLY the changed target; the source scan is reused.
  expect_equal(sum(scan_calls == src), 1L)
  expect_equal(sum(scan_calls == tgt), 2L)
})
