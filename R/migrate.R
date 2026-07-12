#' Migrate packages between two R installations in one call
#'
#' Convenience wrapper around [find_routes()] and [ship()]. Matches
#' installations by version string (e.g. `"4.5.2"`) or full Rscript path, then
#' runs the migration. Use [ship()] directly if you need fine-grained control.
#'
#' @param from Version string or Rscript path of the source installation
#'   (packages are copied *from* here).
#' @param to Version string or Rscript path of the target installation
#'   (packages are installed *into* here).
#' @param dry_run If `TRUE`, return the plan without installing anything.
#'   Default `FALSE`.
#' @param upgrade If `TRUE`, packages already in the target but at an older
#'   version are upgraded as well. Default `TRUE`.
#' @param mode Transfer mode passed to [ship()]: `"online"` (default - 
#'   reinstall via pak), `"offline"` (file-copy only, skip packages without a
#'   valid source path), or `"preserve"` (copy for exact version, fall back to a
#'   pinned pak spec on failure).
#' @param ... Additional arguments passed to [ship()].
#' @return The same named list returned by [ship()]: `plan`, `results`,
#'   `comparison`, `dry_run`, `elapsed_sec`.
#' @examples
#' \dontrun{
#'   # dry run first
#'   migrate("4.5.2", "4.6.0", dry_run = TRUE)
#'
#'   # for real
#'   result <- migrate("4.5.2", "4.6.0")
#'   table(result$results$status)
#' }
#' @export
migrate <- function(from, to, dry_run = FALSE, upgrade = TRUE, mode = "online", ...) {
  routes <- find_routes()

  if (nrow(routes) == 0) {
    cli::cli_abort("No R installations detected. Check {.fn find_routes}.")
  }

  resolve <- function(x, label) {
    if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
      cli::cli_abort("{label} must be a non-empty, non-NA character string (a version like {.val 4.5.2} or an Rscript path), not {.val {x}}.")
    }
    hit <- routes[
      routes$version == x |
      startsWith(routes$version, paste0(x, ".")) |
      routes$rscript_path == x,
    ]
    if (nrow(hit) == 0) {
      available <- paste(routes$version, collapse = ", ")
      cli::cli_abort(c(
        "No R installation matched {.val {x}} for {label}.",
        "i" = "Detected versions: {available}",
        "i" = "Pass a full Rscript path if the version string is ambiguous."
      ))
    }
    if (nrow(hit) > 1) {
      versions <- paste(hit$version, collapse = ", ")
      cli::cli_abort(c(
        "{.val {x}} matches multiple R installations for {label}: {versions}.",
        "i" = "Pass the full version string or Rscript path to disambiguate."
      ))
    }
    hit$rscript_path[[1]]
  }

  src_path <- resolve(from, "from")
  tgt_path <- resolve(to,   "to")

  if (identical(src_path, tgt_path)) {
    cli::cli_abort("{.arg from} and {.arg to} resolve to the same installation.")
  }

  ship(
    source_path = src_path,
    target_path = tgt_path,
    dry_run     = dry_run,
    upgrade     = upgrade,
    mode        = mode,
    ...
  )
}
