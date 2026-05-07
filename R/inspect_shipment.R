#' Detect project characteristics
#'
#' @param project_path Path to the project
#' @return A named list
#' @examples
#' \donttest{
#'   res <- inspect_shipment(tempdir())
#'   res$is_package
#' }
#' @export
inspect_shipment <- function(project_path) {
  project_path <- fs::path_real(project_path)

  has_description <- fs::file_exists(fs::path(project_path, "DESCRIPTION"))
  has_renv <- fs::file_exists(fs::path(project_path, "renv.lock"))
  has_git <- fs::dir_exists(fs::path(project_path, ".git"))
  has_tests <- fs::dir_exists(fs::path(project_path, "tests"))

  is_package <- FALSE
  if (has_description) {
    tryCatch({
      d <- desc::desc(fs::path(project_path, "DESCRIPTION"))
      if (nzchar(d$get("Package")[[1]])) is_package <- TRUE
    }, error = function(e) NULL)
  }

  r_files <- as.character(fs::dir_ls(project_path, glob = "*.[Rr]", recurse = TRUE, type = "file"))

  test_files <- if (has_tests) {
    as.character(fs::dir_ls(fs::path(project_path, "tests"), glob = "*.[Rr]", recurse = TRUE, type = "file"))
  } else {
    character()
  }

  app_files <- as.character(fs::dir_ls(project_path, glob = "app.R|ui.R|server.R", recurse = TRUE, type = "file"))
  has_shiny <- length(app_files) > 0 || fs::dir_exists(fs::path(project_path, "inst", "app"))

  quarto_files <- as.character(fs::dir_ls(project_path, glob = "*.qmd", recurse = TRUE, type = "file"))
  has_quarto <- length(quarto_files) > 0 || fs::file_exists(fs::path(project_path, "_quarto.yml"))

  list(
    is_package = is_package,
    has_description = has_description,
    has_renv = has_renv,
    has_git = has_git,
    has_tests = has_tests,
    has_shiny = has_shiny,
    has_quarto = has_quarto,
    r_files = data.frame(path = r_files, stringsAsFactors = FALSE),
    test_files = data.frame(path = test_files, stringsAsFactors = FALSE),
    app_files = data.frame(path = app_files, stringsAsFactors = FALSE),
    project_path = as.character(project_path)
  )
}
