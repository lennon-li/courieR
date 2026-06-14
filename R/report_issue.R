#' Report a bug or error to the courieR issue tracker
#'
#' Opens a pre-filled GitHub issue form in your browser with your R version,
#' platform, and (optionally) an error message already populated. Use this
#' when you encounter a problem outside of the dashboard, or when you want to
#' file a feature request.
#'
#' @param message Character. A short description of the problem. If `NULL`,
#'   a generic template is used.
#' @param context Character. Additional context about where the error occurred
#'   (e.g. `"ship() with mode = 'offline'"`). Optional.
#'
#' @return Called for its side effect (opens browser). Returns the issue URL
#'   invisibly.
#' @export
#'
#' @examples
#' if (interactive()) {
#'   report_issue("ship() fails with 'library not found'")
#' }
report_issue <- function(message = NULL, context = NULL) {
  msg <- message %||% "<!-- Describe the problem here -->"
  url <- .build_issue_url(msg, context)
  utils::browseURL(url)
  invisible(url)
}

.build_issue_url <- function(message, context = NULL) {
  pkg_ver  <- tryCatch(as.character(utils::packageVersion("courieR")), error = function(e) "unknown")
  r_ver    <- paste0(R.version$major, ".", R.version$minor)
  os_info  <- paste(Sys.info()[["sysname"]], Sys.info()[["release"]])
  platform <- R.version$platform
  n_routes <- tryCatch({
    r <- find_routes()
    sprintf("%d installation(s) detected", nrow(r))
  }, error = function(e) "detection not run")

  context_line <- if (!is.null(context) && nzchar(context))
    paste0("**Context:** ", context, "\n\n")
  else ""

  body <- paste0(
    "## Error report\n\n",
    context_line,
    "**Error:**\n```\n", message, "\n```\n\n",
    "## Environment\n\n",
    "| Field | Value |\n",
    "|-------|-------|\n",
    "| courieR | `", pkg_ver, "` |\n",
    "| R | `", r_ver, "` |\n",
    "| Platform | `", platform, "` |\n",
    "| OS | `", os_info, "` |\n",
    "| Routes | ", n_routes, " |\n\n",
    "## Steps to reproduce\n\n",
    "<!-- Describe what you were doing when the error occurred -->\n\n",
    "1. \n2. \n3. \n"
  )

  title <- paste0("App error: ", strtrim(message, 70))
  paste0(
    "https://github.com/lennon-li/courieR/issues/new",
    "?labels=bug",
    "&title=", utils::URLencode(title, reserved = TRUE),
    "&body=",  utils::URLencode(body,  reserved = TRUE)
  )
}
