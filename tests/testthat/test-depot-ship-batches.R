source("inst/app/modules/mod_depot_ship.R", local = TRUE)

comp <- data.frame(
  package = c("ggplot2", "dplyr", "tidyr", "patchwork"),
  status  = c("missing-from-B", "newer-in-A", "missing-from-A", "same"),
  stringsAsFactors = FALSE
)

test_that(".build_depot_ship_batches returns empty list when all skip", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "skip", patchwork = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "A_to_B", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 0L)
})

test_that(".build_depot_ship_batches routes A_to_B correctly", {
  actions <- c(ggplot2 = "online", dplyr = "ship", tidyr = "skip", patchwork = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "A_to_B", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 2L)

  online_batch <- result[[which(sapply(result, `[[`, "mode") == "online")]]
  expect_equal(online_batch$pkgs,  "ggplot2")
  expect_equal(online_batch$src,   "/a/Rscript")
  expect_equal(online_batch$tgt,   "/b/Rscript")

  copy_batch <- result[[which(sapply(result, `[[`, "mode") == "offline")]]
  expect_equal(copy_batch$pkgs, "dplyr")
})

test_that(".build_depot_ship_batches routes B_to_A correctly", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "online", patchwork = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "B_to_A", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 1L)
  expect_equal(result[[1]]$pkgs, "tidyr")
  expect_equal(result[[1]]$src,  "/b/Rscript")
  expect_equal(result[[1]]$tgt,  "/a/Rscript")
  expect_equal(result[[1]]$mode, "online")
})

test_that(".build_depot_ship_batches routes full (two-way) correctly", {
  actions <- c(ggplot2 = "online", dplyr = "skip", tidyr = "ship", patchwork = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "full", "/a/Rscript", "/b/Rscript")
  modes <- sapply(result, `[[`, "mode")
  srcs  <- sapply(result, `[[`, "src")

  ab_online <- result[[which(modes == "online" & srcs == "/a/Rscript")]]
  expect_equal(ab_online$pkgs, "ggplot2")

  ba_copy <- result[[which(modes == "offline" & srcs == "/b/Rscript")]]
  expect_equal(ba_copy$pkgs, "tidyr")
})

test_that(".build_depot_ship_batches ignores 'same' packages in full direction", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "skip", patchwork = "online")
  result  <- .build_depot_ship_batches(actions, comp, "full", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 0L)
})
