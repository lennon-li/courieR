#' Check if rig is available
#' @return Logical
#' @examples
#' rig_available()
#' @export
rig_available <- function() {
  nzchar(Sys.which("rig"))
}

#' List rig installations
#' @return data.frame
#' @examples
#' \donttest{
#'   if (rig_available()) rig_list()
#' }
#' @export
rig_list <- function() {
  if (!rig_available()) return(data.frame())
  res <- tryCatch(
    processx::run("rig", "list", error_on_status = FALSE),
    error = function(e) list(status = 1)
  )
  if (res$status != 0) return(data.frame())
  
  lines <- strsplit(res$stdout, "\n")[[1]]
  versions <- grep("^[0-9]+\\.[0-9]+", lines, value = TRUE)
  data.frame(version = trimws(versions), stringsAsFactors = FALSE)
}

#' Install R via rig
#' @param version R version
#' @param wait Logical
#' @return The result of [processx::run()].
#' @examples
#' if (interactive() && rig_available()) {
#'   rig_install("4.5.0", wait = FALSE)
#' }
#' @export
rig_install <- function(version, wait = TRUE) {
  if (!rig_available()) stop("rig not available")
  processx::run("rig", c("install", version), timeout = if(wait) 600 else 0)
}
