#' Ship packages between R installations
#'
#' @param source_path Rscript path of the source installation
#' @param target_path Rscript path of the target installation
#' @param packages Optional character vector of packages to ship. If NULL, ships all non-base missing/outdated packages.
#' @param dry_run Logical. If TRUE, return plan without installing.
#' @param upgrade Logical. Passed to pak
#' @param ... Extra arguments
#' @return A list with shipment results
#' @section Safety:
#' `ship()` installs packages into the target R library via [pak::pkg_install()]
#' running in a subprocess. Set `dry_run = TRUE` to preview the migration plan
#' without installing anything. When `dry_run = FALSE` (the default), pak runs
#' under the target R executable so packages are installed for the destination R
#' version. The source R need not have pak installed. All subprocess calls are
#' confined to the target library path; no files are written outside the target
#' library or the R temporary directory.
#' @examples
#' \donttest{
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
    # Reconstruct GitHub refs from RemoteUsername/RemoteRepo captured by manifest()
    u_col <- intersect(c("remoteusername.x", "remoteusername"), names(plan))[1]
    r_col <- intersect(c("remoterepo.x",    "remoterepo"),    names(plan))[1]
    github_refs <- if (!is.na(u_col) && !is.na(r_col)) {
      u <- plan[[u_col]]; r <- plan[[r_col]]
      ifelse(!is.na(u) & nzchar(u) & !is.na(r) & nzchar(r), paste0(u, "/", r), NA_character_)
    } else {
      rep(NA_character_, nrow(plan))
    }

    plan$pak_spec <- mapply(
      wrap,
      package     = plan$package,
      version     = plan$version.x,
      source_hint = plan$source,
      github_ref  = github_refs,
      SIMPLIFY    = TRUE
    )
  } else {
    plan$pak_spec <- character()
  }

  results <- data.table::data.table(package = character(), status = character(), message = character())

  if (dry_run || nrow(plan) == 0) {
    res <- list(
      comparison = comp$comparison,
      plan = plan,
      results = results,
      dry_run = dry_run,
      elapsed_sec = as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    )
    return(res)
  }

  tgt_lib_script <- "cat(.libPaths()[1])"
  tgt_lib_res <- processx::run(target_path, c("--vanilla", "-e", tgt_lib_script), error_on_status = FALSE)
  tgt_lib <- trimws(tgt_lib_res$stdout)
  if (tgt_lib_res$status != 0 || !nzchar(tgt_lib)) {
    cli::cli_abort(
      "Could not determine target library path (exit {tgt_lib_res$status}). stderr: {tgt_lib_res$stderr}",
      class = "courieR_subprocess_error"
    )
  }

  specs <- plan$pak_spec

  pak_res <- tryCatch({
    install_args_file <- tempfile(pattern = "courieR_ship_args_", fileext = ".rds")
    install_script_file <- tempfile(pattern = "courieR_ship_install_", fileext = ".R")
    on.exit({
      if (fs::file_exists(install_args_file)) fs::file_delete(install_args_file)
      if (fs::file_exists(install_script_file)) fs::file_delete(install_script_file)
    }, add = TRUE)

    saveRDS(
      list(specs = specs, lib = tgt_lib, upgrade = upgrade),
      install_args_file
    )
    writeLines(c(
      "args <- commandArgs(trailingOnly = TRUE)",
      "install_args <- readRDS(args[[1]])",
      "if (!requireNamespace('pak', quietly = TRUE)) {",
      "  stop('Package pak is not installed in the target R installation.', call. = FALSE)",
      "}",
      "pak::pkg_install(",
      "  install_args$specs,",
      "  lib = install_args$lib,",
      "  ask = FALSE,",
      "  upgrade = install_args$upgrade",
      ")"
    ), install_script_file)

    res <- processx::run(
      target_path,
      c("--vanilla", install_script_file, install_args_file),
      error_on_status = FALSE
    )
    if (res$status == 0) {
      list(status = "success", error = NULL)
    } else {
      msg <- trimws(paste(res$stderr, res$stdout, sep = "\n"))
      if (!nzchar(msg)) {
        msg <- sprintf("Target pak subprocess exited with status %s", res$status)
      }
      list(status = "error", error = structure(list(message = msg), class = c("simpleError", "error", "condition")))
    }
  }, error = function(e) list(status = "error", error = e))

  tgt_pkgs_after <- manifest(rscript_path = target_path, format = "data.table")

  if (nrow(plan) > 0) {
    results_list <- lapply(seq_len(nrow(plan)), function(i) {
      pkg       <- plan$package[i]
      action    <- plan$action[i]
      after_pkg <- tgt_pkgs_after[tgt_pkgs_after$package == pkg, ]

      if (action == "install") {
        if (nrow(after_pkg) > 0) {
          list(package = pkg, status = "success", message = "Installed")
        } else {
          msg <- if (pak_res$status == "error") conditionMessage(pak_res$error) else "Not found after install"
          list(package = pkg, status = "error", message = msg)
        }
      } else {
        # upgrade: the package was already present; success only if version actually changed
        old_ver   <- plan$version.y[i]
        after_ver <- if (nrow(after_pkg) > 0) after_pkg$version[1] else NA_character_
        if (!is.na(after_ver) && (is.na(old_ver) || after_ver != old_ver)) {
          list(package = pkg, status = "success", message = "Upgraded")
        } else {
          msg <- if (pak_res$status == "error") {
            conditionMessage(pak_res$error)
          } else if (!is.na(after_ver)) {
            sprintf("Version unchanged (%s)", after_ver)
          } else {
            "Package missing after upgrade attempt"
          }
          list(package = pkg, status = "error", message = msg)
        }
      }
    })
    results <- data.table::rbindlist(results_list)
  }

  res <- list(
    comparison = comp$comparison,
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
