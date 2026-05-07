mod_migrate_ui <- function(id) {
  ns <- NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      title = "Setup",
      selectInput(ns("from_r"), "From (origin R)", choices = NULL),
      selectInput(ns("to_r"),   "To (destination R)", choices = NULL),
      actionButton(ns("refresh_routes"), "Refresh", class = "btn-sm btn-secondary"),
      hr(),
      actionButton(ns("deliver"), "Deliver", class = "btn-success btn-lg w-100"),
      br(),
      verbatimTextOutput(ns("progress"))
    ),
    bslib::card(
      bslib::card_header("Packages"),
      bslib::card_body(
        uiOutput(ns("pkg_checklist_ui"))
      )
    )
  )
}

mod_migrate_server <- function(id, from_r_path, to_r_path, selected_pkgs, migration_log) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    r_label <- function(path, version) {
      loc <- if (grepl("AppData", path, ignore.case = TRUE)) "AppData"
             else if (grepl("Program Files", path, ignore.case = TRUE)) "Program Files"
             else if (grepl("Documents", path, ignore.case = TRUE)) "Documents"
             else basename(dirname(dirname(path)))
      paste0("R ", version, "  —  ", loc)
    }

    load_routes <- function() {
      tryCatch({
        r <- courieR::find_routes()
        if (nrow(r) > 0) {
          labels  <- mapply(r_label, r$rscript_path, r$version)
          choices <- stats::setNames(r$rscript_path, labels)
          updateSelectInput(session, "from_r", choices = choices)
          updateSelectInput(session, "to_r",   choices = choices)
        } else {
          showNotification("No R installations detected.", type = "warning")
        }
      }, error = function(e) {
        showNotification(paste("Route scan failed:", e$message), type = "error")
      })
    }

    session$onFlushed(load_routes, once = TRUE)
    observeEvent(input$refresh_routes, { load_routes() })

    pkg_list <- reactive({
      p <- input$from_r
      if (is.null(p) || !nzchar(p)) return(NULL)
      withProgress(message = "Scanning origin R...", {
        tryCatch(
          courieR::manifest(rscript_path = p),
          error = function(e) { showNotification(e$message, type = "error"); NULL }
        )
      })
    })

    observeEvent(input$from_r, { from_r_path(input$from_r) })
    observeEvent(input$to_r,   { to_r_path(input$to_r) })

    output$pkg_checklist_ui <- renderUI({
      pkgs <- pkg_list()
      if (is.null(pkgs) || nrow(pkgs) == 0) {
        return(tags$p("Select an origin R installation to load packages."))
      }
      pkgs      <- pkgs[!duplicated(pkgs$package), ]
      pkg_names <- sort(pkgs$package)
      pkg_info  <- pkgs[match(pkg_names, pkgs$package), ]
      choice_labels <- lapply(seq_len(nrow(pkg_info)), function(i) {
        tags$span(class = "pkg-label",
          tags$span(pkg_info$package[i]),
          tags$span(class = "pkg-version", pkg_info$version[i]),
          tags$span(class = "pkg-source",  pkg_info$source[i])
        )
      })
      tagList(
        tags$div(
          style = "margin-bottom: 8px;",
          actionButton(ns("select_all"),   "Select All",   class = "btn-sm btn-outline-secondary"),
          actionButton(ns("deselect_all"), "Deselect All", class = "btn-sm btn-outline-secondary ms-2")
        ),
        checkboxGroupInput(ns("pkgs"), NULL,
          choiceNames  = choice_labels,
          choiceValues = pkg_names,
          selected     = pkg_names
        )
      )
    })

    observeEvent(input$select_all, {
      pkgs <- pkg_list()
      if (!is.null(pkgs)) updateCheckboxGroupInput(session, "pkgs", selected = sort(pkgs$package))
    })
    observeEvent(input$deselect_all, {
      updateCheckboxGroupInput(session, "pkgs", selected = character(0))
    })

    observeEvent(input$pkgs, { selected_pkgs(input$pkgs) }, ignoreNULL = FALSE)

    output$progress <- renderText({ "Ready." })

    observeEvent(input$deliver, {
      src  <- input$from_r
      tgt  <- input$to_r
      pkgs <- input$pkgs

      if (is.null(src) || !nzchar(src)) {
        showNotification("Select an origin R installation.", type = "error"); return()
      }
      if (is.null(tgt) || !nzchar(tgt)) {
        showNotification("Select a destination R installation.", type = "error"); return()
      }
      if (identical(src, tgt)) {
        showNotification("Origin and destination must be different.", type = "warning"); return()
      }
      if (is.null(pkgs) || length(pkgs) == 0) {
        showNotification("Select at least one package.", type = "warning"); return()
      }

      output$progress <- renderText({ "Delivering packages... (this may take a few minutes)" })

      result <- tryCatch(
        withProgress(message = "Delivering packages...", value = 0, {
          courieR::ship(source_path = src, target_path = tgt, packages = pkgs)
        }),
        error = function(e) {
          showNotification(paste("Error:", e$message), type = "error", duration = NULL)
          NULL
        }
      )

      if (!is.null(result)) {
        migration_log(result)
        n_ok  <- sum(result$results$status == "success")
        n_tot <- nrow(result$results)
        msg   <- sprintf("Done: %d / %d packages delivered in %.1fs.", n_ok, n_tot, result$elapsed_sec)
        output$progress <- renderText({ msg })
        if (n_ok < n_tot) {
          showNotification(sprintf("%d package(s) failed. See Delivery Receipt.", n_tot - n_ok),
                           type = "warning")
        } else {
          showNotification(msg, type = "message")
        }
      } else {
        output$progress <- renderText({ "Delivery failed. See error above." })
      }
    })
  })
}
