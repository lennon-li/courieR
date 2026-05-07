mod_cargo_select_ui <- function(id) {
  ns <- NS(id)
  tagList(
    bslib::card(
      bslib::card_header("Target Package"),
      shiny::selectizeInput(ns("package"), "Select Package", choices = NULL),
      shiny::textInput(ns("version"), "Target Version (optional)", placeholder = "e.g., 1.0.0"),
      shiny::radioButtons(ns("source"), "Source", choices = c("CRAN", "Bioconductor", "GitHub", "local")),
      shiny::conditionalPanel(
        condition = sprintf("input['%s'] == 'GitHub'", ns("source")),
        shiny::textInput(ns("github_ref"), "GitHub Ref (owner/repo@ref)")
      ),
      shiny::conditionalPanel(
        condition = sprintf("input['%s'] == 'local'", ns("source")),
        shiny::textInput(ns("local_path"), "Local Path")
      ),
      h4("Resolved pak spec:"),
      verbatimTextOutput(ns("pak_spec")),
      shiny::selectizeInput(ns("target_r"), "Target R Installation", choices = NULL),
      shiny::actionButton(ns("confirm"), "Confirm Target", class = "btn-primary")
    )
  )
}

mod_cargo_select_server <- function(id, project_path, target_r_path) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    deps <- reactiveVal(NULL)

    observe({
      p <- project_path()
      if (is.null(p)) p <- "."
      d <- courieR::take_inventory(p)
      deps(d)
      updateSelectizeInput(session, "package", choices = c("", d$package))
    })

    observe({
      routes <- courieR::find_routes()
      if (nrow(routes) > 0L) {
        choices <- stats::setNames(routes$rscript_path,
                                   paste(routes$version, "-", routes$rscript_path))
        updateSelectizeInput(session, "target_r", choices = choices)
      }
    })

    spec <- reactive({
      req(input$package)
      courieR::wrap(
        package = input$package,
        version = if (input$source == "local") input$local_path else if (nzchar(input$version)) input$version else NULL,
        source_hint = input$source,
        github_ref = input$github_ref
      )
    })

    output$pak_spec <- renderText({
      if (input$package == "") return("No package selected")
      spec()
    })

    observeEvent(input$confirm, {
      req(input$package)
      if (isTRUE(nzchar(input$target_r))) {
        target_r_path(input$target_r)
      }
      showNotification(sprintf("Target confirmed: %s", spec()), type = "message")
    })
  })
}
