#' Scan project dependencies
#'
#' @param project_path Path to the project
#' @return A data.table
#' @examples
#' \donttest{
#'   take_inventory(tempdir())
#' }
#' @export
take_inventory <- function(project_path) {
  project_path <- fs::path_real(project_path)

  deps <- data.table::data.table(
    package = character(),
    source = character(),
    constraint = character(),
    lockfile_version = character()
  )

  desc_path <- fs::path(project_path, "DESCRIPTION")
  if (fs::file_exists(desc_path)) {
    tryCatch({
      d <- desc::desc(desc_path)
      desc_deps <- d$get_deps()
      if (nrow(desc_deps) > 0) {
        desc_dt <- data.table::as.data.table(desc_deps)
        desc_dt <- desc_dt[desc_dt$type %in% c("Imports", "Depends", "Suggests", "LinkingTo"), ]
        if (nrow(desc_dt) > 0) {
          desc_res <- data.table::data.table(
            package = desc_dt$package,
            source = desc_dt$type,
            constraint = desc_dt$version,
            lockfile_version = NA_character_
          )
          deps <- rbind(deps, desc_res, fill = TRUE)
        }
      }
    }, error = function(e) {
      cli::cli_warn("Could not parse {.file {desc_path}}: {e$message}")
      NULL
    })
  }

  renv_path <- fs::path(project_path, "renv.lock")
  if (fs::file_exists(renv_path)) {
    tryCatch({
      renv_data <- jsonlite::read_json(renv_path)
      if (!is.null(renv_data$Packages)) {
        renv_pkgs <- names(renv_data$Packages)
        renv_vers <- vapply(renv_data$Packages, function(x) {
          if (!is.null(x$Version)) as.character(x$Version) else NA_character_
        }, character(1))

        renv_dt <- data.table::data.table(
          package = renv_pkgs,
          source = "renv.lock",
          constraint = "*",
          lockfile_version = renv_vers
        )

        if (nrow(deps) > 0) {
          for (i in seq_len(nrow(renv_dt))) {
            pkg <- renv_dt$package[i]
            ver <- renv_dt$lockfile_version[i]
            if (pkg %in% deps$package) {
              deps$lockfile_version[deps$package == pkg] <- ver
            } else {
              deps <- rbind(deps, renv_dt[i, ], fill = TRUE)
            }
          }
        } else {
          deps <- renv_dt
        }
      }
    }, error = function(e) {
      cli::cli_warn("Could not parse {.file {renv_path}}: {e$message}")
      NULL
    })
  }

  if (nrow(deps) == 0) {
    return(data.table::data.table(
      package = character(), source = character(), constraint = character(),
      installed_version = character(), lockfile_version = character(),
      target_version = character(), status = character()
    ))
  }

  deps <- deps[deps$package != "R", ]

  installed <- as.data.frame(utils::installed.packages(), stringsAsFactors = FALSE)

  deps$installed_version <- NA_character_
  idx <- match(deps$package, installed$Package)
  deps$installed_version[!is.na(idx)] <- installed$Version[idx[!is.na(idx)]]

  deps$target_version <- NA_character_
  deps$status <- "unknown"

  return(deps)
}
