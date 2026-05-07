mod_receipt_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("summary_banner")),
    bslib::navset_card_tab(
      bslib::nav_panel("Results", DT::dataTableOutput(ns("results"))),
      bslib::nav_panel("Plan",    DT::dataTableOutput(ns("plan")))
    )
  )
}

mod_receipt_server <- function(id, migration_log) {
  moduleServer(id, function(input, output, session) {

    output$summary_banner <- renderUI({
      log <- migration_log()
      if (is.null(log) || is.null(log$results) || nrow(log$results) == 0) {
        return(bslib::card(bslib::card_body("No migration run yet.")))
      }
      n_total <- nrow(log$results)
      n_ok    <- sum(log$results$status == "success")
      n_err   <- n_total - n_ok
      theme   <- if (n_err == 0) "success" else if (n_ok == 0) "danger" else "warning"
      bslib::value_box(
        "Delivery Result",
        sprintf("%d / %d packages delivered", n_ok, n_total),
        sprintf("Elapsed: %.1fs", log$elapsed_sec),
        theme = theme
      )
    })

    output$results <- DT::renderDataTable({
      log <- migration_log()
      if (is.null(log) || is.null(log$results)) {
        return(DT::datatable(data.frame(
          package = character(), status = character(), message = character()
        )))
      }
      DT::datatable(log$results, options = list(pageLength = 15))
    })

    output$plan <- DT::renderDataTable({
      log <- migration_log()
      if (is.null(log) || is.null(log$plan) || nrow(log$plan) == 0) {
        return(DT::datatable(data.frame(package = character(), action = character())))
      }
      cols <- intersect(c("package", "version.x", "action", "source", "pak_spec"),
                        names(log$plan))
      DT::datatable(log$plan[, cols, with = FALSE], options = list(pageLength = 15))
    })
  })
}
