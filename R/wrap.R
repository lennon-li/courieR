#' Generate a pak specification for a package
#'
#' @param package Package name
#' @param version Optional version constraint or exact version
#' @param source_hint Optional hint: "CRAN", "Bioconductor", "GitHub", "local"
#' @param github_ref Optional GitHub ref like "owner/repo@ref"
#' @return A character vector of pak specs
#' @examples
#' wrap("dplyr")
#' wrap("dplyr", version = "1.1.4")
#' wrap("mypackage", source_hint = "Bioconductor")
#' wrap("r-lib/rlang", source_hint = "GitHub", github_ref = "r-lib/rlang")
#' @export
wrap <- function(package, version = NULL, source_hint = NULL, github_ref = NULL) {
  if (!is.null(source_hint) && source_hint == "local" && !is.null(version) && file.exists(version)) {
    return(paste0("local::", version))
  }

  if (!is.null(source_hint) && source_hint == "Bioconductor") {
    return(paste0("bioc::", package))
  }

  if (!is.null(source_hint) && source_hint == "GitHub" && !is.null(github_ref)) {
    return(github_ref)
  }

  if (is.null(version)) {
    return(package)
  }

  if (grepl("^[0-9]+(\\.[0-9]+)*[A-Za-z0-9-]*$", version)) {
    return(paste0(package, "@", version))
  }

  return(package)
}
