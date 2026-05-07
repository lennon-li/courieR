ui <- bslib::page_navbar(
  title = "courieR",
  theme = bslib::bs_theme(version = 5, preset = "shiny"),
  sidebar = bslib::sidebar(
    title = "Delivery Status",
    "Current Shipment:",
    verbatimTextOutput("sidebar_project_path"),
    "Destination R:",
    verbatimTextOutput("sidebar_target_r")
  ),

  bslib::nav_panel("1. Shipment", mod_shipment_select_ui("project")),
  bslib::nav_panel("2. Origin", mod_origin_ui("env")),
  bslib::nav_panel("3. Destination", mod_cargo_select_ui("dep")),
  bslib::nav_panel("4. Pickup", mod_dispatch_ui("baseline")),
  bslib::nav_panel("5. Deliver", mod_dispatch_ui("migrate")),
  bslib::nav_panel("6. Delivery Receipt", mod_receipt_ui("results")),
  bslib::nav_panel("7. Manifest", mod_manifest_ui("report"))
)