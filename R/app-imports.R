# These packages are Imports because the Shiny dashboard under inst/app/ and
# the pak subprocess started by ship() need them at run time, but R CMD check
# only traces namespace use in R/. Referencing them here documents the
# dependency and silences the "All declared Imports should be used" NOTE.
.app_imports <- function() {
  list(
    bslib::card,
    bsicons::bs_icon,
    DT::datatable,
    shinyjs::useShinyjs,
    pak::pkg_install
  )
}
