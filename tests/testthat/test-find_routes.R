test_that("find_routes runs without error", {
  res <- find_routes()
  expect_s3_class(res, "data.frame")

})

test_that("find_routes reports a library column", {
  res <- find_routes()
  expect_true(all(c("version", "rscript_path", "library", "is_current") %in% names(res)))
  expect_type(res$library, "character")
})

test_that("find_routes does not collapse installs that share a version", {
  # Dedup is by executable, not version: two distinct Rscript paths that happen
  # to report the same version must both survive (they are told apart by their
  # library location downstream).
  res <- find_routes()
  skip_if(nrow(res) == 0, "No R installations detected")
  expect_equal(nrow(res), length(unique(res$rscript_path)))
})

test_that("find_routes accepts search_paths = NULL", {
  res <- find_routes(search_paths = NULL)
  expect_s3_class(res, "data.frame")

})

test_that("find_routes handles nonexistent search_paths gracefully", {
  res <- find_routes(search_paths = "/nonexistent/path/to/r")
  expect_s3_class(res, "data.frame")
})
