mod_environment_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("env_summary")),
    bslib::card(
      bslib::card_header("Detected R Installations"),
      DT::dataTableOutput(ns("r_installs"))
    ),
    bslib::card(
      bslib::card_header("Dependencies"),
      DT::dataTableOutput(ns("dependencies"))
    )
  )
}

mod_environment_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # In a real app we'd trigger this based on global_project_path,
    # but for simplicity we'll just scan the current project or "." if null
    project_path <- reactiveVal(getShinyOption("packport_project_path", default = "."))
    
    env_data <- reactive({
      p <- project_path()
      if (is.null(p)) p <- "."
      list(
        type = packport::detect_project_type(p),
        deps = packport::scan_dependencies(p),
        r_inst = packport::detect_r_installations()
      )
    })
    
    output$env_summary <- renderUI({
      data <- env_data()
      req(data)
      
      renv_status <- if(data$type$has_renv) "Active" else "Not initialized"
      dep_count <- nrow(data$deps)
      
      tagList(
        bslib::layout_column_wrap(
          width = 1/3,
          bslib::value_box("Current R", paste(R.version$major, R.version$minor, sep=".")),
          bslib::value_box("renv Status", renv_status, theme = if(data$type$has_renv) "success" else "warning"),
          bslib::value_box("Dependencies", as.character(dep_count))
        )
      )
    })
    
    output$r_installs <- DT::renderDataTable({
      req(env_data())
      dt <- env_data()$r_inst
      if (nrow(dt) > 0) {
        dt <- dt[, c("version", "rscript_path", "is_current")]
      }
      DT::datatable(dt, options = list(pageLength = 5))
    })
    
    output$dependencies <- DT::renderDataTable({
      req(env_data())
      DT::datatable(env_data()$deps, options = list(pageLength = 10))
    })
  })
}