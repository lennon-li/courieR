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
  if (nrow(source_pkgs) == 0) {
    empty_dt <- data.table::data.table(package = character(), version.x = character(), version.y = character(), source = character())
    return(list(
      missing = empty_dt,
      outdated = empty_dt,
      newer = empty_dt,
      same = empty_dt,
      summary = data.frame(missing = 0, outdated = 0, newer = 0, same = 0, total_source = 0)
    ))
  }

  # Exclude base/recommended packages from source as they are part of R
  src <- source_pkgs[is.na(source_pkgs$priority) | !(source_pkgs$priority %in% c("base", "recommended")), ]

  if (nrow(src) == 0) {
    empty_dt <- data.table::data.table(package = character(), version.x = character(), version.y = character(), source = character())
    return(list(
      missing = empty_dt,
      outdated = empty_dt,
      newer = empty_dt,
      same = empty_dt,
      summary = data.frame(missing = 0, outdated = 0, newer = 0, same = 0, total_source = 0)
    ))
  }

  # Merge
  dt <- data.table::merge.data.table(
    src, target_pkgs, by = "package", all.x = TRUE, suffixes = c(".x", ".y")
  )

  if ("source.x" %in% names(dt)) {
    data.table::setnames(dt, "source.x", "source")
    if ("source.y" %in% names(dt)) data.table::set(dt, j = "source.y", value = NULL)
  }

  missing_dt <- dt[is.na(dt$version.y), ]

  dt_both <- dt[!is.na(dt$version.y), ]

  if (nrow(dt_both) > 0) {
    vx <- numeric_version(dt_both$version.x)
    vy <- numeric_version(dt_both$version.y)

    outdated_dt <- dt_both[vx > vy, ]
    newer_dt <- dt_both[vy > vx, ]
    same_dt <- dt_both[vx == vy, ]
  } else {
    empty <- dt[0, ]
    outdated_dt <- empty
    newer_dt <- empty
    same_dt <- empty
  }

  res <- list(
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
