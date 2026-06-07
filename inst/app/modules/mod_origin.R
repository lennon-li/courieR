mod_origin_ui <- function(id) {
  ns <- NS(id)
  tagList(
    bslib::card(
      bslib::card_header("Detected Depots"),
      bslib::card_body(
        uiOutput(ns("detecting_msg")),
        DT::dataTableOutput(ns("r_installs"))
      )
    ),
    bslib::card(
      bslib::card_header("Depot Manifest"),
      bslib::card_body(
        uiOutput(ns("pkg_controls")),
        uiOutput(ns("loading_msg")),
        DT::dataTableOutput(ns("packages"))
      )
    )
  )
}

mod_origin_server <- function(id, from_r_path = NULL, routes_cache = NULL, push_error = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    routes_rv  <- reactiveVal(NULL)
    detecting  <- reactiveVal(FALSE)
    loading_pkg <- reactiveVal(FALSE)

    # Detection is driven from the Sync tab's Detect button, which populates the
    # shared routes_cache. Pick up its result whenever it changes.
    if (!is.null(routes_cache)) {
      observeEvent(routes_cache(), {
        routes_rv(routes_cache())
        detecting(FALSE)
      }, ignoreNULL = TRUE)
    }

    output$detecting_msg <- renderUI({
      if (!detecting()) return(NULL)
      div(
        class = "sync-detecting-msg",
        tags$span(class = "sync-detecting-spinner", ""),
        "Detecting R installations…"
      )
    })

    output$r_installs <- DT::renderDataTable({
      routes <- routes_rv()
      if (is.null(routes) || nrow(routes) == 0) {
        return(DT::datatable(
          data.frame(version = character(), rscript_path = character()),
          options = list(dom = "t"), rownames = FALSE
        ))
      }
      DT::datatable(
        routes[, intersect(c("version", "rscript_path", "is_current"), names(routes))],
        options = list(pageLength = 5, dom = "tip"),
        rownames = FALSE
      )
    })

    output$pkg_controls <- renderUI({
      routes <- routes_rv()
      if (detecting()) return(NULL)
      if (is.null(routes)) {
        return(tags$p(class = "update-no-selection", "Click Scout in the Sync tab to find installations."))
      }
      if (nrow(routes) == 0) {
        return(tags$p(class = "update-no-selection", "No depots detected."))
      }

      labels  <- mapply(function(path, ver) {
        loc <- if (grepl("AppData", path, ignore.case = TRUE)) "AppData"
               else if (grepl("Program Files", path, ignore.case = TRUE)) "Program Files"
               else if (grepl("Documents", path, ignore.case = TRUE)) "Documents"
               else basename(dirname(dirname(path)))
        paste0("R ", ver, "  —  ", loc)
      }, routes$rscript_path, routes$version)

      choices <- stats::setNames(routes$rscript_path, labels)

      div(
        class = "origin-picker-wrap",
        tags$div(class = "sync-select-label", "Select depot to inspect"),
        selectInput(ns("selected_path"), NULL,
                    choices = choices, selectize = FALSE,
                    width = "100%")
      )
    })

    pkg_data <- reactive({
      req(input$selected_path, nzchar(input$selected_path))
      loading_pkg(TRUE)
      on.exit(loading_pkg(FALSE))
      tryCatch(
        courieR::manifest(rscript_path = input$selected_path),
        error = function(e) {
          showNotification(paste("Failed to load packages:", e$message), type = "error")
          if (is.function(push_error)) push_error(e$message, context = "Loading package list")
          NULL
        }
      )
    })

    output$loading_msg <- renderUI({
      if (!loading_pkg()) return(NULL)
      div(
        class = "sync-detecting-msg",
        tags$span(class = "sync-detecting-spinner", ""),
        "Loading package list…"
      )
    })

    output$packages <- DT::renderDataTable({
      req(pkg_data())
      pkgs <- pkg_data()
      pkgs <- pkgs[is.na(pkgs$priority) | !(pkgs$priority %in% c("base", "recommended")), ]
      DT::datatable(pkgs, options = list(pageLength = 15, dom = "frtip"), rownames = FALSE)
    })

    observeEvent(routes_rv(), {
      routes <- routes_rv()
      if (is.null(routes) || nrow(routes) == 0) return()
      labels <- mapply(function(path, ver) {
        loc <- if (grepl("AppData", path, ignore.case = TRUE)) "AppData"
               else if (grepl("Program Files", path, ignore.case = TRUE)) "Program Files"
               else if (grepl("Documents", path, ignore.case = TRUE)) "Documents"
               else basename(dirname(dirname(path)))
        paste0("R ", ver, "  —  ", loc)
      }, routes$rscript_path, routes$version)
      choices <- stats::setNames(routes$rscript_path, labels)
      updateSelectInput(session, "selected_path", choices = choices,
                        selected = routes$rscript_path[[1]])
    }, ignoreNULL = TRUE)
  })
}
