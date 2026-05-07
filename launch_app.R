devtools::install(quick = TRUE, quiet = TRUE)
options(shiny.port = 3841)
shiny::runApp(
  system.file("app", package = "courieR"),
  launch.browser = TRUE
)
