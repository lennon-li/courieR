#' Ship packages between R installations
#'
#' @param source_path Rscript path of the source installation
#' @param target_path Rscript path of the target installation
#' @param packages Optional character vector of packages to ship. If NULL, ships all non-base missing/outdated packages.
#' @param dry_run Logical. If TRUE, return plan without installing.
#' @param upgrade Logical. Passed to pak
#' @param ... Extra arguments
#' @return A list with shipment results
#' @examples
#' \dontrun{
#'   routes <- find_routes()
#'   if (nrow(routes) >= 2) {
#'     result <- ship(
#'       source_path = routes$rscript_path[1],
#'       target_path = routes$rscript_path[2],
#'       dry_run = TRUE
#'     )
#'     print(result$plan)
#'   }
#' }
#' @export
ship <- function(source_path, target_path, packages = NULL, dry_run = FALSE, upgrade = FALSE, ...) {
  start_time <- Sys.time()

  if (!fs::file_exists(source_path)) cli::cli_abort("Source Rscript not found")
  if (!fs::file_exists(target_path)) cli::cli_abort("Target Rscript not found")

  src_pkgs <- manifest(rscript_path = source_path, format = "data.table")
  tgt_pkgs <- manifest(rscript_path = target_path, format = "data.table")

  comp <- inventory(src_pkgs, tgt_pkgs)

  missing_pkgs <- comp$missing
  outdated_pkgs <- comp$outdated

  if (nrow(missing_pkgs) > 0) missing_pkgs$action <- "install"
  if (nrow(outdated_pkgs) > 0) outdated_pkgs$action <- "upgrade"

  plan <- rbind(missing_pkgs, outdated_pkgs, fill = TRUE)

  if (!is.null(packages)) {
    plan <- plan[plan$package %in% packages, ]
  }

  if (nrow(plan) > 0) {
    plan$pak_spec <- mapply(
      wrap,
      package = plan$package,
      version = plan$version.x,
      source_hint = plan$source
    )
  } else {
    plan$pak_spec <- character()
  }

  results <- data.table::data.table(package = character(), status = character(), message = character())

  if (dry_run || nrow(plan) == 0) {
    res <- list(
      comparison = comp,
      plan = plan,
      results = results,
      dry_run = dry_run,
      elapsed_sec = as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    )
    return(res)
  }

  tgt_lib_script <- "cat(.libPaths()[1])"
  tgt_lib_res <- processx::run(target_path, c("--vanilla", "-e", tgt_lib_script))
  tgt_lib <- trimws(tgt_lib_res$stdout)

  specs <- plan$pak_spec

  pak_res <- tryCatch({
    callr::r(
      func = function(specs, lib, upgrade) {
        pak::pkg_install(specs, lib = lib, ask = FALSE, upgrade = upgrade)
        TRUE
      },
      args = list(specs = specs, lib = tgt_lib, upgrade = upgrade),
      show = FALSE
    )
    list(status = "success", error = NULL)
  }, error = function(e) list(status = "error", error = e))

  tgt_pkgs_after <- manifest(rscript_path = target_path, format = "data.table")

  if (nrow(plan) > 0) {
    results_list <- lapply(plan$package, function(pkg) {
      after_pkg <- tgt_pkgs_after[tgt_pkgs_after$package == pkg, ]
      if (nrow(after_pkg) > 0) {
        list(package = pkg, status = "success", message = "Installed")
      } else {
        msg <- if (pak_res$status == "error") pak_res$error$message else "Not found after install"
        list(package = pkg, status = "error", message = msg)
      }
    })
    results <- data.table::rbindlist(results_list)
  }

  res <- list(
    comparison = comp,
    plan = plan,
    results = results,
    dry_run = dry_run,
    elapsed_sec = as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  )

  if (any(results$status == "error")) {
    attr(res, "partial") <- TRUE
  }

  return(res)
}
