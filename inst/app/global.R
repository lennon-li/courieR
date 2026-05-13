library(shiny)
library(bslib)
library(courieR)

module_files <- list.files("modules", pattern = "\\.R$", full.names = TRUE)
for (f in module_files) {
  source(f)
}

route_priority <- function(path) {
  if (grepl("Program Files", path, ignore.case = TRUE)) return(1L)
  if (grepl("AppData", path, ignore.case = TRUE)) return(2L)
  if (grepl("Documents", path, ignore.case = TRUE)) return(3L)
  4L
}

sort_routes <- function(routes) {
  if (is.null(routes) || nrow(routes) == 0) return(routes)
  routes$version_rank <- package_version(routes$version)
  routes$path_rank <- vapply(routes$rscript_path, route_priority, integer(1))
  routes <- routes[order(routes$version_rank, routes$path_rank, decreasing = c(TRUE, FALSE)), ]
  routes$version_rank <- NULL
  routes$path_rank <- NULL
  rownames(routes) <- NULL
  routes
}
