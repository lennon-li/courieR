library(shiny)
library(bslib)
library(packport)

source("ui.R")
source("server.R")

# Source all modules
module_files <- list.files("modules", pattern = "\\.R$", full.names = TRUE)
for (f in module_files) {
  source(f)
}

shinyApp(ui = ui, server = server)