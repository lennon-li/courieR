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
