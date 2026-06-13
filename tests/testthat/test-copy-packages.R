test_that("copy_packages copies a simple package", {
  src_lib <- withr::local_tempdir()
  tgt_lib <- withr::local_tempdir()
  dir.create(file.path(src_lib, "mypkg", "R"), recursive = TRUE)
  writeLines("# stub", file.path(src_lib, "mypkg", "R", "mypkg.R"))

  plan <- data.table::data.table(
    package = "mypkg",
    libpath = file.path(src_lib, "mypkg"),
    compiled = FALSE
  )
  result <- copy_packages(plan, tgt_lib, log_callback = NULL)
  expect_true(file.exists(file.path(tgt_lib, "mypkg", "R", "mypkg.R")))
  expect_equal(result$status, "success")
})

test_that("copy_packages reports skip when libpath missing", {
  tgt_lib <- withr::local_tempdir()
  plan <- data.table::data.table(
    package = "ghost",
    libpath = NA_character_,
    compiled = FALSE
  )
  result <- copy_packages(plan, tgt_lib, log_callback = NULL)
  expect_equal(result$status, "skipped")
})

test_that("copy_packages reports error when src dir does not exist", {
  tgt_lib <- withr::local_tempdir()
  plan <- data.table::data.table(
    package = "gone",
    libpath = "/nonexistent/path/gone",
    compiled = FALSE
  )
  result <- copy_packages(plan, tgt_lib, log_callback = NULL)
  expect_equal(result$status, "error")
})

test_that(".copy_plan resolves libpath to the per-package source directory", {
  # Regression: a manifest's `libpath` is the LIBRARY directory, shared by every
  # package. .copy_plan must join the package name so copy_packages copies the
  # package — not the whole library — into target/<pkg>.
  lib <- "/some/library/4.4"
  plan <- data.table::data.table(package = c("brew", "ini"), libpath.x = lib)
  cp <- courieR:::.copy_plan(plan)
  expect_equal(cp$libpath, file.path(lib, c("brew", "ini")))
})

test_that(".copy_plan + copy_packages copy the package, not the whole library", {
  # End-to-end against a realistic library layout: libpath is the library root
  # containing several packages. The shipped target must contain a valid package
  # (target/brew/DESCRIPTION), never the entire library nested under target/brew.
  src_lib <- withr::local_tempdir()
  tgt_lib <- withr::local_tempdir()
  for (p in c("brew", "ini", "other")) {
    dir.create(file.path(src_lib, p), recursive = TRUE)
    writeLines(sprintf("Package: %s", p), file.path(src_lib, p, "DESCRIPTION"))
  }

  # Mimics the manifest comparison: libpath.x is the LIBRARY dir for every row.
  cmp <- data.table::data.table(package = c("brew", "ini"), libpath.x = src_lib)
  plan <- courieR:::.copy_plan(cmp)
  res <- copy_packages(plan, tgt_lib, log_callback = NULL)

  expect_equal(res$status, c("success", "success"))
  expect_true(file.exists(file.path(tgt_lib, "brew", "DESCRIPTION")))
  expect_true(file.exists(file.path(tgt_lib, "ini", "DESCRIPTION")))
  # The whole library must NOT be nested under the package directory.
  expect_false(dir.exists(file.path(tgt_lib, "brew", "other")))
})
