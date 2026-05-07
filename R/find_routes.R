#' Detect R installations on the system
#'
#' @param search_paths Optional extra paths to search
#' @return A data.frame of R installations
#' @export
find_routes <- function(search_paths = NULL) {
  candidates <- character()

  os <- .Platform$OS.type
  if (os == "windows") {
    r_keys <- tryCatch(
      utils::readRegistry("SOFTWARE\\R-core\\R", hive = "HLM", maxdepth = 2),
      error = function(e) NULL
    )
    if (!is.null(r_keys)) {
      paths <- character()
      if (is.character(r_keys$InstallPath)) paths <- c(paths, r_keys$InstallPath)
      for (k in names(r_keys)) {
        if (is.list(r_keys[[k]]) && is.character(r_keys[[k]]$InstallPath)) {
          paths <- c(paths, r_keys[[k]]$InstallPath)
        }
      }
      candidates <- c(candidates, file.path(paths, "bin", "Rscript.exe"), file.path(paths, "bin", "x64", "Rscript.exe"))
    }

    pf <- Sys.getenv("ProgramFiles")
    if (nzchar(pf)) {
      dirs <- fs::dir_ls(fs::path(pf, "R"), type = "directory", fail = FALSE)
      candidates <- c(candidates, fs::path(dirs, "bin", "Rscript.exe"), fs::path(dirs, "bin", "x64", "Rscript.exe"))
    }
  } else if (Sys.info()["sysname"] == "Darwin") {
    dirs <- fs::dir_ls("/Library/Frameworks/R.framework/Versions", type = "directory", fail = FALSE)
    candidates <- c(candidates, fs::path(dirs, "Resources", "bin", "Rscript"))
  } else {
    dirs <- fs::dir_ls("/opt/R", type = "directory", fail = FALSE)
    candidates <- c(candidates, fs::path(dirs, "bin", "Rscript"))
    candidates <- c(candidates, "/usr/lib/R/bin/Rscript")
  }

  if (!is.null(search_paths)) {
    if (os == "windows") {
      candidates <- c(candidates, fs::path(search_paths, "bin", "Rscript.exe"), fs::path(search_paths, "bin", "x64", "Rscript.exe"))
    } else {
      candidates <- c(candidates, fs::path(search_paths, "bin", "Rscript"))
    }
  }

  candidates <- unique(as.character(candidates))
  candidates <- candidates[fs::file_exists(candidates)]

  res_list <- lapply(candidates, function(rscript) {
    script <- 'cat(paste(R.version$major, R.version$minor, paste(.libPaths(), collapse=";"), sep="|"))'
    out <- tryCatch(
      processx::run(rscript, c("--vanilla", "-e", script), timeout = 5, error_on_status = FALSE),
      error = function(e) NULL
    )

    if (is.null(out) || out$status != 0 || out$timeout) return(NULL)

    parts <- strsplit(trimws(out$stdout), "\\|")[[1]]
    if (length(parts) < 3) return(NULL)

    list(
      version = paste(parts[1], parts[2], sep = "."),
      major = parts[1],
      minor = parts[2],
      rscript_path = rscript,
      lib_paths = list(strsplit(parts[3], ";")[[1]]),
      is_current = FALSE
    )
  })

  res_list <- res_list[!sapply(res_list, is.null)]

  if (length(res_list) == 0) {
    return(data.frame(
      version = character(), major = character(), minor = character(),
      rscript_path = character(), is_current = logical()
    ))
  }

  dt <- data.table::rbindlist(res_list)

  dt$rscript_path <- as.character(fs::path_real(dt$rscript_path))
  dt <- unique(dt, by = "rscript_path")

  current_rscript <- file.path(R.home("bin"), "Rscript")
  if (os == "windows") {
    current_rscript <- paste0(current_rscript, ".exe")
  }
  if (fs::file_exists(current_rscript)) {
    current_rscript <- as.character(fs::path_real(current_rscript))
  }
  dt$is_current <- (dt$rscript_path == current_rscript)

  return(as.data.frame(dt))
}
