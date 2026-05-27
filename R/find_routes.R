#' Detect R installations on the system
#'
#' Scans the current machine for every R installation it can find, across
#' multiple sources per platform, and returns a tidy data frame of results.
#'
#' @param search_paths An optional character vector of additional paths to
#'   search. Each element may be a directory containing `bin/Rscript` (or
#'   `bin/x64/Rscript.exe` on Windows), or a direct path to an `Rscript`
#'   executable.
#'
#' @return A data frame with one row per unique R installation and the
#'   following columns:
#'   \describe{
#'     \item{version}{Character. R version string, e.g. `"4.4.1"`.}
#'     \item{rscript_path}{Character. Absolute path to the `Rscript` executable.}
#'     \item{is_current}{Logical. `TRUE` for the R session running courieR.}
#'     \item{source}{Character. Detection source label (e.g. `"registry-hklm"`,
#'       `"registry-hkcu"`, `"programfiles"`, `"appdata"`, `"documents"`,
#'       `"homebrew"`, `"rig"`, `"search_paths"`).}
#'   }
#'
#' @details
#' Detection sources by platform:
#'
#' **Windows**
#' \itemize{
#'   \item HKLM registry (`SOFTWARE\R-core\R`) — standard admin installs via
#'     the CRAN Windows installer.
#'   \item HKCU registry (`SOFTWARE\R-core\R`) — non-admin installs that
#'     register under the current user hive only.
#'   \item `%ProgramFiles%\R` — directory scan for admin installs not in the
#'     registry.
#'   \item `%LOCALAPPDATA%\Programs\R` — rig-managed and other user-local
#'     installs.
#'   \item `%USERPROFILE%\Documents\R` — installs placed in the user's
#'     Documents folder.
#'   \item rig (`rig list`) — any additional versions managed by rig that
#'     were not found by path scanning.
#' }
#'
#' **macOS**
#' \itemize{
#'   \item `/Library/Frameworks/R.framework/Versions` — system-wide CRAN
#'     installer.
#'   \item `~/Library/Frameworks/R.framework/Versions` — user-local framework
#'     installs (no admin required).
#'   \item Homebrew: `/opt/homebrew/opt/r` (Apple Silicon) and
#'     `/usr/local/opt/r` (Intel).
#'   \item rig (`rig list`) — rig-managed versions.
#' }
#'
#' **Linux**
#' \itemize{
#'   \item `/opt/R` — rig system-wide installs.
#'   \item `~/.local/share/rig/R` — rig user-local installs.
#'   \item conda environments (active `$CONDA_PREFIX`).
#'   \item System `Rscript` on `$PATH`.
#' }
#'
#' Symlinks are resolved via `fs::path_real()` so that duplicate entries from
#' different detection sources pointing to the same executable are collapsed.
#'
#' @examples
#' \donttest{
#' routes <- find_routes()
#' routes[, c("version", "rscript_path", "is_current")]
#'
#' # include a non-standard install
#' routes <- find_routes(search_paths = "/opt/custom-r/bin/Rscript")
#' }
#' @export
find_routes <- function(search_paths = NULL) {
  candidates <- character()
  windows_rscript_paths <- function(paths) {
    paths <- as.character(paths)
    x64 <- fs::path(paths, "bin", "x64", "Rscript.exe")
    root <- fs::path(paths, "bin", "Rscript.exe")

    # Prefer x64 on Windows. Some root-level launchers mis-handle `-e` quoting.
    unique(c(as.character(x64), as.character(root)))
  }
  windows_document_r_roots <- function() {
    profile <- Sys.getenv("USERPROFILE")
    if (!nzchar(profile)) return(character(0))
    root <- fs::path(profile, "Documents", "R")
    if (fs::dir_exists(root)) root else character(0)
  }

  os <- .Platform$OS.type
  if (os == "windows") {
    extract_registry_paths <- function(keys) {
      paths <- character()
      if (is.null(keys)) return(paths)
      if (is.character(keys$InstallPath)) paths <- c(paths, keys$InstallPath)
      for (k in names(keys)) {
        if (is.list(keys[[k]]) && is.character(keys[[k]]$InstallPath)) {
          paths <- c(paths, keys[[k]]$InstallPath)
        }
      }
      paths
    }

    r_keys <- tryCatch(
      utils::readRegistry("SOFTWARE\\R-core\\R", hive = "HLM", maxdepth = 2),
      error = function(e) NULL
    )
    candidates <- c(candidates, windows_rscript_paths(extract_registry_paths(r_keys)))

    # Non-admin installs register under HKCU, not HKLM
    r_keys_user <- tryCatch(
      utils::readRegistry("SOFTWARE\\R-core\\R", hive = "HCU", maxdepth = 2),
      error = function(e) NULL
    )
    candidates <- c(candidates, windows_rscript_paths(extract_registry_paths(r_keys_user)))

    pf <- Sys.getenv("ProgramFiles")
    if (nzchar(pf)) {
      dirs <- fs::dir_ls(fs::path(pf, "R"), type = "directory", fail = FALSE)
      candidates <- c(candidates, windows_rscript_paths(dirs))
    }

    # User-local installs (no admin rights) default to ~/AppData/Local/Programs/R
    # or ~/Documents/R — check both
    local_prog <- fs::path(Sys.getenv("LOCALAPPDATA"), "Programs", "R")
    if (nzchar(Sys.getenv("LOCALAPPDATA")) && fs::dir_exists(local_prog)) {
      dirs <- fs::dir_ls(local_prog, type = "directory", fail = FALSE)
      candidates <- c(candidates, windows_rscript_paths(dirs))
    }

    docs_roots <- windows_document_r_roots()
    if (length(docs_roots) > 0) {
      docs_dirs <- unlist(lapply(docs_roots, function(root) {
        fs::dir_ls(root, type = "directory", fail = FALSE)
      }), use.names = FALSE)
      candidates <- c(candidates, windows_rscript_paths(docs_dirs))
    }
  } else if (Sys.info()["sysname"] == "Darwin") {
    dirs <- fs::dir_ls("/Library/Frameworks/R.framework/Versions", type = "directory", fail = FALSE)
    candidates <- c(candidates, fs::path(dirs, "Resources", "bin", "Rscript"))

    # User-local framework install (no admin required)
    user_fw <- fs::path(path.expand("~"), "Library", "Frameworks", "R.framework", "Versions")
    if (fs::dir_exists(user_fw)) {
      user_dirs <- fs::dir_ls(user_fw, type = "directory", fail = FALSE)
      candidates <- c(candidates, fs::path(user_dirs, "Resources", "bin", "Rscript"))
    }

    # Homebrew: Apple Silicon (/opt/homebrew) and Intel (/usr/local)
    for (brew_prefix in c("/opt/homebrew", "/usr/local")) {
      candidates <- c(candidates, fs::path(brew_prefix, "opt", "r", "bin", "Rscript"))
    }
  } else {
    dirs <- fs::dir_ls("/opt/R", type = "directory", fail = FALSE)
    candidates <- c(candidates, fs::path(dirs, "bin", "Rscript"))
    candidates <- c(candidates, "/usr/lib/R/bin/Rscript")

    # User-local rig installs (~/.local/share/rig/R/)
    user_rig <- fs::path(path.expand("~"), ".local", "share", "rig", "R")
    if (fs::dir_exists(user_rig)) {
      rig_dirs <- fs::dir_ls(user_rig, type = "directory", fail = FALSE)
      candidates <- c(candidates, fs::path(rig_dirs, "bin", "Rscript"))
    }

    # Common conda/mamba prefixes
    for (conda_prefix in c("miniconda3", "anaconda3", "mambaforge", "miniforge3")) {
      candidates <- c(candidates, fs::path(path.expand("~"), conda_prefix, "bin", "Rscript"))
    }
  }

  # Supplement with any rig-managed versions not already caught by directory scans
  if (rig_available()) {
    rig_versions <- tryCatch({
      res <- processx::run("rig", "list", error_on_status = FALSE, timeout = 5)
      if (res$status == 0) {
        lines <- trimws(strsplit(res$stdout, "\n")[[1]])
        lines <- sub("^\\*\\s*", "", lines)  # strip leading star (marks current version)
        trimws(grep("^[0-9]+\\.[0-9]+", lines, value = TRUE))
      } else character(0)
    }, error = function(e) character(0))

    for (ver in rig_versions) {
      if (os == "windows") {
        candidates <- c(candidates, windows_rscript_paths(
          fs::path(Sys.getenv("LOCALAPPDATA"), "Programs", "R", paste0("R-", ver))
        ))
      } else if (Sys.info()["sysname"] == "Darwin") {
        candidates <- c(candidates,
          fs::path("/Library/Frameworks/R.framework/Versions", ver, "Resources", "bin", "Rscript")
        )
      } else {
        candidates <- c(candidates,
          fs::path("/opt/R", ver, "bin", "Rscript"),
          fs::path(path.expand("~"), ".local", "share", "rig", "R", ver, "bin", "Rscript")
        )
      }
    }
  }

  if (!is.null(search_paths)) {
    if (os == "windows") {
      candidates <- c(candidates, windows_rscript_paths(search_paths))
    } else {
      candidates <- c(candidates, fs::path(search_paths, "bin", "Rscript"))
    }
  }

  candidates <- unique(as.character(candidates))
  candidates <- candidates[fs::file_exists(candidates)]

  res_list <- lapply(candidates, function(rscript) {
    script <- 'cat(R.version$major, "||SEP||", R.version$minor, "||SEP||", paste(.libPaths(), collapse = "||LIB||"), sep = "")'
    out <- tryCatch(
      processx::run(rscript, c("--vanilla", "-e", script), timeout = 5, error_on_status = FALSE),
      error = function(e) NULL
    )

    if (is.null(out) || out$status != 0 || out$timeout) return(NULL)

    parts <- strsplit(trimws(out$stdout), "\\|\\|SEP\\|\\|")[[1]]
    if (length(parts) < 3) return(NULL)

    list(
      version = paste(trimws(parts[1]), trimws(parts[2]), sep = "."),
      major = trimws(parts[1]),
      minor = trimws(parts[2]),
      rscript_path = rscript,
      lib_paths = list(strsplit(trimws(parts[3]), "\\|\\|LIB\\|\\|")[[1]]),
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
