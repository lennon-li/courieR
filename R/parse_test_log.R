#' Parse test log
#'
#' @param log_path Path to the log file
#' @return data.table
#' @export
parse_test_log <- function(log_path) {
  if (!fs::file_exists(log_path)) {
    return(data.table::data.table(file=character(), test=character(), status=character(), message=character()))
  }
  
  res <- data.table::data.table(
    file = character(),
    test = character(),
    status = character(),
    message = character()
  )
  return(res)
}