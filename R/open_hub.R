#' Launch the courieR dashboard
#'
#' Opens the Shiny dashboard in your browser. The dashboard detects all R
#' installations on the machine and lets you compare and sync packages between
#' any two of them without writing any code.
#'
#' `hub()` is a short alias for `open_hub()`.
#'
#' @param project_path Reserved; currently unused.
#' @param port Port to run the Shiny app on. `NULL` picks a random available port.
#' @param launch.browser Whether to open the system browser automatically. Default `TRUE`.
#' @return Called for its side effect of launching a Shiny application.
#' @examples
#' if (interactive()) {
#'   hub()        # short form
#'   open_hub()   # same thing
#' }
#' @export
open_hub <- function(project_path = NULL, port = NULL, launch.browser = TRUE) {
  missing_pkgs <- Filter(
    function(p) !requireNamespace(p, quietly = TRUE),
    c("shiny", "bslib", "bsicons", "DT")
  )
  if (length(missing_pkgs) > 0) {
    cli::cli_abort(c(
      "The courieR dashboard requires additional packages that are not installed.",
      "i" = "Install them with: {.code install.packages(c({paste(shQuote(missing_pkgs), collapse = ', ')}))}",
      "i" = "The CLI workflow ({.fn find_routes}, {.fn manifest}, {.fn inventory}, {.fn ship}) works without these packages."
    ))
  }

  app_dir <- system.file("app", package = "courieR")
  if (app_dir == "") {
    cli::cli_abort("Could not find app directory. Try re-installing courieR.")
  }

  if (!is.null(project_path)) {
    project_path <- fs::path_real(project_path)
  }

  shiny::shinyOptions(courieR_project_path = project_path)
  shiny::runApp(app_dir, port = port, launch.browser = launch.browser)
}

#' @rdname open_hub
#' @export
hub <- function(project_path = NULL, port = NULL, launch.browser = TRUE) {
  open_hub(project_path = project_path, port = port, launch.browser = launch.browser)
}
