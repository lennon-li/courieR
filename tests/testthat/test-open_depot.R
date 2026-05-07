test_that("open_depot creates directories and gitignore", {
  withr::local_tempdir("test_dir")

  res <- open_depot(".")

  base_dir <- fs::path(".", ".courier-depot")
  expect_equal(as.character(fs::path_abs(res)), as.character(fs::path_abs(base_dir)))

  expect_true(fs::dir_exists(base_dir))
  expect_true(fs::dir_exists(fs::path(base_dir, "logs", "baseline")))
  expect_true(fs::dir_exists(fs::path(base_dir, "logs", "post_migration")))
  expect_true(fs::dir_exists(fs::path(base_dir, "reports")))
  expect_true(fs::dir_exists(fs::path(base_dir, "cache")))
  expect_true(fs::dir_exists(fs::path(base_dir, "artifacts")))

  expect_true(fs::file_exists(fs::path(base_dir, ".gitignore")))
  expect_equal(readLines(fs::path(base_dir, ".gitignore")), "*")

  # Idempotency check
  expect_silent(open_depot("."))
})
