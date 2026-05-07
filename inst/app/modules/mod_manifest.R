mod_manifest_ui <- function(id) {
  ns <- NS(id)
  tagList(
    bslib::card(
      bslib::card_header("Generate Delivery Manifest"),
      shiny::radioButtons(ns("format"), "Format", choices = c("HTML", "Markdown")),
      shiny::checkboxGroupInput(ns("sections"), "Include Sections",
                                choices = c("Origin", "Dispatch", "Receipt"),
                                selected = c("Origin", "Dispatch", "Receipt")),
      shiny::downloadButton(ns("download"), "Download Manifest", class = "btn-success")
    )
  )
}

mod_manifest_server <- function(id, project_path) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    output$download <- downloadHandler(
      filename = function() {
        ext <- if (input$format == "HTML") "html" else "md"
        paste0("delivery_manifest_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".", ext)
      },
      content = function(file) {
        template <- system.file("report_template.Rmd", package = "courieR")
        if (template == "") {
          template <- tempfile(fileext = ".Rmd")
          writeLines(c("---", "title: 'Delivery Manifest'", "---", "# Manifest"), template)
        }

        out_fmt <- if (input$format == "HTML") rmarkdown::html_document() else rmarkdown::md_document()

        rmarkdown::render(
          template,
          output_format = out_fmt,
          output_file = file,
          params = list(
            project_path = project_path(),
            sections = input$sections
          ),
          envir = new.env(parent = globalenv()),
          quiet = TRUE
        )
      }
    )
  })
}
