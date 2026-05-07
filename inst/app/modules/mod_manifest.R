mod_manifest_ui <- function(id) {
  ns <- NS(id)
  tagList(
    bslib::card(
      bslib::card_header("Generate Delivery Manifest"),
      shiny::radioButtons(ns("format"), "Format", choices = c("HTML", "Markdown")),
      shiny::checkboxGroupInput(ns("sections"), "Include Sections",
                                choices = c("Origin", "Receipt"),
                                selected = c("Origin", "Receipt")),
      shiny::downloadButton(ns("download"), "Download Manifest", class = "btn-success")
    )
  )
}

mod_manifest_server <- function(id, from_r_path, to_r_path, migration_log) {
  moduleServer(id, function(input, output, session) {

    output$download <- downloadHandler(
      filename = function() {
        ext <- if (input$format == "HTML") "html" else "md"
        paste0("delivery_manifest_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".", ext)
      },
      content = function(file) {
        if (!requireNamespace("rmarkdown", quietly = TRUE)) {
          writeLines(
            "rmarkdown is not installed. Run install.packages('rmarkdown') to enable manifest downloads.",
            file
          )
          return()
        }
        template <- system.file("report_template.Rmd", package = "courieR")
        if (template == "") {
          template <- tempfile(fileext = ".Rmd")
          writeLines(c("---", "title: 'Delivery Manifest'", "---", "# Manifest"), template)
        }
        out_fmt <- if (input$format == "HTML") rmarkdown::html_document() else rmarkdown::md_document()
        rmarkdown::render(
          template,
          output_format = out_fmt,
          output_file   = file,
          params = list(
            from_r_path   = from_r_path(),
            to_r_path     = to_r_path(),
            migration_log = migration_log(),
            sections      = input$sections
          ),
          envir = new.env(parent = globalenv()),
          quiet = TRUE
        )
      }
    )
  })
}
