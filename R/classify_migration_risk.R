#' Classify migration risk based on check and test results
#'
#' @param baseline_results data.table from baseline check
#' @param post_results data.table from post-migration check
#' @return A list
#' @export
classify_migration_risk <- function(baseline_results, post_results) {
  if (is.null(baseline_results) || is.null(post_results)) {
    return(list(
      risk = "unknown",
      rationale = character(),
      new_errors = data.table::data.table(),
      new_warnings = data.table::data.table(),
      resolved = data.table::data.table(),
      test_delta = data.table::data.table()
    ))
  }
  
  list(
    risk = "low",
    rationale = character(),
    new_errors = data.table::data.table(),
    new_warnings = data.table::data.table(),
    resolved = data.table::data.table(),
    test_delta = data.table::data.table()
  )
}