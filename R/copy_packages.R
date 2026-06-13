#' Copy packages by file system
#'
#' Copies package directories from their source `libpath` into a target library
#' directory. Packages with no usable source path are skipped; missing source
#' directories are reported as errors.
#'
#' @param plan data.table with columns `package`, `libpath`, `compiled`.
#' @param target_lib Character. Path to the target library root.
#' @param log_callback Function or NULL. Called with a single string per event.
#' @return data.table with columns `package`, `status` (`"success"`,
#'   `"skipped"`, or `"error"`), and `message`.
#' @keywords internal
copy_packages <- function(plan, target_lib, log_callback = NULL) {
  emit <- function(...) {
    if (is.function(log_callback)) {
      try(log_callback(paste(..., collapse = "")), silent = TRUE)
    }
    invisible(NULL)
  }

  plan <- data.table::as.data.table(plan)
  if (nrow(plan) == 0) {
    return(data.table::data.table(
      package = character(),
      status = character(),
      message = character()
    ))
  }

  n <- nrow(plan)
  results <- lapply(seq_len(n), function(i) {
    pkg <- plan$package[[i]]
    src <- plan$libpath[[i]]

    if (is.na(src) || !nzchar(src)) {
      emit(sprintf("[skip] %s - no source path available", pkg))
      return(list(package = pkg, status = "skipped", message = "no source libpath"))
    }

    if (!dir.exists(src)) {
      emit(sprintf("[error] %s - source directory not found: %s", pkg, src))
      return(list(package = pkg, status = "error", message = sprintf("source not found: %s", src)))
    }

    dst <- file.path(target_lib, pkg)
    tryCatch({
      # Announce BEFORE the copy: a single dir_copy can take minutes on
      # synced/network drives, and live progress UIs key off this line.
      emit(sprintf("[%d/%d] %s - copying ...", i, n, pkg))
      t0 <- Sys.time()
      fs::dir_copy(src, dst, overwrite = TRUE)
      emit(sprintf("[ok] %s - copied (%.1fs)", pkg,
                   as.numeric(difftime(Sys.time(), t0, units = "secs"))))
      list(package = pkg, status = "success", message = "copied")
    }, error = function(e) {
      emit(sprintf("[error] %s - %s", pkg, conditionMessage(e)))
      list(package = pkg, status = "error", message = conditionMessage(e))
    })
  })

  data.table::rbindlist(results)
}
