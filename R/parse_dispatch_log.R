#' Parse test log
#'
#' @param log_path Path to the log file
#' @return data.table
#' @examples
#' tmp <- tempfile(fileext = ".log")
#' writeLines(c(
#'   "-- Failure (test-foo.R:1): addition works ----",
#'   "Expected 3, got 4."
#' ), tmp)
#' parse_dispatch_log(tmp)
#' file.remove(tmp)
#' @export
parse_dispatch_log <- function(log_path) {
  empty_dt <- data.table::data.table(
    file    = character(),
    test    = character(),
    status  = character(),
    message = character()
  )

  if (!fs::file_exists(log_path)) {
    return(empty_dt)
  }

  lines <- readLines(log_path, warn = FALSE)
  # A CRLF log can leave a trailing "\r" on each line (platform-dependent);
  # left as-is, the header regex's "----$" anchor would never match and the
  # log would silently parse as having zero results.
  lines <- sub("\r$", "", lines)
  if (length(lines) == 0L || all(nchar(trimws(lines)) == 0L)) {
    return(empty_dt)
  }

  header_pattern <- paste0(
    "^--\\s+(Failure|Success|Skip)\\s+\\(([^)]+)\\):\\s*(.+?)\\s*----$"
  )

  header_idx <- grep(header_pattern, lines)
  if (length(header_idx) == 0L) {
    return(empty_dt)
  }

  results <- lapply(seq_along(header_idx), function(i) {
    hline  <- lines[header_idx[i]]
    status <- sub("^--\\s+(\\w+).*", "\\1", hline)
    file   <- sub(":\\d+$", "",
                     sub("^--\\s+\\w+\\s+\\(([^)]+)\\).*", "\\1", hline))
    test   <- sub("^--\\s+\\w+\\s+\\([^)]+\\):\\s*(.+?)\\s*----$", "\\1", hline)

    status <- tolower(status)

    msg_start <- header_idx[i] + 1L
    msg_end   <- if (i < length(header_idx)) header_idx[i + 1L] - 1L else length(lines)

    if (msg_start <= msg_end) {
      msg_lines <- lines[msg_start:msg_end]
      msg_lines <- msg_lines[nchar(trimws(msg_lines)) > 0L]
      msg <- paste(msg_lines, collapse = "\n")
    } else {
      msg <- ""
    }

    list(file = file, test = test, status = status, message = msg)
  })

  data.table::rbindlist(results)
}
