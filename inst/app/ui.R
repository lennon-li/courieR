ui <- bslib::page_navbar(
  title = div(
    class = "app-brand",
    div(
      class = "app-brand-mark",
      tags$div(
        class = "app-logo-wrap",
        tags$img(src = "logo.png", height = "84px",
                 style = "vertical-align: middle; background: transparent;")
      ),
      tags$div(class = "app-version",
               sprintf("v%s", utils::packageVersion("courieR")))
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
             Array.from(bar.querySelectorAll('.sync-summary-chip'))
               .forEach(function(c) { c.classList.add('chip-active'); });
             Shiny.setInputValue(inputId, null, {priority: 'event'});
           } else {
             Shiny.setInputValue(inputId, activeChips.map(function(c) {
               return c.dataset.status;
             }), {priority: 'event'});
           }
         }
         function navigateToCustomDispatch() {
           var tab = document.querySelector('[data-value=\"Custom Dispatch\"]');
           if (tab) tab.click();
         }
         // Global busy lock: while a long operation runs (Compare/Ship), grey
         // out action buttons across ALL tabs (see body.app-busy in styles.css).
         // Set client-side from button onclick so it takes effect before the
         // blocking server observer starts; cleared by the server when done.
         function courierAppBusy(on) {
           document.body.classList.toggle('app-busy', !!on);
         }"
      ))
    ),
    mod_error_reporter_ui("reporter")
  ),

  bslib::nav_panel(
    "Bulk Dispatch",
    mod_sync_ui("sync")
  ),

  bslib::nav_panel(
    title = tagList(
      "Custom Dispatch",
      uiOutput("custom_dispatch_badge", inline = TRUE)
    ),
    value = "Custom Dispatch",
    div(class = "advanced-pane", mod_origin_ship_ui("env"))
  ),

  bslib::nav_panel(
    "Tools",
    div(
      class = "advanced-pane advanced-tools",
      bslib::card(
        bslib::card_header("Restock"),
        bslib::card_body(mod_sync_maintenance_ui("sync"))
      ),
      mod_origin_browse_ui("env"),
      div(class = "advanced-manifest", mod_manifest_ui("report"))
    )
  )
)
