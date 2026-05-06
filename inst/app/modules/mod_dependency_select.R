mod_dependency_select_ui <- function(id) {
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
      shiny::actionButton(ns("confirm"), "Confirm Target", class = "btn-primary")
    )
  )
}

mod_dependency_select_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    project_path <- reactiveVal(getShinyOption("packport_project_path", default = "."))
    deps <- reactiveVal(NULL)
    
    observe({
      p <- project_path()
      if (is.null(p)) p <- "."
      d <- packport::scan_dependencies(p)
      deps(d)
      updateSelectizeInput(session, "package", choices = c("", d$package))
    })
    
    spec <- reactive({
      req(input$package)
      packport::detect_install_source(
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
      showNotification(sprintf("Target confirmed: %s", spec()), type = "message")
    })
  })
}