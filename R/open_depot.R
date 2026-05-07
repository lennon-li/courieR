#' Ensure the courier depot directory structure exists
#'
#' Creates `.courier-depot/` and its subdirectories in the project path.
#' Writes a `.gitignore` to prevent tracking of logs and artifacts.
#'
#' @param project_path Path to the R project
#' @return Invisibly returns the path to the `.courier-depot` directory.
#' @examples
#' \donttest{
#'   depot <- open_depot(tempdir())
#' }
#' @export
open_depot <- function(project_path) {
  base_dir <- depot_path(project_path)

  subdirs <- c(
    fs::path(base_dir, "logs", "baseline"),
    fs::path(base_dir, "logs", "post_migration"),
    fs::path(base_dir, "reports"),
    fs::path(base_dir, "cache"),
    fs::path(base_dir, "artifacts")
  )

  fs::dir_create(subdirs, recurse = TRUE)

  gitignore_path <- fs::path(base_dir, ".gitignore")
  if (!fs::file_exists(gitignore_path)) {
    writeLines("*", gitignore_path)
  }

  invisible(base_dir)
}
