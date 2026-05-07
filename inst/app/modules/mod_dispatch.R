mod_dispatch_ui <- function(id) {
  ns <- NS(id)
  tagList(
    bslib::layout_column_wrap(
      width = 1/3,
      shiny::actionButton(ns("run_document"), "1. Document", icon = icon("file-code")),
      shiny::actionButton(ns("run_test"), "2. Test", icon = icon("flask")),
      shiny::actionButton(ns("run_check"), "3. Check", icon = icon("check-circle"))
    ),
    br(),
    bslib::card(
      bslib::card_header("Console Output"),
      verbatimTextOutput(ns("console_out"))
    ),
    bslib::navset_card_tab(
      bslib::nav_panel("Test Results", DT::dataTableOutput(ns("test_results"))),
      bslib::nav_panel("Check Results", DT::dataTableOutput(ns("check_results")))
    )
  )
}

mod_dispatch_server <- function(id, phase, project_path, target_r_path, results_store) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    active_proc <- reactiveVal(NULL)
    stdout_file <- reactiveVal(NULL)
    parsed_flag <- reactiveVal(FALSE)

    check_data <- reactiveVal(
      data.table::data.table(severity = character(), message = character(),
                             file = character(), line = character())
    )
    test_data <- reactiveVal(
      data.table::data.table(file = character(), test = character(),
                             status = character(), message = character())
    )

    run_cmd <- function(label, expr) {
      if (!is.null(active_proc()) && active_proc()$process$is_alive()) {
        showNotification("A process is already running", type = "warning")
        return()
      }
      p <- project_path()
      if (is.null(p)) p <- "."

      parsed_flag(FALSE)
      results_store(list(check = NULL, test = NULL))

      res <- courieR::dispatch(p, expr, phase, label)
      active_proc(res)
      stdout_file(res$stdout_path)
    }

    observeEvent(input$run_document, {
      run_cmd("document", "devtools::document()")
    })

    observeEvent(input$run_test, {
      run_cmd("test", "devtools::test()")
    })

    observeEvent(input$run_check, {
      run_cmd("check", "devtools::check()")
    })

    observe({
      proc_val <- active_proc()
      if (is.null(proc_val)) return()

      invalidateLater(1000, session)

      proc <- proc_val$process
      alive <- proc$is_alive()

      isolate({
        if (!alive && !parsed_flag()) {
          f <- stdout_file()
          if (!is.null(f) && file.exists(f)) {
            cparsed <- courieR::parse_inspection_log(f)
            tparsed <- courieR::parse_dispatch_log(f)

            if (nrow(cparsed) > 0L) check_data(cparsed)
            if (nrow(tparsed) > 0L) test_data(tparsed)

            results_store(list(check = cparsed, test = tparsed))
          }
          parsed_flag(TRUE)
        }
      })
    })

    output$console_out <- renderText({
      if (is.null(active_proc())) return("Ready.")

      invalidateLater(1000, session)

      f <- stdout_file()
      if (is.null(f) || !file.exists(f)) return("Starting...")

      proc <- active_proc()$process
      alive <- proc$is_alive()

      lines <- readLines(f, warn = FALSE)
      text <- paste(tail(lines, 30), collapse = "\n")

      if (!alive) {
        text <- paste0(text, "\n[Process completed with exit code: ",
                       proc$get_exit_status(), "]")
      }

      text
    })

    output$test_results <- DT::renderDataTable({
      DT::datatable(test_data(), options = list(pageLength = 10))
    })

    output$check_results <- DT::renderDataTable({
      DT::datatable(check_data(), options = list(pageLength = 10))
    })
  })
}
