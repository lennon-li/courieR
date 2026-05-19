#' List packages installed in a library, optionally via a different R executable
#'
#' @param rscript_path Path to the Rscript executable. Defaults to current session.
#' @param lib_path Library path to query. Defaults to default `.libPaths()` of the target R.
#' @param format Return format
#' @param timeout_sec Timeout for subprocess
#' @return data.table
#' @examples
#' \donttest{
#'   pkgs <- manifest()
#'   head(pkgs)
#' }
#' @export
manifest <- function(rscript_path = NULL, lib_path = NULL, format = c("data.table", "data.frame"), timeout_sec = 30L) {
  format <- match.arg(format)

  if (is.null(rscript_path)) {
    rscript_path <- file.path(R.home("bin"), "Rscript")
    if (.Platform$OS.type == "windows") {
      rscript_path <- paste0(rscript_path, ".exe")
    }
  }

  if (!fs::file_exists(rscript_path)) {
    cli::cli_abort("Rscript not found at {.path {rscript_path}}", class = "courieR_rscript_not_found")
  }

  script_file <- tempfile(pattern = "courieR_manifest_", fileext = ".R")
  on.exit(if (fs::file_exists(script_file)) fs::file_delete(script_file), add = TRUE)

  lib_arg <- if (is.null(lib_path)) "NULL" else deparse(lib_path)

  script_content <- paste0('
suppressPackageStartupMessages({
  pkgs <- as.data.frame(
    installed.packages(lib.loc = ', lib_arg, ',
                       fields = c("Package","Version","Priority","Repository","RemoteType")),
    stringsAsFactors = FALSE
  )
  if (nrow(pkgs) == 0) {
    cat("__COURIERS_MANIFEST_START__\n[]\n__COURIERS_MANIFEST_END__\n")
    q("no", status = 0)
  }
  pkgs$source <- ifelse(!is.na(pkgs$Repository) & grepl("CRAN", pkgs$Repository), "CRAN",
    ifelse(!is.na(pkgs$RemoteType) & pkgs$RemoteType == "github", "GitHub",
    ifelse(!is.na(pkgs$RemoteType) & pkgs$RemoteType == "bioc", "Bioconductor", "unknown")))

  names(pkgs) <- tolower(names(pkgs))

  keep_cols <- intersect(c("package", "version", "priority", "repository", "remotetype", "libpath", "source"), names(pkgs))
  pkgs <- pkgs[, keep_cols, drop = FALSE]

  cat("__COURIERS_MANIFEST_START__\n")
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    cat(jsonlite::toJSON(pkgs, auto_unbox = TRUE, na = "null"))
  } else {
    cat("CSV_START\n")
    write.csv(pkgs, row.names = FALSE, na = "", eol = "\n")
    cat("CSV_END\n")
  }
  cat("\n__COURIERS_MANIFEST_END__\n")
})
')

  writeLines(script_content, script_file)

  res <- tryCatch(
    processx::run(
      command = rscript_path,
      args = c("--vanilla", script_file),
      timeout = timeout_sec,
      error_on_status = FALSE,
      windows_verbatim_args = FALSE
    ),
    error = function(e) e
  )

  if (inherits(res, "error")) {
    cli::cli_abort("Failed to execute subprocess", parent = res, class = "courieR_subprocess_error")
  }

  if (res$timeout) {
    cli::cli_warn("Subprocess timed out")
    out <- data.table::data.table()
    attr(out, "timed_out") <- TRUE
    if (format == "data.frame") out <- as.data.frame(out)
    return(out)
  }

  if (res$status != 0) {
    cli::cli_warn(res$stderr)
    cli::cli_abort("Subprocess exited with status {res$status}", class = "courieR_subprocess_error")
  }

  raw_stdout <- res$stdout

  inner <- sub(
    "(?s).*__COURIERS_MANIFEST_START__\r?\n(.*?)\r?\n__COURIERS_MANIFEST_END__.*",
    "\\1", raw_stdout, perl = TRUE
  )
  if (identical(inner, raw_stdout)) {
    cli::cli_abort(
      "Manifest subprocess output did not contain expected sentinels. stderr: {res$stderr}",
      class = "courieR_subprocess_error"
    )
  }
  out_text <- trimws(inner)

  parsed <- NULL
  if (grepl("^CSV_START", out_text)) {
    csv_str <- sub("(?s).*?CSV_START\r?\n(.*?)\r?\nCSV_END.*", "\\1", out_text, perl = TRUE)
    csv_str <- gsub("\r\n", "\n", csv_str, fixed = TRUE)
    csv_str <- gsub("\r", "\n", csv_str, fixed = TRUE)
    parsed <- read.csv(text = csv_str, stringsAsFactors = FALSE)
  } else {
    parsed <- tryCatch(
      jsonlite::fromJSON(out_text),
      error = function(e) e
    )
    if (inherits(parsed, "error")) {
      cli::cli_abort("Failed to parse JSON output", parent = parsed, class = "courieR_json_parse_error")
    }
  }

  if (is.null(parsed) || (is.data.frame(parsed) && nrow(parsed) == 0) || length(parsed) == 0) {
    parsed <- data.frame(
      package = character(), version = character(), priority = character(),
      repository = character(), remotetype = character(),
      lib.loc = character(), source = character()
    )
  }

  dt <- data.table::as.data.table(parsed)
  if (format == "data.frame") {
    dt <- as.data.frame(dt)
  }

  return(dt)
}
