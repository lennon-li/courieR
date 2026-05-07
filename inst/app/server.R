server <- function(input, output, session) {
  project_path <- reactiveVal(getShinyOption("courieR_project_path", default = NULL))
  target_r_path <- reactiveVal(NULL)
  baseline_results <- reactiveVal(list(check = NULL, test = NULL))
  post_results <- reactiveVal(list(check = NULL, test = NULL))

  output$sidebar_project_path <- renderText({
    p <- project_path()
    if (is.null(p)) "None selected" else as.character(p)
  })

  output$sidebar_target_r <- renderText({
    t <- target_r_path()
    if (is.null(t)) "Not set" else as.character(t)
  })

  mod_shipment_select_server("project", project_path)
  mod_origin_server("env", project_path)
  mod_cargo_select_server("dep", project_path, target_r_path)
  mod_dispatch_server("baseline", phase = "baseline", project_path, target_r_path, baseline_results)
  mod_dispatch_server("migrate", phase = "post_migration", project_path, target_r_path, post_results)
  mod_receipt_server("results", baseline_results, post_results)
  mod_manifest_server("report", project_path)
}
