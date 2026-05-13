mod_sync_ui <- function(id) {
  ns <- NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      class = "sync-sidebar",
      div(
        class = "sync-select-block sync-select-block-a",
        tags$div(class = "sync-select-label", "Select first installation"),
        selectInput(ns("install_a"), NULL, choices = character(0), selectize = FALSE),
        uiOutput(ns("install_a_badge"))
      ),
      div(
        class = "sync-select-block sync-select-block-b",
        tags$div(class = "sync-select-label", "Select second installation"),
        selectInput(ns("install_b"), NULL, choices = character(0), selectize = FALSE),
        uiOutput(ns("install_b_badge"))
      ),
      tags$div(class = "sync-select-label", "Click Compare to compare packages"),
      actionButton(ns("compare"), "Compare", class = "btn sync-compare-btn"),
      hr(),
      tags$div(class = "sync-select-label", "Click a button below to sync packages"),
      div(
        class = "sync-button-grid",
        actionButton(ns("sync_a_to_b"), "A→B", class = "btn-sm sync-btn sync-btn-a"),
        actionButton(ns("sync_b_to_a"), "B→A", class = "btn-sm sync-btn sync-btn-b"),
        actionButton(ns("sync_full"), "Full Sync", class = "btn-sm sync-btn sync-btn-full")
      )
    ),
    bslib::card(
      class = "sync-card",
      bslib::card_header("Comparison"),
      bslib::card_body(
        uiOutput(ns("detecting_msg")),
        uiOutput(ns("comparison_summary")),
        DT::dataTableOutput(ns("comparison_table"))
      )
    )
  )
}

mod_sync_server <- function(id, install_a_path = NULL, install_b_path = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    pending_sync    <- reactiveVal(NULL)
    routes_data     <- reactiveVal(data.frame())
    comparison_data <- reactiveVal(NULL)
    detecting       <- reactiveVal(TRUE)

    r_label <- function(path, version) {
      loc <- if (grepl("AppData", path, ignore.case = TRUE)) {
        "AppData"
      } else if (grepl("Program Files", path, ignore.case = TRUE)) {
        "Program Files"
      } else if (grepl("Documents", path, ignore.case = TRUE)) {
        "Documents"
      } else {
        basename(dirname(dirname(path)))
      }
      paste0("R ", version, "  —  ", loc)
    }

    r_badge <- function(version, bucket) {
      if (is.null(version) || is.na(version) || !nzchar(version)) {
        return(sprintf("<span class='sync-col-badge sync-col-%s'>R ?</span>", bucket))
      }
      sprintf("<span class='sync-col-badge sync-col-%s'>R %s</span>", bucket, version)
    }

    button_label <- function(from_version, from_bucket, to_version, to_bucket, label, bidirectional = FALSE) {
      from_text <- if (is.null(from_version) || is.na(from_version)) "R ?" else paste("R", from_version)
      to_text   <- if (is.null(to_version)   || is.na(to_version))   "R ?" else paste("R", to_version)
      arrow <- if (bidirectional) "&#8652;" else "&rarr;"
      shiny::HTML(sprintf(
        "<span class='sync-route-label'>%s</span><div class='sync-route-row'><span class='sync-route-pill sync-col-%s'>%s</span><span class='sync-route-arrow-icon'>%s</span><span class='sync-route-pill sync-col-%s'>%s</span></div>",
        label,
        from_bucket, from_text,
        arrow,
        to_bucket, to_text
      ))
    }

    status_badge <- function(status, display = NULL) {
      status_class <- gsub("[^a-z]", "-", tolower(status))
      label <- if (!is.null(display)) display else status
      sprintf("<span class='sync-status sync-status-%s'>%s</span>", status_class, label)
    }

    route_version <- function(path) {
      routes <- routes_data()
      if (nrow(routes) == 0 || is.null(path) || !nzchar(path)) {
        return(NA_character_)
      }

      idx <- match(path, routes$rscript_path)
      if (is.na(idx)) {
        return(NA_character_)
      }

      as.character(routes$version[[idx]])
    }

    normalize_manifest <- function(pkgs) {
      dt <- data.table::as.data.table(pkgs)

      if (ncol(dt) == 0) {
        return(data.table::data.table(
          package = character(),
          version = character(),
          priority = character(),
          source = character()
        ))
      }

      if (!"priority" %in% names(dt)) {
        data.table::set(dt, j = "priority", value = rep(NA_character_, nrow(dt)))
      }
      if (!"source" %in% names(dt)) {
        data.table::set(dt, j = "source", value = rep(NA_character_, nrow(dt)))
      }

      dt <- dt[is.na(dt[["priority"]]) | !(dt[["priority"]] %in% c("base", "recommended")), ]
      dt[, c("package", "version", "source"), with = FALSE]
    }

    build_sync_comparison <- function(a_pkgs, b_pkgs) {
      a_dt <- normalize_manifest(a_pkgs)
      b_dt <- normalize_manifest(b_pkgs)

      comp <- data.table::merge.data.table(
        a_dt,
        b_dt,
        by = "package",
        all = TRUE,
        suffixes = c(".a", ".b")
      )

      data.table::setnames(comp, c("version.a", "version.b"), c("version_in_a", "version_in_b"))
      if ("source.a" %in% names(comp)) {
        data.table::setnames(comp, "source.a", "source_in_a")
      }
      if ("source.b" %in% names(comp)) {
        data.table::setnames(comp, "source.b", "source_in_b")
      }

      status <- rep("same", nrow(comp))
      missing_b <- is.na(comp[["version_in_b"]]) & !is.na(comp[["version_in_a"]])
      missing_a <- is.na(comp[["version_in_a"]]) & !is.na(comp[["version_in_b"]])
      status[missing_b] <- "missing-from-B"
      status[missing_a] <- "missing-from-A"

      both_present <- !is.na(comp[["version_in_a"]]) & !is.na(comp[["version_in_b"]])
      if (any(both_present)) {
        ver_a <- package_version(comp[["version_in_a"]][both_present])
        ver_b <- package_version(comp[["version_in_b"]][both_present])
        both_status <- rep("same", sum(both_present))
        both_status[ver_a > ver_b] <- "newer-in-A"
        both_status[ver_b > ver_a] <- "newer-in-B"
        status[both_present] <- both_status
      }

      data.table::set(comp, j = "status", value = status)
      comp[order(comp[["package"]]), ]
    }

    packages_for_direction <- function(comp, direction) {
      if (direction == "A_to_B") {
        return(comp[["package"]][comp[["status"]] %in% c("missing-from-B", "newer-in-A")])
      }
      if (direction == "B_to_A") {
        return(comp[["package"]][comp[["status"]] %in% c("missing-from-A", "newer-in-B")])
      }
      character(0)
    }

    load_routes <- function() {
      detecting(TRUE)
      tryCatch({
        r <- sort_routes(courieR::find_routes())
        routes_data(r)
        if (nrow(r) == 0) {
          showNotification("No R installations detected.", type = "warning")
          updateSelectInput(session, "install_a", choices = character(0), selected = character(0))
          updateSelectInput(session, "install_b", choices = character(0), selected = character(0))
        } else {
          labels <- mapply(r_label, r$rscript_path, r$version)
          choices <- stats::setNames(r$rscript_path, labels)

          current_a <- isolate(input$install_a)
          current_b <- isolate(input$install_b)

          selected_a <- if (!is.null(current_a) && nzchar(current_a) && current_a %in% r$rscript_path) {
            current_a
          } else {
            r$rscript_path[[1]]
          }

          selected_b <- if (!is.null(current_b) && nzchar(current_b) && current_b %in% r$rscript_path && !identical(current_b, selected_a)) {
            current_b
          } else if (nrow(r) >= 2) {
            r$rscript_path[[2]]
          } else {
            r$rscript_path[[1]]
          }

          updateSelectInput(session, "install_a", choices = choices, selected = selected_a)
          updateSelectInput(session, "install_b", choices = choices, selected = selected_b)
        }
      }, error = function(e) {
        showNotification(paste("Route scan failed:", e$message), type = "error")
      })
      detecting(FALSE)
    }

    observe({
      a_version <- route_version(input$install_a)
      b_version <- route_version(input$install_b)

      updateActionButton(session, "sync_a_to_b", label = button_label(a_version, "a", b_version, "b", "Copy A → B"))
      updateActionButton(session, "sync_b_to_a", label = button_label(b_version, "b", a_version, "a", "Copy B → A"))
      updateActionButton(session, "sync_full",   label = button_label(a_version, "a", b_version, "b", "Two-Way Sync", bidirectional = TRUE))
    })

    output$install_a_badge <- renderUI({
      a_version <- route_version(input$install_a)
      div(
        class = "sync-install-meta sync-install-meta-a",
        shiny::HTML(r_badge(a_version, "a"))
      )
    })

    output$install_b_badge <- renderUI({
      b_version <- route_version(input$install_b)
      div(
        class = "sync-install-meta sync-install-meta-b",
        shiny::HTML(r_badge(b_version, "b"))
      )
    })

    output$detecting_msg <- renderUI({
      if (!detecting()) return(NULL)
      div(
        class = "sync-detecting-msg",
        tags$span(class = "sync-detecting-spinner", ""),
        "Detecting R installations…"
      )
    })

    output$comparison_summary <- renderUI({
      comp <- comparison_data()
      if (is.null(comp) || nrow(comp) == 0) return(NULL)
      a_version <- route_version(input$install_a)
      b_version <- route_version(input$install_b)

      counts <- table(comp[["status"]])
      make_chip <- function(status, label, css_extra = "") {
        n <- as.integer(counts[status])
        if (is.na(n) || n == 0) return(NULL)
        tags$span(
          class = paste("sync-summary-chip", css_extra),
          tags$strong(n), " × ", label
        )
      }

      a_lbl <- if (!is.na(a_version)) paste("newer in R", a_version) else "newer in A"
      b_lbl <- if (!is.na(b_version)) paste("newer in R", b_version) else "newer in B"
      na_lbl <- if (!is.na(a_version)) paste("not in R", a_version) else "missing from A"
      nb_lbl <- if (!is.na(b_version)) paste("not in R", b_version) else "missing from B"

      div(
        class = "sync-summary-bar",
        make_chip("same",          "identical",  "chip-same"),
        make_chip("newer-in-A",    a_lbl,        "chip-diff-a"),
        make_chip("newer-in-B",    b_lbl,        "chip-diff-b"),
        make_chip("missing-from-B", nb_lbl,      "chip-diff-a"),
        make_chip("missing-from-A", na_lbl,      "chip-diff-b")
      )
    })

    session$onFlushed(load_routes, once = TRUE)

    observeEvent(input$install_a, {
      if (is.function(install_a_path)) {
        install_a_path(input$install_a)
      }
      comparison_data(NULL)
    }, ignoreNULL = FALSE)

    observeEvent(input$install_b, {
      if (is.function(install_b_path)) {
        install_b_path(input$install_b)
      }
      comparison_data(NULL)
    }, ignoreNULL = FALSE)

    observeEvent(input$compare, {
      a_path <- input$install_a
      b_path <- input$install_b

      if (is.null(a_path) || !nzchar(a_path) || is.null(b_path) || !nzchar(b_path)) {
        showNotification("Select two R installations first.", type = "warning")
        return()
      }

      if (identical(a_path, b_path)) {
        showNotification("Choose two different R installations.", type = "warning")
        return()
      }

      withProgress(message = "Comparing R libraries...", {
        a_pkgs <- courieR::manifest(rscript_path = a_path)
        b_pkgs <- courieR::manifest(rscript_path = b_path)
        comparison_data(build_sync_comparison(a_pkgs, b_pkgs))
      })
    })

    sync_comparison <- reactive({
      comparison_data()
    })

    output$comparison_table <- DT::renderDataTable({
      comp <- sync_comparison()
      if (is.null(comp)) {
        return(DT::datatable(
          data.frame(
            package = character(),
            version_in_a = character(),
            version_in_b = character(),
            status = character()
          ),
          filter = "top",
          options = list(dom = "ft"),
          caption = htmltools::tags$caption("Select two installations and click Compare.")
        ))
      }

      a_version <- route_version(input$install_a)
      b_version <- route_version(input$install_b)
      raw_status <- comp[["status"]]
      status_labels <- raw_status
      if (!is.na(a_version)) {
        status_labels[status_labels == "newer-in-A"]    <- paste0("newer in R ", a_version)
        status_labels[status_labels == "missing-from-A"] <- paste0("not in R ", a_version)
      }
      if (!is.na(b_version)) {
        status_labels[status_labels == "newer-in-B"]    <- paste0("newer in R ", b_version)
        status_labels[status_labels == "missing-from-B"] <- paste0("not in R ", b_version)
      }
      display <- data.frame(
        package = comp[["package"]],
        version_in_a = ifelse(is.na(comp[["version_in_a"]]), "not installed", comp[["version_in_a"]]),
        version_in_b = ifelse(is.na(comp[["version_in_b"]]), "not installed", comp[["version_in_b"]]),
        status = mapply(status_badge, raw_status, status_labels, SIMPLIFY = TRUE),
        status_raw = raw_status,
        stringsAsFactors = FALSE
      )

      diff_statuses <- c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B")

      DT::datatable(
        display,
        rownames = FALSE,
        escape = FALSE,
        colnames = c(
          "Package",
          r_badge(a_version, "a"),
          r_badge(b_version, "b"),
          "Status",
          "status_raw"
        ),
        filter = "top",
        options = list(
          pageLength = 50,
          lengthMenu = c(25, 50, 100, -1),
          scrollX = TRUE,
          autoWidth = TRUE,
          columnDefs = list(list(targets = 4, visible = FALSE))
        ),
        class = "stripe hover compact sync-table"
      ) |>
        DT::formatStyle(
          "status_raw",
          target = "row",
          backgroundColor = DT::styleEqual(
            c("same", diff_statuses),
            c("#ffffff", "#fff6ef", "#eefafb", "#fff4ea", "#edf8fb")
          )
        ) |>
        DT::formatStyle(
          "status_raw",
          target = "row",
          fontWeight = DT::styleEqual(
            c("same", diff_statuses),
            c("400", "600", "600", "600", "600")
          )
        )
    })

    show_sync_confirmation <- function(plan) {
      if (plan$type == "full") {
        msg <- sprintf(
          "This will install or upgrade %d package(s) into B and %d package(s) into A. Proceed?",
          length(plan$packages_a_to_b),
          length(plan$packages_b_to_a)
        )
      } else {
        msg <- sprintf(
          "This will install or upgrade %d package(s). Proceed?",
          length(plan$packages)
        )
      }

      showModal(modalDialog(
        title = "Confirm Sync",
        msg,
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_sync"), "Proceed", class = "btn-primary")
        )
      ))
    }

    observeEvent(input$sync_a_to_b, {
      comp <- sync_comparison()
      if (is.null(comp)) {
        showNotification("Select both installs first.", type = "warning")
        return()
      }

      packages <- packages_for_direction(comp, "A_to_B")
      if (length(packages) == 0) {
        showNotification("Install B already has all packages from A at the same or newer version.", type = "message")
        return()
      }

      pending_sync(list(
        type = "A_to_B",
        source_path = input$install_a,
        target_path = input$install_b,
        target_b = input$install_b,
        packages = packages
      ))
      show_sync_confirmation(pending_sync())
    })

    observeEvent(input$sync_b_to_a, {
      comp <- sync_comparison()
      if (is.null(comp)) {
        showNotification("Select both installs first.", type = "warning")
        return()
      }

      packages <- packages_for_direction(comp, "B_to_A")
      if (length(packages) == 0) {
        showNotification("Install A already has all packages from B at the same or newer version.", type = "message")
        return()
      }

      pending_sync(list(
        type = "B_to_A",
        source_path = input$install_b,
        target_path = input$install_a,
        target_path_display = input$install_a,
        packages = packages
      ))
      show_sync_confirmation(list(
        type = "B_to_A",
        packages = packages,
        target_path = input$install_a
      ))
    })

    observeEvent(input$sync_full, {
      comp <- sync_comparison()
      if (is.null(comp)) {
        showNotification("Select both installs first.", type = "warning")
        return()
      }

      packages_a_to_b <- packages_for_direction(comp, "A_to_B")
      packages_b_to_a <- packages_for_direction(comp, "B_to_A")

      if (length(packages_a_to_b) + length(packages_b_to_a) == 0) {
        showNotification("Both installs already share the same packages at the same or newer versions.", type = "message")
        return()
      }

      plan <- list(
        type = "full",
        source_a = input$install_a,
        source_b = input$install_b,
        target_a = input$install_a,
        target_b = input$install_b,
        packages_a_to_b = packages_a_to_b,
        packages_b_to_a = packages_b_to_a
      )
      pending_sync(plan)
      show_sync_confirmation(plan)
    })

    observeEvent(input$confirm_sync, {
      plan <- pending_sync()
      removeModal()

      if (is.null(plan)) {
        return()
      }

      result <- tryCatch(
        withProgress(message = "Syncing packages...", value = 0, {
          if (plan$type == "full") {
            if (length(plan$packages_a_to_b) > 0) {
              courieR::ship(
                source_path = plan$source_a,
                target_path = plan$target_b,
                packages = plan$packages_a_to_b
              )
            }
            if (length(plan$packages_b_to_a) > 0) {
              courieR::ship(
                source_path = plan$source_b,
                target_path = plan$target_a,
                packages = plan$packages_b_to_a
              )
            }
            list(count = length(plan$packages_a_to_b) + length(plan$packages_b_to_a))
          } else {
            courieR::ship(
              source_path = plan$source_path,
              target_path = plan$target_path,
              packages = plan$packages
            )
            list(count = length(plan$packages))
          }
        }),
        error = function(e) {
          showNotification(paste("Error:", e$message), type = "error", duration = NULL)
          NULL
        }
      )

      if (!is.null(result)) {
        comparison_data(NULL)
        showNotification(sprintf("Sync complete. %d package(s) installed.", result$count), type = "message")
      }

      pending_sync(NULL)
    })
  })
}
