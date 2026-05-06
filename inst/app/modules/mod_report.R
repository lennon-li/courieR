mod_report_ui <- function(id) {
  ns <- NS(id)
  tagList(
    bslib::card(
      bslib::card_header("Generate Migration Report"),
      shiny::radioButtons(ns("format"), "Format", choices = c("HTML", "Markdown")),
      shiny::checkboxGroupInput(ns("sections"), "Include Sections", 
                                choices = c("Environment", "Diagnostics", "Results"),
                                selected = c("Environment", "Diagnostics", "Results")),
      shiny::downloadButton(ns("download"), "Download Report", class = "btn-success")
    )
  )
}

mod_report_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    project_path <- reactiveVal(getShinyOption("packport_project_path", default = "."))
    
    output$download <- downloadHandler(
      filename = function() {
        ext <- if (input$format == "HTML") "html" else "md"
        paste0("migration_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".", ext)
      },
      content = function(file) {
        template <- system.file("report_template.Rmd", package = "packport")
        if (template == "") {
          # Create a dummy template if package not installed
          template <- tempfile(fileext = ".Rmd")
          writeLines(c("---", "title: 'Migration Report'", "---", "# Report"), template)
        }
        
        # Determine output format
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