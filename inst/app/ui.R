ui <- bslib::page_navbar(
  title = NULL,
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
         function navigateToDepotShip() {
           var advTab = document.querySelector('[data-value=\"Advanced\"]');
           if (advTab) advTab.click();
           setTimeout(function() {
             var shipTab = document.querySelector('[data-value=\"Ship\"]');
             if (shipTab) shipTab.click();
           }, 150);
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
    title = tagList(
      "Advanced",
      uiOutput("advanced_badge", inline = TRUE)
    ),
    value = "Advanced",
    bslib::navset_card_tab(
      bslib::nav_panel(
        "Depot",
        div(class = "advanced-pane advanced-depot", mod_origin_ui("env"))
      ),
      bslib::nav_panel(
        "Manifest",
        div(class = "advanced-pane advanced-manifest", mod_manifest_ui("report"))
      ),
      bslib::nav_panel(
        "Maintenance",
        div(class = "advanced-pane advanced-maintenance",
            bslib::card(
              bslib::card_header("Restock"),
              bslib::card_body(mod_sync_maintenance_ui("sync"))
            ))
      )
    )
  )
)
