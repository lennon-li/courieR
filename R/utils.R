# Internal utility functions for packport

#' Create a standardized status list
#'
#' @param status Character: "success", "error", etc.
#' @param message Character describing the outcome
#' @param ... Additional fields
#' @return A named list
#' @noRd
status_result <- function(status, message = NULL, ...) {
  c(list(status = status, message = message), list(...))
}

#' Get path to migration directory
#'
#' @param project_path Path to the R project
#' @return Path object
#' @noRd
migration_dir_path <- function(project_path) {
  fs::path(project_path, ".migration-dashboard")
}