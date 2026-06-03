#' Launch the courieR delivery hub dashboard
#'
#' @param project_path Optional path to pre-fill in the app
#' @param port Optional port to run the app on
#' @param launch.browser Logical. Whether to open the browser
#' @return Called for its side effect of launching a Shiny application.
#' @examples
#' if (interactive()) {
#'   open_hub()
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
