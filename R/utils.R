# Internal utility functions for courieR

#' Create a standardized status list
#'
#' @param status Character: "success", "error", etc.
#' @param message Character describing the outcome
#' @param ... Additional fields
#' @return A named list
#' @noRd
receipt <- function(status, message = NULL, ...) {
  c(list(status = status, message = message), list(...))
}

#' Get path to courier depot directory
#'
#' @param project_path Path to the R project
#' @return Path object
#' @noRd
depot_path <- function(project_path) {
  fs::path(project_path, ".courier-depot")
}