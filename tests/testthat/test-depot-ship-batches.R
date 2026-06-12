# Find path to mod_depot_ship.R
mod_path <- testthat::test_path("..", "..", "inst", "app", "modules", "mod_depot_ship.R")
if (!file.exists(mod_path)) {
  # During R CMD check, the package is installed, inst/ is stripped,
  # and the file is located inside the installed package structure.
  mod_path <- system.file("app/modules/mod_depot_ship.R", package = "courieR")
}
if (mod_path == "" || !file.exists(mod_path)) {
  # Fallback for R CMD check structure relative to test directory
  mod_path <- testthat::test_path("..", "..", "courieR", "app", "modules", "mod_depot_ship.R")
}

source(mod_path, local = TRUE)

comp <- data.frame(
  package = c("ggplot2", "dplyr", "tidyr", "patchwork", "scales"),
  status  = c("missing-from-target", "newer-in-source", "missing-from-source", "same", "newer-in-target"),
  stringsAsFactors = FALSE
)

test_that(".build_depot_ship_batches returns empty list when all skip", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "skip", patchwork = "skip", scales = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "source_to_target", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 0L)
})

test_that(".build_depot_ship_batches routes source_to_target correctly", {
  actions <- c(ggplot2 = "online", dplyr = "ship", tidyr = "skip", patchwork = "skip", scales = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "source_to_target", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 2L)

  online_batch <- result[[which(sapply(result, `[[`, "mode") == "online")]]
  expect_equal(online_batch$pkgs,  "ggplot2")
  expect_equal(online_batch$src,   "/a/Rscript")
  expect_equal(online_batch$tgt,   "/b/Rscript")

  copy_batch <- result[[which(sapply(result, `[[`, "mode") == "offline")]]
  expect_equal(copy_batch$pkgs, "dplyr")
})

test_that(".build_depot_ship_batches routes target_to_source correctly", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "online", patchwork = "skip", scales = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "target_to_source", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 1L)
  expect_equal(result[[1]]$pkgs, "tidyr")
  expect_equal(result[[1]]$src,  "/b/Rscript")
  expect_equal(result[[1]]$tgt,  "/a/Rscript")
  expect_equal(result[[1]]$mode, "online")
})

test_that(".build_depot_ship_batches routes full (two-way) correctly", {
  actions <- c(ggplot2 = "online", dplyr = "skip", tidyr = "ship", patchwork = "skip", scales = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "full", "/a/Rscript", "/b/Rscript")
  modes <- sapply(result, `[[`, "mode")
  srcs  <- sapply(result, `[[`, "src")

  st_online <- result[[which(modes == "online" & srcs == "/a/Rscript")]]
  expect_equal(st_online$pkgs, "ggplot2")

  ts_copy <- result[[which(modes == "offline" & srcs == "/b/Rscript")]]
  expect_equal(ts_copy$pkgs, "tidyr")
})

test_that(".build_depot_ship_batches ignores 'same' packages in full direction", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "skip", patchwork = "online", scales = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "full", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 0L)
})

test_that(".build_depot_ship_batches routes newer-in-target to target_to_source in full direction", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "skip", patchwork = "skip", scales = "online")
  result  <- .build_depot_ship_batches(actions, comp, "full", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 1L)
  expect_equal(result[[1]]$pkgs, "scales")
  expect_equal(result[[1]]$src,  "/b/Rscript")
  expect_equal(result[[1]]$tgt,  "/a/Rscript")
  expect_equal(result[[1]]$mode, "online")
})
