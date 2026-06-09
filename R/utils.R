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

#' Eligible ship targets for a given source installation
#'
#' Given a [find_routes()] frame and a source `rscript_path`, return the subset
#' of rows that are valid *targets* to ship into. An installation is excluded
#' when it:
#' \itemize{
#'   \item is the source itself;
#'   \item resolves to the same `library` as the source (same package store, so
#'     shipping there would change nothing) — this is the case two installs of
#'     the same minor version usually fall into;
#'   \item runs an older R than the source (an older R cannot reliably hold
#'     packages built for / requiring a newer R).
#' }
#' Unknown versions stay eligible (online installs adapt to the target);
#' unknown libraries fall back to the version rule alone.
#'
#' @param routes A data frame from [find_routes()] (needs `rscript_path`,
#'   `version`, and optionally `library`).
#' @param src_path Character scalar: the source installation's `rscript_path`.
#' @return The eligible subset of `routes`, in the same column order.
#' @noRd
eligible_targets <- function(routes, src_path) {
  if (is.null(routes) || nrow(routes) == 0 ||
      is.null(src_path) || !nzchar(src_path)) {
    return(routes[0, , drop = FALSE])
  }
  has_lib  <- "library" %in% names(routes)
  src_idx  <- match(src_path, routes$rscript_path)
  src_v    <- if (!is.na(src_idx)) {
    tryCatch(package_version(as.character(routes$version[[src_idx]])), error = function(e) NULL)
  } else NULL
  src_lib  <- if (has_lib && !is.na(src_idx)) routes$library[[src_idx]] else NA_character_

  keep <- vapply(seq_len(nrow(routes)), function(i) {
    if (identical(routes$rscript_path[[i]], src_path)) return(FALSE)
    tlib <- if (has_lib) routes$library[[i]] else NA_character_
    if (!is.na(src_lib) && !is.na(tlib) && identical(src_lib, tlib)) return(FALSE)
    tv <- tryCatch(package_version(as.character(routes$version[[i]])), error = function(e) NULL)
    if (is.null(src_v) || is.null(tv)) return(TRUE)
    tv >= src_v
  }, logical(1))
  routes[keep, , drop = FALSE]
}