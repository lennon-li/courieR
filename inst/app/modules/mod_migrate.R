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

    build_comparison_table <- function(inv) {
      if (!is.null(inv$comparison)) {
        return(data.table::as.data.table(inv$comparison))
      }

      status_map <- c(
        missing = "missing",
        outdated = "outdated",
        newer = "newer",
        same = "same"
      )

      parts <- lapply(names(status_map), function(name) {
        dt <- inv[[name]]
        if (is.null(dt) || nrow(dt) == 0) {
          return(NULL)
        }

        dt <- data.table::as.data.table(dt)
        if (!"status" %in% names(dt)) {
          data.table::set(dt, j = "status", value = rep(status_map[[name]], nrow(dt)))
        }
        dt
      })

      data.table::rbindlist(parts, use.names = TRUE, fill = TRUE)
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

    package_inventory <- reactive({
      src <- input$from_r
      tgt <- input$to_r
      src_msg <- if (is.null(src)) "<null>" else src
      tgt_msg <- if (is.null(tgt)) "<null>" else tgt
      message(sprintf("[mod_migrate] package_inventory fired: from=%s to=%s", src_msg, tgt_msg))

      if (is.null(src) || !nzchar(src) || is.null(tgt) || !nzchar(tgt)) {
        return(NULL)
      }

      withProgress(message = "Comparing R libraries...", {
        tryCatch(
          {
            src_pkgs <- courieR::manifest(rscript_path = src)
            tgt_pkgs <- courieR::manifest(rscript_path = tgt)
            comparison <- build_comparison_table(courieR::inventory(src_pkgs, tgt_pkgs))
            message(sprintf("[mod_migrate] inventory rows=%d missing=%d", nrow(comparison), sum(comparison[["status"]] == "missing", na.rm = TRUE)))
            comparison
          },
          error = function(e) {
            message(sprintf("[mod_migrate] inventory error: %s", e$message))
            showNotification(e$message, type = "error")
            NULL
          }
        )
      })
    })

    observeEvent(input$from_r, { from_r_path(input$from_r) })
    observeEvent(input$to_r,   { to_r_path(input$to_r) })

    output$pkg_checklist_ui <- renderUI({
      comparison <- package_inventory()
      if (is.null(comparison)) {
        return(tags$p("Select both origin and destination R installations to compare packages."))
      }

      if (nrow(comparison) == 0) {
        return(tags$p("No transferable packages found in the origin R installation."))
      }

      pkg_info <- comparison[order(comparison[["package"]]), ]
      pkg_names <- pkg_info[["package"]]
      selected_pkgs_default <- pkg_info[["package"]][pkg_info[["status"]] == "missing"]
      choice_labels <- lapply(seq_len(nrow(pkg_info)), function(i) {
        source_value <- if ("source" %in% names(pkg_info) && length(pkg_info[["source"]]) >= i) pkg_info[["source"]][i] else NA_character_
        status_value <- if ("status" %in% names(pkg_info) && length(pkg_info[["status"]]) >= i) pkg_info[["status"]][i] else "unknown"
        target_version <- if ("version.y" %in% names(pkg_info) && length(pkg_info[["version.y"]]) >= i && !is.na(pkg_info[["version.y"]][i])) {
          pkg_info[["version.y"]][i]
        } else {
          "not installed"
        }
        tags$span(class = "pkg-label",
          tags$span(pkg_info[["package"]][i]),
          tags$span(class = "pkg-version", paste("from", pkg_info[["version.x"]][i])),
          tags$span(class = "pkg-version", paste("to", target_version)),
          tags$span(class = "pkg-source", paste(status_value, if (!is.na(source_value)) paste0("(", source_value, ")") else ""))
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
          selected     = selected_pkgs_default
        )
      )
    })

    observeEvent(package_inventory(), {
      comparison <- package_inventory()
      if (is.null(comparison)) {
        selected_pkgs(character(0))
        return()
      }
      selected_pkgs(comparison[["package"]][comparison[["status"]] == "missing"])
    }, ignoreNULL = FALSE)

    observeEvent(input$select_all, {
      comparison <- package_inventory()
      if (!is.null(comparison)) updateCheckboxGroupInput(session, "pkgs", selected = comparison$package)
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
