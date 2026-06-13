#' List packages installed in a library
#'
#' Runs a subprocess under the given R executable and returns all
#' user-installed packages. Base and recommended packages are excluded
#' automatically.
#'
#' @param rscript_path Full path to an `Rscript` executable. Defaults to the
#'   current R session. Use [find_routes()] to get paths for other
#'   installations.
#' @param lib_path Library path to query within the target R. Defaults to the
#'   first element of `.libPaths()` in that R installation.
#' @param format `"data.table"` (default) or `"data.frame"`.
#' @param timeout_sec Maximum seconds to wait for the subprocess. Increase
#'   this on slow machines or network-mounted drives. Default `30`.
#' @return A `data.table` (or `data.frame`) with one row per user-installed
#'   package and columns: `package`, `version`, `source` (`"CRAN"`,
#'   `"GitHub"`, `"Bioconductor"`, or `"unknown"`), `remotetype`,
#'   `remoteusername`, `remoterepo`, `libpath`. Base and recommended packages
#'   are never included in the output.
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

  # Strip the *parent* R session's library/home env vars before launching the
  # target R (see child_r_env()). Otherwise the target R reports the parent's
  # library instead of its own - making every installation appear to share one
  # library. The target R still reads its own .Renviron/.Rprofile, so
  # user-configured paths survive.
  child_env <- child_r_env()

  # When lib_path is not explicit, fetch the target R's real .libPaths() using its
  # normal startup (reads .Rprofile/.Renviron), so user-configured paths are included.
  if (is.null(lib_path)) {
    lp_res <- tryCatch(
      processx::run(
        rscript_path,
        c("--no-save", "-e", "cat(paste(.libPaths(), collapse = '\n'))"),
        env = child_env,
        error_on_status = FALSE,
        timeout = 10
      ),
      error = function(e) NULL
    )
    if (!is.null(lp_res) && lp_res$status == 0 && nzchar(trimws(lp_res$stdout))) {
      lib_path <- trimws(strsplit(trimws(lp_res$stdout), "\n")[[1]])
    }
  }

  lib_arg <- if (is.null(lib_path)) "NULL" else paste(deparse(lib_path), collapse = "\n")

  script_content <- paste0('
suppressPackageStartupMessages({
  pkgs <- as.data.frame(
    installed.packages(lib.loc = ', lib_arg, ',
                       fields = c("Package","Version","Priority","Repository","RemoteType","RemoteUsername","RemoteRepo")),
    stringsAsFactors = FALSE
  )
  if (nrow(pkgs) == 0) {
    cat("__COURIERS_MANIFEST_START__\n[]\n__COURIERS_MANIFEST_END__\n")
    q("no", status = 0)
  }
  base_lib      <- tolower(normalizePath(.Library, winslash = "/", mustWork = FALSE))
  lib_norm      <- tolower(normalizePath(pkgs$LibPath, winslash = "/", mustWork = FALSE))
  base_pkg_list <- tryCatch(
    rownames(installed.packages(priority = c("base", "recommended"))),
    error = function(e) character(0)
  )
  is_base <- (!is.na(pkgs$Priority) & pkgs$Priority %in% c("base", "recommended")) |
             lib_norm == base_lib |
             pkgs$Package %in% base_pkg_list
  pkgs <- pkgs[!is_base, , drop = FALSE]
  if (nrow(pkgs) == 0) {
    cat("__COURIERS_MANIFEST_START__\n[]\n__COURIERS_MANIFEST_END__\n")
    q("no", status = 0)
  }
  pkgs$source <- ifelse(!is.na(pkgs$Repository) & grepl("CRAN", pkgs$Repository), "CRAN",
    ifelse(!is.na(pkgs$RemoteType) & pkgs$RemoteType == "github", "GitHub",
    ifelse(!is.na(pkgs$RemoteType) & pkgs$RemoteType == "bioc", "Bioconductor", "unknown")))

  names(pkgs) <- tolower(names(pkgs))

  keep_cols <- intersect(c("package", "version", "priority", "repository", "remotetype", "remoteusername", "remoterepo", "libpath", "source"), names(pkgs))
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
      args = c("--no-save", "--no-restore", "--no-site-file", "--no-init-file", script_file),
      env = child_env,
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
