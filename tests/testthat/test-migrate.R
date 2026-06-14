test_that("migrate resolves partial major.minor version (e.g. '4.6' matches '4.6.0')", {
  skip_on_cran()
  routes <- find_routes()
  skip_if(nrow(routes) == 0, "No R installations detected")
  # Build partial versions and keep only those that are unambiguous (unique major.minor)
  routes$partial <- sub("\\.[0-9]+$", "", routes$version)
  partial_counts <- table(routes$partial)
  unique_routes <- routes[routes$partial %in% names(partial_counts[partial_counts == 1]), ]
  skip_if(
    nrow(unique_routes) == 0,
    "No R installation has a unique major.minor partial version"
  )
  partial_ver <- unique_routes$partial[[1]]
  skip_if(partial_ver == unique_routes$version[[1]], "Version has no patch component to strip")
  if (nrow(unique_routes) == 1) {
    # Only one unambiguous partial — same-install error expected, but NOT "no match"
    err <- tryCatch(migrate(partial_ver, partial_ver), error = function(e) e)
    expect_match(conditionMessage(err), "same installation", ignore.case = TRUE)
  } else {
    partial_second <- unique_routes$partial[[2]]
    result <- migrate(partial_ver, partial_second, dry_run = TRUE)
    expect_true(result$dry_run)
  }
})

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
