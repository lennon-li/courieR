test_that("find_routes runs without error", {
  res <- find_routes()
  expect_s3_class(res, "data.frame")

})

test_that("find_routes accepts search_paths = NULL", {
  res <- find_routes(search_paths = NULL)
  expect_s3_class(res, "data.frame")

})

test_that("find_routes handles nonexistent search_paths gracefully", {
  res <- find_routes(search_paths = "/nonexistent/path/to/r")
  expect_s3_class(res, "data.frame")
})
