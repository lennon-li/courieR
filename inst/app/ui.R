ui <- bslib::page_navbar(
  title = "packport",
  theme = bslib::bs_theme(version = 5, preset = "shiny"),
  sidebar = bslib::sidebar(
    title = "Migration Status",
    "Current Project:",
    verbatimTextOutput("sidebar_project_path"),
    "Target R:",
    verbatimTextOutput("sidebar_target_r")
  ),
  
  bslib::nav_panel("1. Project", mod_project_select_ui("project")),
  bslib::nav_panel("2. Environment", mod_environment_ui("env")),
  bslib::nav_panel("3. Target", mod_dependency_select_ui("dep")),
  bslib::nav_panel("4. Baseline", mod_diagnostics_ui("baseline")),
  bslib::nav_panel("5. Migrate", mod_diagnostics_ui("migrate")),
  bslib::nav_panel("6. Results", mod_results_ui("results")),
  bslib::nav_panel("7. Report", mod_report_ui("report"))
)