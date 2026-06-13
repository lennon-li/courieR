test_that("find_routes runs without error", {
  res <- find_routes()
  expect_s3_class(res, "data.frame")

})

test_that("find_routes reports home and library columns", {
  res <- find_routes()
  expect_true(all(c("version", "rscript_path", "home", "library", "is_current") %in% names(res)))
  expect_type(res$home, "character")
  expect_type(res$library, "character")
})

test_that("find_routes does not leak the parent's R_LIBS_USER into probed installs", {
  skip_on_cran()
  # R always exports R_LIBS_USER into its session env. If the detection probe
  # inherited it, every probed install would report THIS session's library
  # instead of its own, making distinct installs look like they share a library.
  fake <- file.path(tempdir(), "courieR-fake-libloc")
  dir.create(fake, showWarnings = FALSE)  # R only adds existing dirs to .libPaths()
  old <- Sys.getenv("R_LIBS_USER", unset = NA)
  Sys.setenv(R_LIBS_USER = fake)
  on.exit({
    if (is.na(old)) Sys.unsetenv("R_LIBS_USER") else Sys.setenv(R_LIBS_USER = old)
  }, add = TRUE)

  res <- find_routes()
  skip_if(nrow(res) == 0, "No R installations detected")
  fake_norm <- as.character(fs::path_norm(fake))
  expect_false(any(!is.na(res$library) & res$library == fake_norm))
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

# Helper: create a fake Rscript executable that sleeps, then reports a valid
# probe payload (major||SEP||minor||SEP||home||SEP||libs). Unix-only.
local_fake_rscript <- function(sleep_secs, version_minor = "9.9",
                               env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  path <- file.path(dir, "Rscript")
  writeLines(c(
    "#!/bin/sh",
    sprintf("sleep %s", sleep_secs),
    sprintf(
      "printf '4||SEP||%s||SEP||/fake/home||SEP||/fake/lib'",
      version_minor
    )
  ), path)
  Sys.chmod(path, "0755")
  path
}

test_that("find_routes detects installs whose probe takes longer than 3s", {
  skip_on_cran()
  skip_on_os("windows")
  # Regression: a hard 3s probe timeout silently dropped real R installs on
  # slow machines (antivirus/OneDrive cold starts), so detection flickered
  # between runs. The default timeout must comfortably absorb a slow start.
  fake <- local_fake_rscript(sleep_secs = 4)
  res <- find_routes(search_paths = fake)
  expect_true(fake %in% res$rscript_path)
})

test_that("find_routes probe timeout is configurable and warns when exceeded", {
  skip_on_cran()
  skip_on_os("windows")
  fake <- local_fake_rscript(sleep_secs = 10)
  withr::local_options(courier.probe_timeout = 0.5)
  expect_warning(
    res <- find_routes(search_paths = fake),
    "timed out"
  )
  expect_false(fake %in% res$rscript_path)
})
