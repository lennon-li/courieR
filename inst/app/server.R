server <- function(input, output, session) {
  # Global state
  project_path <- reactiveVal(getShinyOption("packport_project_path", default = NULL))
  
  output$sidebar_project_path <- renderText({
    p <- project_path()
    if (is.null(p)) "None selected" else as.character(p)
  })
  
  output$sidebar_target_r <- renderText({
    "Not set"
  })
  
  # Module servers (stubs)
  mod_project_select_server("project", project_path)
  mod_environment_server("env")
  mod_dependency_select_server("dep")
  mod_diagnostics_server("baseline", phase = "baseline")
  mod_diagnostics_server("migrate", phase = "post_migration")
  mod_results_server("results")
  mod_report_server("report")
}