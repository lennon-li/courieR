# Helper: build ship batches from per-package action assignments.
# Returns a list of batch specs: list(pkgs, src, tgt, mode).
#
# actions   named character vector: package -> "skip" | "ship" | "online"
# comp      data.frame/data.table with columns: package, status
# direction one of "A_to_B", "B_to_A", "full"
# from_path Rscript path for installation A
# to_path   Rscript path for installation B
.build_depot_ship_batches <- function(actions, comp, direction, from_path, to_path) {
  non_skip <- names(actions)[actions != "skip"]
  if (length(non_skip) == 0L) return(list())

  status_map <- stats::setNames(
    comp[["status"]][match(non_skip, comp[["package"]])],
    non_skip
  )

  if (direction == "full") {
    a_to_b <- non_skip[status_map[non_skip] %in% c("missing-from-B", "newer-in-A")]
    b_to_a <- non_skip[status_map[non_skip] %in% c("missing-from-A", "newer-in-B")]
  } else if (direction == "A_to_B") {
    a_to_b <- non_skip
    b_to_a <- character(0)
  } else {
    a_to_b <- character(0)
    b_to_a <- non_skip
  }

  batches <- list()

  add_batch <- function(pkgs, src, tgt, mode) {
    if (length(pkgs) == 0L) return()
    batches[[length(batches) + 1L]] <<- list(pkgs = pkgs, src = src,
                                              tgt = tgt, mode = mode)
  }

  add_batch(a_to_b[actions[a_to_b] == "online"], from_path, to_path, "online")
  add_batch(a_to_b[actions[a_to_b] == "ship"],   from_path, to_path, "offline")
  add_batch(b_to_a[actions[b_to_a] == "online"], to_path, from_path, "online")
  add_batch(b_to_a[actions[b_to_a] == "ship"],   to_path, from_path, "offline")

  batches
}
