routes <- function(...) {
  rows <- list(...)
  data.frame(
    version      = vapply(rows, `[[`, character(1), "version"),
    rscript_path = vapply(rows, `[[`, character(1), "rscript_path"),
    library      = vapply(rows, `[[`, character(1), "library"),
    is_current   = FALSE,
    stringsAsFactors = FALSE
  )
}
r <- function(version, rscript_path, library) {
  list(version = version, rscript_path = rscript_path, library = library)
}

test_that("eligible_targets excludes the source itself", {
  rt <- routes(
    r("4.5.1", "/a/Rscript", "/lib/a"),
    r("4.5.2", "/b/Rscript", "/lib/b")
  )
  res <- courieR:::eligible_targets(rt, "/a/Rscript")
  expect_false("/a/Rscript" %in% res$rscript_path)
  expect_equal(res$rscript_path, "/b/Rscript")
})

test_that("eligible_targets excludes installs that share the source library", {
  # Two 4.5.x installs sharing one user library: neither is a useful target.
  rt <- routes(
    r("4.5.1", "/a/Rscript", "/home/u/R/lib/4.5"),
    r("4.5.2", "/b/Rscript", "/home/u/R/lib/4.5"),
    r("4.6.0", "/c/Rscript", "/home/u/R/lib/4.6")
  )
  res <- courieR:::eligible_targets(rt, "/a/Rscript")
  expect_equal(res$rscript_path, "/c/Rscript")
})

test_that("eligible_targets excludes older-R installs", {
  rt <- routes(
    r("4.5.2", "/a/Rscript", "/lib/a"),
    r("4.4.1", "/b/Rscript", "/lib/b"),
    r("4.6.0", "/c/Rscript", "/lib/c")
  )
  res <- courieR:::eligible_targets(rt, "/a/Rscript")
  expect_setequal(res$rscript_path, "/c/Rscript")
})

test_that("eligible_targets keeps same-or-newer with a different library", {
  rt <- routes(
    r("4.5.1", "/a/Rscript", "/lib/a"),
    r("4.5.2", "/b/Rscript", "/lib/b")  # same minor, DIFFERENT library
  )
  res <- courieR:::eligible_targets(rt, "/a/Rscript")
  expect_equal(res$rscript_path, "/b/Rscript")
})

test_that("eligible_targets keeps unknown versions eligible", {
  rt <- routes(
    r("4.5.1", "/a/Rscript", "/lib/a"),
    r("",      "/b/Rscript", "/lib/b")
  )
  res <- courieR:::eligible_targets(rt, "/a/Rscript")
  expect_true("/b/Rscript" %in% res$rscript_path)
})

test_that("eligible_targets returns empty when no source / empty routes", {
  rt <- routes(r("4.5.1", "/a/Rscript", "/lib/a"))
  expect_equal(nrow(courieR:::eligible_targets(rt, "")), 0L)
  expect_equal(nrow(courieR:::eligible_targets(rt[0, ], "/a/Rscript")), 0L)
})

test_that("eligible_targets tolerates a missing library column", {
  rt <- data.frame(
    version = c("4.5.1", "4.6.0"),
    rscript_path = c("/a/Rscript", "/b/Rscript"),
    is_current = FALSE,
    stringsAsFactors = FALSE
  )
  res <- courieR:::eligible_targets(rt, "/a/Rscript")
  expect_equal(res$rscript_path, "/b/Rscript")
})
