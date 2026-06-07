ui <- bslib::page_navbar(
  title = div(
    class = "app-brand",
    div(
      class = "app-brand-mark",
      tags$div(
        class = "app-logo-wrap",
        tags$img(src = "logo.png", height = "84px", style = "vertical-align: middle; background: transparent;")
      ),
      tags$div(class = "app-version", sprintf("v%s", utils::packageVersion("courieR")))
    )
  ),
  window_title = "courieR",
  theme = bslib::bs_theme(version = 5, preset = "shiny"),
  header = tagList(
    shinyjs::useShinyjs(),
    tags$head(
      tags$link(rel = "stylesheet", href = "styles.css"),
      tags$script(HTML(
        "$(document).on('shiny:busy', function(){ $('.app-brand-mark').addClass('app-busy'); });
         $(document).on('shiny:idle', function(){ $('.app-brand-mark').removeClass('app-busy'); });
         function courierChipClick(el, status, inputId) {
           el.classList.toggle('chip-active');
           var bar = el.closest('.sync-summary-bar');
           var activeChips = bar ? Array.from(bar.querySelectorAll('.chip-active')) : [];
           if (activeChips.length === 0) {
             Array.from(bar.querySelectorAll('.sync-summary-chip')).forEach(function(c) { c.classList.add('chip-active'); });
             Shiny.setInputValue(inputId, null, {priority: 'event'});
           } else {
             Shiny.setInputValue(inputId, activeChips.map(function(c) { return c.dataset.status; }), {priority: 'event'});
           }
         }"
      ))
    ),
    mod_error_reporter_ui("reporter")
  ),

  bslib::nav_panel(
    "Dispatch",
    mod_sync_ui("sync")
  ),

  bslib::nav_panel(
    "Advanced",
    bslib::navset_card_tab(
      bslib::nav_panel("Restock",          div(class = "advanced-pane advanced-update",   mod_update_ui("update"))),
      bslib::nav_panel("Depot",            div(class = "advanced-pane advanced-packages", mod_origin_ui("env"))),
      bslib::nav_panel("Delivery Receipt", div(class = "advanced-pane advanced-receipt", mod_receipt_ui("results"))),
      bslib::nav_panel("Route",            div(class = "advanced-pane advanced-details", uiOutput("details_panel"))),
      bslib::nav_panel("Manifest",         div(class = "advanced-pane advanced-manifest", mod_manifest_ui("report")))
    )
  ),

)
