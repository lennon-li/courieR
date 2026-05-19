ui <- bslib::page_navbar(
  title = div(
    class = "app-brand",
    tags$img(src = "logo.png", height = "84px", style = "vertical-align: middle; background: transparent;"),
    uiOutput("top_install_summary")
  ),
  window_title = "courieR",
  theme = bslib::bs_theme(version = 5, preset = "shiny"),
  header = tags$head(tags$link(rel = "stylesheet", href = "styles.css")),

  bslib::nav_panel(
    "Sync",
    mod_sync_ui("sync")
  ),

  bslib::nav_panel(
    "Advanced",
    bslib::navset_card_tab(
      bslib::nav_panel("Packages",         div(class = "advanced-pane advanced-packages", mod_origin_ui("env"))),
      bslib::nav_panel("Delivery Receipt", div(class = "advanced-pane advanced-receipt", mod_receipt_ui("results"))),
      bslib::nav_panel("Details",          div(class = "advanced-pane advanced-details", uiOutput("details_panel"))),
      bslib::nav_panel("Manifest",         div(class = "advanced-pane advanced-manifest", mod_manifest_ui("report"))),
      bslib::nav_panel("Update",           div(class = "advanced-pane advanced-update",   mod_update_ui("update")))
    )
  ),

)
