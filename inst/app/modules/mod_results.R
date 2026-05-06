mod_results_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("risk_banner")),
    bslib::navset_card_tab(
      bslib::nav_panel("Check Comparison", DT::dataTableOutput(ns("check_cmp"))),
      bslib::nav_panel("Test Comparison", DT::dataTableOutput(ns("test_cmp"))),
      bslib::nav_panel("Rationale", uiOutput(ns("rationale")))
    )
  )
}

mod_results_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    risk_res <- reactive({
      # Stub: in reality we'd pull parsed logs from baseline and post runs
      packport::classify_migration_risk(NULL, NULL)
    })
    
    output$risk_banner <- renderUI({
      res <- risk_res()
      theme <- switch(res$risk,
                      high = "danger",
                      medium = "warning",
                      low = "success",
                      "secondary")
      
      bslib::value_box(
        "Migration Risk",
        toupper(res$risk),
        theme = theme,
        width = 12
      )
    })
    
    output$check_cmp <- DT::renderDataTable({
      DT::datatable(data.frame(severity = character(), message = character(), change = character()))
    })
    
    output$test_cmp <- DT::renderDataTable({
      DT::datatable(data.frame(file = character(), test = character(), baseline = character(), post = character()))
    })
    
    output$rationale <- renderUI({
      res <- risk_res()
      if (length(res$rationale) == 0) return(p("No rationale available."))
      tags$ul(
        lapply(res$rationale, tags$li)
      )
    })
  })
}