#' Classify shipment risk based on check and test results
#'
#' @param baseline_results data.table from baseline check
#' @param post_results data.table from post-shipment check
#' @return A list
#' @examples
#' baseline <- data.table::data.table(
#'   severity = character(), message = character(),
#'   file = character(), line = character()
#' )
#' post <- data.table::data.table(
#'   severity = "ERROR", message = "undefined symbol",
#'   file = "R/foo.R", line = "10"
#' )
#' rate_shipment(baseline, post)
#' @export
rate_shipment <- function(baseline_results, post_results) {
  if (is.null(baseline_results) || is.null(post_results)) {
    return(list(
      risk        = "unknown",
      new_errors  = 0L,
      new_warnings = 0L,
      new_notes   = 0L,
      reason      = "missing results"
    ))
  }

  mkkey <- function(dt) {
    paste(dt[["severity"]], dt[["file"]], dt[["line"]],
          substr(dt[["message"]], 1L, 120L), sep = "|")
  }

  base_keys <- mkkey(baseline_results)
  post_keys <- mkkey(post_results)

  new_mask <- !post_keys %in% base_keys

  if (!any(new_mask)) {
    return(list(
      risk         = "none",
      new_errors   = 0L,
      new_warnings = 0L,
      new_notes    = 0L,
      reason       = "no new issues"
    ))
  }

  new_sev  <- post_results[["severity"]][new_mask]
  n_errors <- sum(new_sev == "ERROR")
  n_warns  <- sum(new_sev == "WARNING")
  n_notes  <- sum(new_sev == "NOTE")

  if (n_errors > 0L) {
    risk   <- "high"
    reason <- sprintf("%d new error(s), %d new warning(s)", n_errors, n_warns)
  } else if (n_warns > 0L) {
    risk   <- "medium"
    reason <- sprintf("%d new warning(s), %d new note(s)", n_warns, n_notes)
  } else {
    risk   <- "low"
    reason <- sprintf("%d new note(s)", n_notes)
  }

  list(
    risk         = risk,
    new_errors   = n_errors,
    new_warnings = n_warns,
    new_notes    = n_notes,
    reason       = reason
  )
}
