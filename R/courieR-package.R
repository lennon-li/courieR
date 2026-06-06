#' @keywords internal
#' @importFrom utils read.csv write.csv
"_PACKAGE"

.onAttach <- function(libname, pkgname) {
  ver <- utils::packageVersion("courieR")
  packageStartupMessage(
    "courieR ", ver, "\n",
    "  Launch the dashboard : hub()\n",
    "  CLI reference        : ?ship"
  )
}

# The following block is used by usethis to automatically manage
# roxygen namespace tags. Modify with care!
## usethis namespace: start
## usethis namespace: end
NULL
