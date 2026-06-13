# End-to-end browser test (shinytest2 + headless Chrome) driving the real app
# through both Bulk Dispatch and Custom Dispatch, verifying the copy-path ship
# (.copy_plan) actually installs a package into the target library.
#
# Heavy and environment-specific: needs two real R installations, a Chrome
# binary, and modifies the target library. Opt in with COURIER_E2E=true.
# It also requires the WORKING-TREE courieR to be installed (the app subprocess
# does library(courieR)); run `R CMD INSTALL .` first.

e2e_enabled <- identical(Sys.getenv("COURIER_E2E"), "true")

test_that("browser: Bulk Compare + Custom Dispatch copy-ship installs into target", {
  skip_on_cran()
  skip_if_not(e2e_enabled, "set COURIER_E2E=true to run browser e2e")
  skip_if_not_installed("shinytest2")
  skip_if_not_installed("chromote")

  src     <- Sys.getenv("COURIER_E2E_SRC", "/opt/R/4.4.3/bin/Rscript")
  tgt     <- Sys.getenv("COURIER_E2E_TGT", "/opt/R/4.5.2/bin/Rscript")
  tgt_lib <- Sys.getenv("COURIER_E2E_TGT_LIB",
                        "/home/yeli/R/x86_64-pc-linux-gnu-library/4.5")
  skip_if_not(file.exists(src) && file.exists(tgt) && dir.exists(tgt_lib),
              "needs two real R installations and a writable target library")
  if (!nzchar(Sys.getenv("CHROMOTE_CHROME"))) {
    chrome <- Sys.which("google-chrome")
    skip_if(chrome == "", "no Chrome binary found")
    Sys.setenv(CHROMOTE_CHROME = chrome)
  }

  pkg <- "broman"  # local/private source -> copy path (the bug's path)

  # SETUP: ensure target is missing the package so it appears as shippable.
  unlink(file.path(tgt_lib, pkg), recursive = TRUE, force = TRUE)
  before <- courieR::manifest(rscript_path = tgt, format = "data.table")
  expect_false(pkg %in% before$package)

  app_dir <- testthat::test_path("..", "..", "inst", "app")
  if (!dir.exists(app_dir)) app_dir <- system.file("app", package = "courieR")
  skip_if(!dir.exists(app_dir), "app directory not found")

  app <- shinytest2::AppDriver$new(
    app_dir, name = "courier-e2e",
    load_timeout = 90000, timeout = 30000,
    height = 950, width = 1500, seed = 1
  )
  withr::defer(app$stop())

  app$wait_for_idle(duration = 1500, timeout = 60000)

  # --- BULK DISPATCH: pick routes, Compare, Preview plan (no install) ---
  app$set_inputs(`sync-install_source` = src, wait_ = FALSE)
  app$set_inputs(`sync-install_target` = tgt, wait_ = FALSE)
  app$wait_for_idle(duration = 800, timeout = 20000)
  app$click("sync-compare")
  app$wait_for_idle(duration = 2000, timeout = 120000)
  app$click("sync-preview_btn")
  app$wait_for_idle(duration = 1500, timeout = 30000)
  expect_false(is.null(app$get_html("#shiny-modal")))
  app$run_js(paste0("var m=document.getElementById('shiny-modal');",
                    "if(m&&window.bootstrap){var i=bootstrap.Modal.getInstance(m);",
                    "if(i) i.hide();}"))
  app$wait_for_idle(duration = 800, timeout = 10000)

  # --- CUSTOM DISPATCH: cherry-pick the package and ship via copy (offline) ---
  app$run_js("navigateToCustomDispatch();")
  app$wait_for_idle(duration = 1500, timeout = 30000)
  app$set_inputs(`env-depot_ship-ship_search` = pkg)
  app$wait_for_idle(duration = 1200, timeout = 20000)
  app$set_inputs(`env-depot_ship-ship_mode` = "offline", wait_ = FALSE)
  app$set_inputs(`env-depot_ship-ship_cb_rows` = 1,
                 allow_no_input_binding_ = TRUE, priority_ = "event")
  app$wait_for_idle(duration = 800, timeout = 10000)
  app$click("env-depot_ship-depot_ship_btn")
  app$wait_for_idle(duration = 3000, timeout = 120000)

  # --- VERIFY independently of the app process (clean child env) ---
  after <- courieR::manifest(rscript_path = tgt, format = "data.table")
  expect_true(pkg %in% after$package)                                   # in manifest
  expect_true(file.exists(file.path(tgt_lib, pkg, "DESCRIPTION")))      # valid layout
  expect_false(dir.exists(file.path(tgt_lib, pkg, pkg)))                # not nested
  loaded <- processx::run(
    tgt, c("--vanilla", "-e",
           sprintf("cat(requireNamespace(%s, quietly=TRUE))", shQuote(pkg))),
    env = courieR:::child_r_env(), error_on_status = FALSE
  )
  expect_match(loaded$stdout, "TRUE")                                   # loadable in target
})
