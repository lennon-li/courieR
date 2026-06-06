#' Resolve the primary target library for an R installation
#'
#' @param target_path Full path to target `Rscript`.
#' @return Character scalar path to `.libPaths()[1L]` in the target R.
#' @keywords internal
find_target_lib <- function(target_path) {
  res <- processx::run(
    target_path,
    c("--vanilla", "--no-save", "-e", "cat(.libPaths()[1L])"),
    error_on_status = FALSE
  )
  out <- trimws(res$stdout)
  if (res$status != 0 || !nzchar(out)) {
    cli::cli_abort(
      "Could not determine target library path (exit {res$status}). stderr: {res$stderr}",
      class = "courieR_subprocess_error"
    )
  }
  out
}

.find_r_major <- function(rscript_path) {
  res <- tryCatch(
    processx::run(
      rscript_path,
      c("--vanilla", "--no-save", "-e", "cat(R.version$major)"),
      error_on_status = FALSE,
      timeout = 5
    ),
    error = function(e) NULL
  )
  if (is.null(res) || res$status != 0) return(NA_character_)
  trimws(res$stdout)
}

.copy_plan <- function(plan) {
  plan <- data.table::as.data.table(plan)
  lib_col <- intersect(c("libpath", "libpath.x"), names(plan))[1]
  libpath <- if (!is.na(lib_col)) as.character(plan[[lib_col]]) else rep(NA_character_, nrow(plan))
  compiled <- !is.na(libpath) & nzchar(libpath) & file.exists(file.path(libpath, "libs"))
  data.table::data.table(
    package = plan$package,
    libpath = libpath,
    compiled = compiled
  )
}

.warn_cross_major_compiled <- function(copy_plan, source_path, target_path, log_callback = NULL) {
  if (!any(copy_plan$compiled, na.rm = TRUE)) return(invisible(NULL))
  source_major <- .find_r_major(source_path)
  target_major <- .find_r_major(target_path)
  if (!is.na(source_major) && !is.na(target_major) && !identical(source_major, target_major)) {
    msg <- sprintf(
      "Warning: copying compiled package(s) across R major versions (%s -> %s) may be unsafe: %s",
      source_major,
      target_major,
      paste(copy_plan$package[copy_plan$compiled], collapse = ", ")
    )
    if (is.function(log_callback)) try(log_callback(msg), silent = TRUE)
  }
  invisible(NULL)
}

.run_pak_plan <- function(plan, target_path, target_lib = NULL, upgrade = FALSE, log_callback = NULL) {
  emit_log <- function(...) {
    if (is.function(log_callback)) {
      try(log_callback(paste(..., collapse = "")), silent = TRUE)
    }
    invisible(NULL)
  }

  plan <- data.table::as.data.table(plan)
  if (nrow(plan) == 0) {
    return(data.table::data.table(package = character(), status = character(), message = character()))
  }
  if (is.null(target_lib)) {
    target_lib <- find_target_lib(target_path)
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
      list(specs = specs, lib = target_lib, upgrade = upgrade),
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

    emit_log("Running pak in the target R installation; first-time metadata loading may take 1-2 minutes.")
    res <- processx::run(
      target_path,
      c("--vanilla", install_script_file, install_args_file),
      error_on_status = FALSE,
      stdout_line_callback = function(line) emit_log(line),
      stderr_line_callback = function(line) emit_log(line)
    )
    if (res$status == 0) {
      emit_log("pak subprocess finished successfully.")
      list(status = "success", error = NULL)
    } else {
      msg <- trimws(paste(res$stderr, res$stdout, sep = "\n"))
      if (!nzchar(msg)) {
        msg <- sprintf("Target pak subprocess exited with status %s", res$status)
      }
      emit_log(sprintf("pak subprocess failed with status %s.", res$status))
      list(status = "error", error = structure(list(message = msg), class = c("simpleError", "error", "condition")))
    }
  }, error = function(e) list(status = "error", error = e))

  if (identical(pak_res$status, "success")) {
    out <- data.table::data.table(package = plan$package, status = "success", message = "pak completed")
  } else {
    out <- data.table::data.table(package = plan$package, status = "error", message = conditionMessage(pak_res$error))
    attr(out, "pak_error") <- pak_res$error
  }
  out
}

#' Ship packages between R installations
#'
#' Compares the package libraries of two R installations and transfers missing
#' or outdated packages into the target.
#'
#' @param source_path Full path to the `Rscript` executable of the source
#'   installation (the one you are copying packages *from*). Use
#'   [find_routes()] to discover available paths.
#' @param target_path Full path to the `Rscript` executable of the target
#'   installation (the one you are installing packages *into*). The target
#'   R must have `pak` installed for `mode = "online"` or pak fallbacks.
#' @param packages Character vector of package names to act on. If `NULL`
#'   (the default), all packages that are missing from or outdated in the
#'   target are included.
#' @param dry_run If `TRUE`, build and return the installation plan without
#'   installing anything. Use this to review what will happen before
#'   committing to a sync.
#' @param upgrade If `TRUE`, packages already present in the target but at an
#'   older version than the source are upgraded. If `FALSE` (the default),
#'   only packages missing from the target are installed.
#' @param log_callback Optional function of one argument. When provided, it is
#'   called with a single character string for each progress message emitted
#'   during package transfer.
#' @param mode Transfer mode: `"online"` reinstalls via pak (default),
#'   `"offline"` copies package directories by file and skips packages without
#'   a valid source path, and `"preserve"` copies first then falls back to a
#'   pinned pak spec for packages that could not be copied.
#' @param ... Reserved for future arguments.
#' @return A named list with the following elements:
#'   \describe{
#'     \item{`plan`}{`data.table` of planned actions with columns `package`,
#'       `action` (`"install"` or `"upgrade"`), `mode`, `version.x` (source
#'       version), `version.y` (target version, `NA` if the package is
#'       missing), and `pak_spec` (the spec passed to pak).}
#'     \item{`results`}{`data.table` of per-package outcomes with columns
#'       `package`, `status` (`"success"`, `"skipped"`, or `"error"`), and
#'       `message`.}
#'     \item{`comparison`}{The raw [inventory()] comparison table.}
#'     \item{`dry_run`}{`TRUE` if no packages were installed.}
#'     \item{`elapsed_sec`}{Total wall-clock time in seconds.}
#'   }
#' @section Safety:
#' `ship()` can install packages into the target R library via
#' [pak::pkg_install()] running in a subprocess, or copy package directories
#' directly for offline/preserve transfers. Set `dry_run = TRUE` to preview the
#' migration plan without installing or copying anything. The source R need not
#' have pak installed. Subprocess calls and file copies are confined to the
#' target library path and R temporary directory.
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
ship <- function(source_path, target_path, packages = NULL, dry_run = FALSE, upgrade = FALSE,
                 log_callback = NULL, mode = c("online", "offline", "preserve"), ...) {
  start_time <- Sys.time()
  valid_modes <- c("online", "offline", "preserve")
  if (length(mode) > 1L) mode <- mode[[1L]]
  if (length(mode) != 1L || !mode %in% valid_modes) {
    cli::cli_abort("`mode` must be one of {.val online}, {.val offline}, or {.val preserve}.", class = "courieR_invalid_mode")
  }

  if (!is.null(log_callback) && !is.function(log_callback)) {
    cli::cli_abort("`log_callback` must be a function or NULL", class = "courieR_invalid_log_callback")
  }

  if (!fs::file_exists(source_path)) cli::cli_abort("Source Rscript not found")
  if (!fs::file_exists(target_path)) cli::cli_abort("Target Rscript not found")

  src_pkgs <- manifest(rscript_path = source_path, format = "data.table")
  tgt_pkgs <- manifest(rscript_path = target_path, format = "data.table")

  comp <- inventory(src_pkgs, tgt_pkgs)

  missing_pkgs <- comp$missing
  outdated_pkgs <- comp$outdated

  if (nrow(missing_pkgs) > 0) missing_pkgs$action <- "install"
  if (nrow(outdated_pkgs) > 0) outdated_pkgs$action <- "upgrade"

  plan <- data.table::as.data.table(rbind(missing_pkgs, outdated_pkgs, fill = TRUE))

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
  data.table::set(plan, j = "mode", value = rep(mode, nrow(plan)))

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

  if (mode == "online") {
    target_lib <- find_target_lib(target_path)
    pak_results <- .run_pak_plan(plan, target_path, target_lib = target_lib, upgrade = upgrade, log_callback = log_callback)
    pak_error <- attr(pak_results, "pak_error")

    tgt_pkgs_after <- manifest(rscript_path = target_path, format = "data.table")

    results_list <- lapply(seq_len(nrow(plan)), function(i) {
      pkg <- plan$package[i]
      action <- plan$action[i]
      after_pkg <- tgt_pkgs_after[tgt_pkgs_after$package == pkg, ]
      pak_row <- pak_results[pak_results$package == pkg, ]
      pak_msg <- if (nrow(pak_row) > 0 && pak_row$status[[1]] == "error") pak_row$message[[1]] else NULL

      if (action == "install") {
        if (nrow(after_pkg) > 0) {
          list(package = pkg, status = "success", message = "Installed")
        } else {
          msg <- if (!is.null(pak_msg)) pak_msg else if (!is.null(pak_error)) conditionMessage(pak_error) else "Not found after install"
          list(package = pkg, status = "error", message = msg)
        }
      } else {
        old_ver <- plan$version.y[i]
        after_ver <- if (nrow(after_pkg) > 0) after_pkg$version[1] else NA_character_
        if (!is.na(after_ver) && (is.na(old_ver) || after_ver != old_ver)) {
          list(package = pkg, status = "success", message = "Upgraded")
        } else {
          msg <- if (!is.null(pak_msg)) {
            pak_msg
          } else if (!is.null(pak_error)) {
            conditionMessage(pak_error)
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
  } else if (mode == "offline") {
    target_lib <- find_target_lib(target_path)
    plan_copy <- .copy_plan(plan)
    .warn_cross_major_compiled(plan_copy, source_path, target_path, log_callback = log_callback)
    results <- copy_packages(plan_copy, target_lib, log_callback = log_callback)
  } else if (mode == "preserve") {
    target_lib <- find_target_lib(target_path)
    plan_copy <- .copy_plan(plan)
    .warn_cross_major_compiled(plan_copy, source_path, target_path, log_callback = log_callback)
    copy_res <- copy_packages(plan_copy, target_lib, log_callback = log_callback)
    fallback_pkgs <- copy_res[["package"]][copy_res[["status"]] != "success"]
    if (length(fallback_pkgs) > 0) {
      fallback <- data.table::copy(plan[plan$package %in% fallback_pkgs, ])
      pinned_versions <- if ("version.x" %in% names(fallback)) fallback$version.x else fallback$version
      data.table::set(
        fallback,
        j = "pak_spec",
        value = ifelse(
          !is.na(pinned_versions) & nzchar(pinned_versions),
          paste0(fallback$package, "@", pinned_versions),
          fallback$package
        )
      )
      pak_res <- .run_pak_plan(fallback, target_path, target_lib = target_lib, upgrade = upgrade, log_callback = log_callback)
      results <- data.table::rbindlist(list(copy_res[copy_res$status == "success", ], pak_res), fill = TRUE)
    } else {
      results <- copy_res
    }
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
