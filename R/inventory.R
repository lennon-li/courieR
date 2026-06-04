#' Compare two package libraries
#'
#' @param source_pkgs data.table from `manifest`
#' @param target_pkgs data.table from `manifest`
#' @return A list of data.tables and a summary data.frame
#' @examples
#' src <- data.table::data.table(
#'   package  = c("dplyr", "ggplot2"),
#'   version  = c("1.1.4", "3.5.1"),
#'   priority = NA_character_
#' )
#' tgt <- data.table::data.table(
#'   package = "dplyr",
#'   version = "1.0.0"
#' )
#' inventory(src, tgt)
#' @export
inventory <- function(source_pkgs, target_pkgs) {
  source_pkgs <- normalize_manifest_packages(source_pkgs)
  target_pkgs <- normalize_manifest_packages(target_pkgs)

  # Exclude base/recommended packages from source as they are part of R
  src <- source_pkgs[is.na(source_pkgs$priority) | !(source_pkgs$priority %in% c("base", "recommended")), ]

  if (nrow(src) == 0) {
    return(empty_inventory_result())
  }

  # Merge
  dt <- data.table::merge.data.table(
    src, target_pkgs, by = "package", all.x = TRUE, suffixes = c(".x", ".y")
  )

  if ("source.x" %in% names(dt)) {
    data.table::setnames(dt, "source.x", "source")
  }
  if ("source.y" %in% names(dt)) {
    data.table::setnames(dt, "source.y", "target_source")
  }

  status <- rep("missing", nrow(dt))
  has_target <- which(!is.na(dt$version.y))

  if (length(has_target) > 0) {
    vx_str <- dt$version.x[has_target]
    vy_str <- dt$version.y[has_target]
    valid_ver <- nzchar(vx_str) & nzchar(vy_str)

    vx <- package_version(ifelse(valid_ver, vx_str, "0.0.0"))
    vy <- package_version(ifelse(valid_ver, vy_str, "0.0.0"))

    target_status <- rep("same", length(has_target))
    target_status[vx > vy] <- "outdated"
    target_status[vy > vx] <- "newer"
    # For non-parseable versions: only force "outdated" when source has a version
    # and target doesn't. When both are empty (e.g. local dev package on both
    # sides), leave as "same" to avoid an infinite reinstall loop.
    src_has_ver <- nzchar(vx_str) & !valid_ver
    tgt_has_ver <- nzchar(vy_str) & !valid_ver
    target_status[src_has_ver & !tgt_has_ver] <- "outdated"
    target_status[tgt_has_ver & !src_has_ver] <- "newer"
    status[has_target] <- target_status
  }
  data.table::set(dt, j = "status", value = status)

  missing_dt <- dt[which(dt[["status"]] == "missing"), ]
  outdated_dt <- dt[which(dt[["status"]] == "outdated"), ]
  newer_dt <- dt[which(dt[["status"]] == "newer"), ]
  same_dt <- dt[which(dt[["status"]] == "same"), ]

  res <- list(
    comparison = dt,
    missing = missing_dt,
    outdated = outdated_dt,
    newer = newer_dt,
    same = same_dt,
    summary = data.frame(
      missing = nrow(missing_dt),
      outdated = nrow(outdated_dt),
      newer = nrow(newer_dt),
      same = nrow(same_dt),
      total_source = nrow(src)
    )
  )
  return(res)
}

normalize_manifest_packages <- function(pkgs) {
  dt <- data.table::as.data.table(pkgs)

  if (ncol(dt) == 0) {
    return(data.table::data.table(
      package = character(),
      version = character(),
      priority = character(),
      source = character()
    ))
  }

  if (!"package" %in% names(dt)) {
    data.table::set(dt, j = "package", value = rep("", nrow(dt)))
  }
  if (!"version" %in% names(dt)) {
    data.table::set(dt, j = "version", value = rep("", nrow(dt)))
  }
  if (!"priority" %in% names(dt)) {
    data.table::set(dt, j = "priority", value = rep(NA_character_, nrow(dt)))
  }
  if (!"source" %in% names(dt)) {
    data.table::set(dt, j = "source", value = rep(NA_character_, nrow(dt)))
  }

  data.table::set(dt, j = "package", value = as.character(dt[["package"]]))
  data.table::set(dt, j = "version", value = as.character(dt[["version"]]))
  data.table::set(dt, j = "priority", value = as.character(dt[["priority"]]))
  data.table::set(dt, j = "source", value = as.character(dt[["source"]]))

  dt[]
}

empty_inventory_result <- function() {
  empty_dt <- data.table::data.table(
    package = character(),
    version.x = character(),
    version.y = character(),
    source = character(),
    status = character()
  )

  list(
    comparison = empty_dt,
    missing = empty_dt,
    outdated = empty_dt,
    newer = empty_dt,
    same = empty_dt,
    summary = data.frame(missing = 0, outdated = 0, newer = 0, same = 0, total_source = 0)
  )
}
