mod_shipment_select_ui <- function(id) {
  ns <- NS(id)
  tagList(
    bslib::card(
      bslib::card_header("Shipment Selection"),
      shiny::textInput(ns("path"), "Project Path", value = "."),
      shiny::actionButton(ns("scan"), "Scan Shipment", class = "btn-primary")
    ),
    uiOutput(ns("scan_results"))
  )
}

mod_shipment_select_server <- function(id, global_project_path) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    observeEvent(global_project_path(), {
      if (!is.null(global_project_path())) {
        updateTextInput(session, "path", value = global_project_path())
      }
    })

    scan_res <- reactiveVal(NULL)

    observeEvent(input$scan, {
      req(input$path)
      path <- input$path
      if (dir.exists(path)) {
        res <- courieR::inspect_shipment(path)
        scan_res(res)
        global_project_path(res$project_path)
      } else {
        showNotification("Directory does not exist", type = "error")
      }
    })

    output$scan_results <- renderUI({
      res <- scan_res()
      if (is.null(res)) return(NULL)

      tagList(
        bslib::layout_column_wrap(
          width = 1/4,
          bslib::value_box("Package", if (res$is_package) "Yes" else "No", theme = if (res$is_package) "success" else "secondary"),
          bslib::value_box("renv", if (res$has_renv) "Yes" else "No", theme = if (res$has_renv) "success" else "secondary"),
          bslib::value_box("Git", if (res$has_git) "Yes" else "No", theme = if (res$has_git) "success" else "secondary"),
          bslib::value_box("Tests", if (res$has_tests) "Yes" else "No", theme = if (res$has_tests) "success" else "secondary")
        ),
        bslib::navset_card_tab(
          bslib::nav_panel("R Files", DT::dataTableOutput(ns("r_files"))),
          bslib::nav_panel("Test Files", DT::dataTableOutput(ns("test_files"))),
          bslib::nav_panel("App Files", DT::dataTableOutput(ns("app_files")))
        )
      )
    })

    output$r_files <- DT::renderDataTable({
      req(scan_res())
      DT::datatable(scan_res()$r_files, options = list(pageLength = 5))
    })

    output$test_files <- DT::renderDataTable({
      req(scan_res())
      DT::datatable(scan_res()$test_files, options = list(pageLength = 5))
    })

    output$app_files <- DT::renderDataTable({
      req(scan_res())
      DT::datatable(scan_res()$app_files, options = list(pageLength = 5))
    })
  })
}
