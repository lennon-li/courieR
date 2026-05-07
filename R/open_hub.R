#' Launch the courieR delivery hub dashboard
#'
#' @param project_path Optional path to pre-fill in the app
#' @param port Optional port to run the app on
#' @param launch.browser Logical. Whether to open the browser
#' @examples
#' \dontrun{
#'   open_hub()
#' }
#' @export
open_hub <- function(project_path = NULL, port = NULL, launch.browser = TRUE) {
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
