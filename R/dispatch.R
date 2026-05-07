#' Run an R command in the background and log output
#'
#' @param project_path Path to the project
#' @param expr Expression to run (as a quoted expression or function)
#' @param phase Character: "baseline" or "post_migration"
#' @param label Character: "document", "test", or "check"
#' @param rscript_path Optional path to Rscript
#' @param timeout_sec Timeout in seconds
#' @return A list with process info
#' @export
dispatch <- function(project_path, expr, phase, label, rscript_path = NULL, timeout_sec = 600L) {
  start_time <- Sys.time()

  base_dir <- open_depot(project_path)
  log_dir <- fs::path(base_dir, "logs", phase)
  fs::dir_create(log_dir)

  stdout_path <- fs::path(log_dir, paste0(label, "_stdout.txt"))
  stderr_path <- fs::path(log_dir, paste0(label, "_stderr.txt"))

  proc <- callr::r_bg(
    func = function(e, p) {
      setwd(p)
      eval(parse(text = e))
    },
    args = list(e = expr, p = as.character(fs::path_real(project_path))),
    stdout = stdout_path,
    stderr = stderr_path
  )

  list(
    phase = phase,
    label = label,
    status = "running",
    exit_code = NA_integer_,
    stdout_path = as.character(stdout_path),
    stderr_path = as.character(stderr_path),
    start_time = start_time,
    end_time = NA,
    duration_sec = NA_real_,
    process = proc
  )
}
