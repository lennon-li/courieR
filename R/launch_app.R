#' Launch the packport migration dashboard
#'
#' @param project_path Optional path to pre-fill in the app
#' @param port Optional port to run the app on
#' @param launch.browser Logical. Whether to open the browser
#' @export
launch_app <- function(project_path = NULL, port = NULL, launch.browser = TRUE) {
  app_dir <- system.file("app", package = "packport")
  if (app_dir == "") {
    cli::cli_abort("Could not find app directory. Try re-installing packport.")
  }
  
  if (!is.null(project_path)) {
    project_path <- fs::path_real(project_path)
  }
  
  shiny::shinyOptions(packport_project_path = project_path)
  shiny::runApp(app_dir, port = port, launch.browser = launch.browser)
}