#' Parse R CMD check log
#'
#' @param log_path Path to the log file
#' @return data.table
#' @export
parse_check_log <- function(log_path) {
  if (!fs::file_exists(log_path)) {
    return(data.table::data.table(severity=character(), message=character(), file=character(), line=character(), raw_block=character()))
  }
  
  res <- data.table::data.table(
    severity = character(),
    message = character(),
    file = character(),
    line = character(),
    raw_block = character()
  )
  return(res)
}