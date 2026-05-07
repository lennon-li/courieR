ui <- bslib::page_navbar(
  title = tags$img(src = "logo.png", height = "96px",
                   style = "vertical-align: middle;"),
  theme = bslib::bs_theme(version = 5, preset = "shiny"),
  tags$head(tags$link(rel = "stylesheet", href = "styles.css")),

  bslib::nav_panel(
    "Migrate",
    mod_migrate_ui("migrate")
  ),

  bslib::nav_panel(
    "Advanced",
    bslib::navset_card_tab(
      bslib::nav_panel("Packages",         mod_origin_ui("env")),
      bslib::nav_panel("Delivery Receipt", mod_receipt_ui("results")),
      bslib::nav_panel("Details",          uiOutput("details_panel")),
      bslib::nav_panel("Manifest",         mod_manifest_ui("report"))
    )
  ),

)
