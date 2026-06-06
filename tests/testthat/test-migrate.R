test_that("migrate errors on unknown version", {
  skip_on_cran()
  expect_error(
    migrate("0.0.0", "0.0.1"),
    class = "rlang_error"
  )
})

test_that("migrate errors when from and to resolve to the same installation", {
  skip_on_cran()
  routes <- find_routes()
  skip_if(nrow(routes) == 0, "No R installations detected")
  ver <- routes$version[[1]]
  expect_error(
    migrate(ver, ver),
    class = "rlang_error"
  )
})

test_that("migrate dry_run returns a plan without installing", {
  skip_on_cran()
  routes <- find_routes()
  skip_if(nrow(routes) < 2, "Need at least 2 R installations")
  skip_if(
    length(unique(routes$version)) < 2,
    "Need at least 2 R installations with distinct versions"
  )
  result <- migrate(
    from    = routes$version[[1]],
    to      = routes$version[[2]],
    dry_run = TRUE
  )
  expect_true(result$dry_run)
  expect_true(is.data.frame(result$plan) || data.table::is.data.table(result$plan))
})
