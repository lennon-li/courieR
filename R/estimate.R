# Ship-time estimation with per-machine calibration.
#
# Static per-package constants are wildly wrong across machines: a pure-R
# package copy is ~0.5s on a local SSD but 100-200s on a OneDrive-synced
# Windows library. So estimates start from conservative defaults and are
# calibrated from every completed ship, persisted across sessions in the
# user cache directory.

# Default seconds per package by route, plus fixed per-ship overhead
# (subprocess spawns, library verification). Deliberately conservative -
# calibration tightens them after the first real ship on a machine.
.ship_rate_defaults <- function() {
  list(copy = 15, binary = 30, source = 240, overhead = 45)
}

.ship_rates_path <- function() {
  dir <- tools::R_user_dir("courieR", which = "cache")
  file.path(dir, "ship-rates.rds")
}

#' Read calibrated per-package ship rates (seconds), falling back to defaults
#' @noRd
ship_rates <- function() {
  defaults <- .ship_rate_defaults()
  path <- .ship_rates_path()
  saved <- if (file.exists(path)) {
    tryCatch(readRDS(path), error = function(e) NULL)
  } else {
    NULL
  }
  if (is.list(saved)) {
    for (nm in intersect(names(saved), names(defaults))) {
      v <- saved[[nm]]
      if (is.numeric(v) && length(v) == 1L && is.finite(v) && v > 0) {
        defaults[[nm]] <- v
      }
    }
  }
  defaults
}

#' Record an observed per-package rate for a route ("copy", "binary", "source")
#'
#' Blends the observation into the stored rate (exponential moving average,
#' weight 0.6 on the new observation) and persists it.
#' @noRd
record_ship_rate <- function(route, secs_per_pkg) {
  if (!route %in% c("copy", "binary", "source", "overhead")) return(invisible(NULL))
  if (!is.numeric(secs_per_pkg) || length(secs_per_pkg) != 1L ||
      !is.finite(secs_per_pkg) || secs_per_pkg <= 0) {
    return(invisible(NULL))
  }
  rates <- ship_rates()
  rates[[route]] <- 0.4 * rates[[route]] + 0.6 * secs_per_pkg
  path <- .ship_rates_path()
  tryCatch({
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    saveRDS(rates, path)
  }, error = function(e) NULL)
  invisible(rates)
}

#' Estimate total ship time for a plan
#'
#' @param n_copy,n_binary,n_source Package counts by route.
#' @return list(low, high, text): a low/high range in seconds and a
#'   human-readable string such as "~2-6 min". The range reflects estimation
#'   uncertainty (x0.6 / x2 around the point estimate).
#' @noRd
estimate_ship_secs <- function(n_copy = 0L, n_binary = 0L, n_source = 0L) {
  r <- ship_rates()
  point <- r$overhead + n_copy * r$copy + n_binary * r$binary + n_source * r$source
  low  <- max(5, point * 0.6)
  high <- point * 2
  list(low = low, high = high, text = .fmt_secs_range(low, high))
}

.fmt_one <- function(secs) {
  if (secs < 90) return(sprintf("%ds", round(secs)))
  mins <- secs / 60
  if (mins < 90) return(sprintf("%d min", max(1, round(mins))))
  sprintf("%.1f h", mins / 60)
}

.fmt_secs_range <- function(low, high) {
  if (round(low) >= round(high)) return(paste0("~", .fmt_one(high)))
  # Collapse the unit when both ends share it ("~2-6 min", not "~2 min-6 min").
  lo <- .fmt_one(low)
  hi <- .fmt_one(high)
  lo_parts <- strsplit(lo, " ")[[1]]
  hi_parts <- strsplit(hi, " ")[[1]]
  if (length(lo_parts) == 2 && length(hi_parts) == 2 && lo_parts[2] == hi_parts[2]) {
    return(sprintf("~%s-%s %s", lo_parts[1], hi_parts[1], hi_parts[2]))
  }
  sprintf("~%s - %s", lo, hi)
}
