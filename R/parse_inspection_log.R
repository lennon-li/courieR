#' Parse R CMD check log
#'
#' @param log_path Path to the log file
#' @return data.table
#' @examples
#' tmp <- tempfile(fileext = ".log")
#' writeLines(c(
#'   "* checking examples ... WARNING",
#'   "  An example result is marked with \\donttest."
#' ), tmp)
#' parse_inspection_log(tmp)
#' file.remove(tmp)
#' @export
parse_inspection_log <- function(log_path) {
  empty_dt <- data.table::data.table(
    severity = character(),
    message  = character(),
    file     = character(),
    line     = character(),
    raw_block = character()
  )

  if (!fs::file_exists(log_path)) {
    return(empty_dt)
  }

  lines <- readLines(log_path, warn = FALSE)
  if (length(lines) == 0L || all(nchar(trimws(lines)) == 0L)) {
    return(empty_dt)
  }

  check_lines <- grep("^\\* checking", lines)
  if (length(check_lines) == 0L) {
    return(empty_dt)
  }

  issue_idx <- check_lines[grepl("\\b(ERROR|WARNING|NOTE)\\b\\s*$",
                                  lines[check_lines])]
  if (length(issue_idx) == 0L) {
    return(empty_dt)
  }

  results <- lapply(seq_along(issue_idx), function(i) {
    start <- issue_idx[i]
    end   <- if (i < length(issue_idx)) issue_idx[i + 1L] - 1L else length(lines)

    block_lines <- lines[start:end]
    severity <- regmatches(lines[start],
                           regexpr("ERROR|WARNING|NOTE", lines[start]))

    detail <- if (end > start) block_lines[-1L] else character(0L)
    while (length(detail) > 0L && nchar(trimws(detail[length(detail)])) == 0L) {
      detail <- detail[-length(detail)]
    }
    msg   <- paste(detail, collapse = "\n")

    fl_match <- regmatches(
      msg,
      regexpr("[A-Za-z0-9._-]+\\.[A-Za-z0-9]+:(\\d+)", msg)
    )

    if (length(fl_match) > 0L && nchar(fl_match) > 0L) {
      parts <- strsplit(fl_match, ":")[[1L]]
      file  <- parts[1L]
      line  <- parts[2L]
    } else {
      file <- ""
      line <- ""
    }

    list(
      severity  = severity,
      message   = msg,
      file      = file,
      line      = line,
      raw_block = paste(block_lines, collapse = "\n")
    )
  })

  data.table::rbindlist(results)
}
