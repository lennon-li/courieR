library(shiny)
library(bslib)
library(courieR)

module_files <- list.files("modules", pattern = "\\.R$", full.names = TRUE)
for (f in module_files) {
  source(f)
}
