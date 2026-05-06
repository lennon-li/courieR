mod_diagnostics_ui <- function(id) {
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

mod_diagnostics_server <- function(id, phase) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    project_path <- reactiveVal(getShinyOption("packport_project_path", default = "."))
    
    # Store process object and paths
    active_proc <- reactiveVal(NULL)
    stdout_file <- reactiveVal(NULL)
    
    run_cmd <- function(label, expr) {
      if (!is.null(active_proc()) && active_proc()$process$is_alive()) {
        showNotification("A process is already running", type = "warning")
        return()
      }
      p <- project_path()
      if (is.null(p)) p <- "."
      
      res <- packport::run_r_command(p, expr, phase, label)
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
    
    output$console_out <- renderText({
      if (is.null(active_proc())) return("Ready.")
      
      # Poll the process
      invalidateLater(1000, session)
      
      f <- stdout_file()
      if (is.null(f) || !file.exists(f)) return("Starting...")
      
      proc <- active_proc()$process
      alive <- proc$is_alive()
      
      lines <- readLines(f, warn = FALSE)
      text <- paste(tail(lines, 30), collapse = "\n")
      
      if (!alive) {
        text <- paste0(text, "\n[Process completed with exit code: ", proc$get_exit_status(), "]")
      }
      
      text
    })
    
    # Parse results (Stubs for now, would call parse_check_log / parse_test_log on actual files)
    output$test_results <- DT::renderDataTable({
      # In a real app we'd point this to the log file from active_proc() once done
      DT::datatable(data.frame(file = character(), test = character(), status = character(), message = character()))
    })
    
    output$check_results <- DT::renderDataTable({
      DT::datatable(data.frame(severity = character(), message = character(), file = character(), line = character()))
    })
  })
}