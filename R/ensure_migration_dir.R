#' Ensure the migration dashboard directory structure exists
#'
#' Creates `.migration-dashboard/` and its subdirectories in the project path.
#' Writes a `.gitignore` to prevent tracking of logs and artifacts.
#'
#' @param project_path Path to the R project
#' @return Invisibly returns the path to the `.migration-dashboard` directory.
#' @export
ensure_migration_dir <- function(project_path) {
  base_dir <- migration_dir_path(project_path)
  
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