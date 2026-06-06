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
      actionButton(ns("compare"), "Compare", class = "btn sync-compare-btn"),
      hr(),
      selectInput(
        ns("transfer_mode"),
        label = "Transfer mode",
        choices = c(
          "Online — reinstall via pak" = "online",
          "Offline — copy files, skip the rest" = "offline",
          "Preserve versions — copy then pin" = "preserve"
        ),
        selected = "online"
      ),
      selectInput(
        ns("sync_direction"),
        label = "Sync direction",
        choices = c(
          "A → B" = "A_to_B",
          "B → A" = "B_to_A",
          "Two-way"    = "full"
        ),
        selected = "A_to_B"
      ),
      actionButton(ns("sync_btn"), "Sync", class = "btn sync-compare-btn"),
    ),
    bslib::card(
      class = "sync-card",
      bslib::card_header("Comparison"),
      bslib::card_body(
        uiOutput(ns("detecting_msg")),
        uiOutput(ns("comparison_summary")),
        div(
          class = "sync-workspace",
          div(
            class = "sync-comparison-pane",
            DT::dataTableOutput(ns("comparison_table"))
          ),
          div(
            class = "sync-log-pane",
            uiOutput(ns("sync_log"))
          )
        )
      )
    )
  )
}

mod_sync_server <- function(id, install_a_path = NULL, install_b_path = NULL, push_error = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    pending_sync    <- reactiveVal(NULL)
    routes_data     <- reactiveVal(data.frame())
    comparison_data <- reactiveVal(NULL)
    detecting       <- reactiveVal(TRUE)
    detection_status <- reactiveVal(NULL)
    sync_log        <- reactiveVal(character())
    sync_active     <- reactiveVal(FALSE)
    sync_pct        <- reactiveVal(0)
    sync_step       <- reactiveVal("Idle")

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
        "<span class='visually-hidden'>%s</span><div class='sync-route-row'><span class='sync-route-pill sync-col-%s'>%s</span><span class='sync-route-arrow-icon'>%s</span><span class='sync-route-pill sync-col-%s'>%s</span></div>",
        htmltools::htmlEscape(label),
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

    add_sync_log <- function(...) {
      msg <- paste(..., collapse = "")
      entry <- sprintf("%s  %s", format(Sys.time(), "%H:%M:%S"), msg)
      sync_log(c(sync_log(), entry))
      try({
        entry_json <- jsonlite::toJSON(entry, auto_unbox = TRUE)
        shinyjs::runjs(sprintf(
          "(function(){var el=document.getElementById('%s'); if(!el) return; if(el.getAttribute('data-empty')==='true'){el.textContent=''; el.removeAttribute('data-empty');} var line=%s; el.textContent += (el.textContent ? '\\n' : '') + line; el.scrollTop = el.scrollHeight;})();",
          ns("sync_log_pre"),
          entry_json
        ))
      }, silent = TRUE)
      invisible(NULL)
    }

    set_sync_progress <- function(pct = NULL, step = NULL, active = TRUE) {
      sync_active(isTRUE(active))
      if (!is.null(pct)) sync_pct(max(0, min(100, as.numeric(pct))))
      if (!is.null(step)) sync_step(step)
      invisible(NULL)
    }

    comparison_counts_text <- function(comp) {
      if (is.null(comp) || nrow(comp) == 0) {
        return("no packages in comparison")
      }

      statuses <- c("same", "missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B")
      counts <- table(factor(comp[["status"]], levels = statuses))
      sprintf(
        "%d same, %d missing from B, %d missing from A, %d newer in A, %d newer in B",
        counts[["same"]],
        counts[["missing-from-B"]],
        counts[["missing-from-A"]],
        counts[["newer-in-A"]],
        counts[["newer-in-B"]]
      )
    }

    add_plan_log <- function(ship_result) {
      plan <- ship_result$plan
      if (is.null(plan) || nrow(plan) == 0) {
        add_sync_log("Plan details: no package actions were required by ship().")
        return(invisible(NULL))
      }

      install_n <- sum(plan$action == "install", na.rm = TRUE)
      upgrade_n <- sum(plan$action == "upgrade", na.rm = TRUE)
      add_sync_log(sprintf("Plan details: %d install(s), %d upgrade(s).", install_n, upgrade_n))

      for (i in seq_len(nrow(plan))) {
        source_version <- if ("version.x" %in% names(plan)) plan$version.x[[i]] else NA_character_
        target_version <- if ("version.y" %in% names(plan)) plan$version.y[[i]] else NA_character_
        target_text <- if (is.na(target_version) || !nzchar(target_version)) "not installed" else target_version
        pak_spec <- if ("pak_spec" %in% names(plan)) plan$pak_spec[[i]] else plan$package[[i]]
        add_sync_log(sprintf(
          "  - %s: %s target %s -> source %s using pak spec %s",
          plan$package[[i]],
          plan$action[[i]],
          target_text,
          source_version,
          pak_spec
        ))
      }

      invisible(NULL)
    }

    add_result_log <- function(ship_result) {
      results <- ship_result$results
      if (is.null(results) || nrow(results) == 0) {
        add_sync_log("Result details: no per-package results were returned.")
        return(invisible(NULL))
      }

      for (i in seq_len(nrow(results))) {
        add_sync_log(sprintf(
          "  - %s: %s — %s",
          results$package[[i]],
          results$status[[i]],
          results$message[[i]]
        ))
      }

      invisible(NULL)
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

    route_display <- function(path) {
      routes <- routes_data()
      if (nrow(routes) == 0 || is.null(path) || !nzchar(path)) {
        return("unknown R installation")
      }

      idx <- match(path, routes$rscript_path)
      if (is.na(idx)) {
        return("selected R installation")
      }

      r_label(path, routes$version[[idx]])
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
      status_rank <- match(
        comp[["status"]],
        c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B", "same")
      )
      comp <- comp[order(status_rank, comp[["package"]]), ]
      comp[]
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

    estimate_sync_time <- function(package_count) {
      if (package_count <= 0) {
        return("less than 1 minute")
      }

      min_minutes <- ceiling(max(1, package_count * 0.25))
      max_minutes <- ceiling(max(min_minutes + 1, package_count * 1.5))

      if (package_count >= 20) {
        max_minutes <- ceiling(max_minutes * 1.25)
      }

      sprintf("%d-%d minutes", min_minutes, max_minutes)
    }

    refresh_comparison <- function(a_path, b_path, progress_detail = "Refreshing comparison", pct_base = 0, pct_span = 100) {
      set_sync_progress(pct_base, progress_detail, active = TRUE)
      add_sync_log(progress_detail, ".")
      set_sync_progress(pct_base + pct_span * 0.2, "Scanning first installation", active = TRUE)
      a_pkgs <- courieR::manifest(rscript_path = a_path)
      set_sync_progress(pct_base + pct_span * 0.55, "Scanning second installation", active = TRUE)
      b_pkgs <- courieR::manifest(rscript_path = b_path)
      set_sync_progress(pct_base + pct_span * 0.8, "Building comparison", active = TRUE)
      comparison_data(build_sync_comparison(a_pkgs, b_pkgs))
      set_sync_progress(pct_base + pct_span, "Comparison ready", active = TRUE)
    }

    load_routes <- function() {
      detecting(TRUE)
      detection_status(NULL)
      add_sync_log("Scanning for R installations...")
      tryCatch({
        r <- sort_routes(courieR::find_routes())
        routes_data(r)
        detection_status(sprintf("Detection complete: found %d installation(s).", nrow(r)))
        add_sync_log(sprintf("Detection complete: found %d installation(s).", nrow(r)))
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
        detection_status("Detection failed. See error details below.")
        add_sync_log("Detection failed: ", e$message)
        showNotification(paste("Route scan failed:", e$message), type = "error")
        if (is.function(push_error)) push_error(e$message, context = "Detecting R installations")
      })
      detecting(FALSE)
    }


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
      if (detecting()) {
        return(div(
          class = "alert alert-info sync-detecting-msg",
          role = "status",
          tags$span(class = "sync-detecting-spinner", ""),
          "Scanning for R installations..."
        ))
      }

      status <- detection_status()
      if (is.null(status) || !nzchar(status)) return(NULL)
      div(
        class = "alert alert-info sync-detecting-msg",
        role = "status",
        status
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

    output$sync_log <- renderUI({
      entries <- sync_log()
      active <- sync_active()
      pct <- sync_pct()
      step <- sync_step()

      progress_ui <- if (active) {
        tags$div(
          class = "sync-inline-progress",
          tags$div(class = "sync-progress-label", step),
          tags$div(
            class = "progress",
            tags$div(
              class = "progress-bar progress-bar-striped progress-bar-animated",
              role = "progressbar",
              style = sprintf("width: %.0f%%;", pct),
              `aria-valuenow` = sprintf("%.0f", pct),
              `aria-valuemin` = "0",
              `aria-valuemax` = "100",
              sprintf("%.0f%%", pct)
            )
          )
        )
      } else {
        NULL
      }

      empty_text <- "Run Compare, choose a sync direction, then watch package activity here."
      tags$div(
        class = paste("sync-log", if (length(entries) == 0) "sync-log-empty" else ""),
        tags$div(
          class = "sync-log-title",
          "Sync log",
          tags$span(
            class = "sync-log-subtitle",
            if (length(entries) == 0) "Waiting for sync activity" else "Detailed package actions and post-sync comparison refresh"
          )
        ),
        progress_ui,
        tags$pre(
          id = ns("sync_log_pre"),
          `data-empty` = if (length(entries) == 0) "true" else NULL,
          if (length(entries) == 0) empty_text else paste(utils::tail(entries, 250), collapse = "\n")
        )
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

      tryCatch({
        set_sync_progress(0, "Starting comparison", active = TRUE)
        refresh_comparison(a_path, b_path, progress_detail = "Starting comparison")
        set_sync_progress(100, "Comparison ready", active = FALSE)
      }, error = function(e) {
        set_sync_progress(0, "Comparison failed", active = FALSE)
        add_sync_log("Comparison failed: ", e$message)
        showNotification(paste("Comparison failed:", e$message), type = "error", duration = NULL)
        if (is.function(push_error)) push_error(e$message, context = "Comparing R libraries")
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
        status_rank = match(raw_status, c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B", "same")),
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
          "status_raw",
          "status_rank"
        ),
        filter = "top",
        options = list(
          pageLength = 50,
          lengthMenu = c(25, 50, 100, -1),
          scrollX = TRUE,
          autoWidth = TRUE,
          order = list(list(5, "asc"), list(0, "asc")),
          columnDefs = list(list(targets = c(4, 5), visible = FALSE)),
          drawCallback = DT::JS("function(settings) {
            var node = this.api().table().node();
            if ($(node).data('dtFilterSetup')) return;
            $(node).data('dtFilterSetup', true);
            var api = this.api();
            var inputs = $(api.table().header()).find('input[type=\"search\"]');
            inputs.eq(1).closest('th').empty();
            inputs.eq(2).closest('th').empty();
            var statusTh = inputs.eq(3).closest('th');
            var sel = $('<select style=\"width:100%;padding:3px 6px;border:1px solid #ced4da;border-radius:6px;font-size:0.85em;background:#fff\">' +
              '<option value=\"\">All statuses</option>' +
              '<option value=\"same\">Same</option>' +
              '<option value=\"newer-in-A\">Newer in A</option>' +
              '<option value=\"newer-in-B\">Newer in B</option>' +
              '<option value=\"missing-from-A\">Missing from A</option>' +
              '<option value=\"missing-from-B\">Missing from B</option>' +
              '</select>');
            statusTh.empty().append(sel);
            sel.on('change', function() {
              api.column(4).search(this.value).draw();
            });
          }")
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
      mode_note <- switch(
        input$transfer_mode,
        online = "Packages will be reinstalled from CRAN / GitHub / Bioconductor.",
        offline = "Packages will be copied by file. Packages without a valid source path will be skipped.",
        preserve = "Packages will be copied first. Any that cannot be copied will be reinstalled at the same version.",
        "Packages will be transferred using the selected mode."
      )

      if (plan$type == "full") {
        package_count <- length(plan$packages_a_to_b) + length(plan$packages_b_to_a)
        msg <- sprintf(
          "This will install or upgrade %d package(s) into B and %d package(s) into A. Estimated time: %s. Proceed?",
          length(plan$packages_a_to_b),
          length(plan$packages_b_to_a),
          estimate_sync_time(package_count)
        )
      } else {
        package_count <- length(plan$packages)
        msg <- sprintf(
          "This will install or upgrade %d package(s). Estimated time: %s. Proceed?",
          length(plan$packages),
          estimate_sync_time(package_count)
        )
      }

      showModal(modalDialog(
        title = "Confirm Sync",
        tags$p(msg),
        tags$p(tags$strong("Transfer mode: "), mode_note),
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_sync"), "Proceed", class = "btn-primary")
        )
      ))
    }

    observeEvent(input$sync_btn, {
      comp <- sync_comparison()
      if (is.null(comp)) {
        showNotification("Run Compare first.", type = "warning")
        return()
      }

      direction <- input$sync_direction

      if (direction == "full") {
        packages_a_to_b <- packages_for_direction(comp, "A_to_B")
        packages_b_to_a <- packages_for_direction(comp, "B_to_A")
        if (length(packages_a_to_b) + length(packages_b_to_a) == 0) {
          showNotification("Both installations are already in sync.", type = "message")
          return()
        }
        plan <- list(
          type            = "full",
          source_a        = input$install_a,
          source_b        = input$install_b,
          target_a        = input$install_a,
          target_b        = input$install_b,
          packages_a_to_b = packages_a_to_b,
          packages_b_to_a = packages_b_to_a
        )
        pending_sync(plan)
        show_sync_confirmation(plan)
      } else {
        packages <- packages_for_direction(comp, direction)
        if (length(packages) == 0) {
          label <- if (direction == "A_to_B") "B" else "A"
          showNotification(sprintf("Install %s already has all packages at the same or newer version.", label), type = "message")
          return()
        }
        src <- if (direction == "A_to_B") input$install_a else input$install_b
        tgt <- if (direction == "A_to_B") input$install_b else input$install_a
        pending_sync(list(
          type        = direction,
          source_path = src,
          target_path = tgt,
          packages    = packages
        ))
        show_sync_confirmation(pending_sync())
      }
    })

    observeEvent(input$confirm_sync, {
      plan <- pending_sync()
      removeModal()

      if (is.null(plan)) {
        return()
      }

      sync_log(character())
      add_sync_log("Preparing sync plan.")
      add_sync_log("Base and recommended R packages are skipped; only user-installed packages are compared/synced.")
      add_sync_log("Current comparison before sync: ", comparison_counts_text(comparison_data()), ".")

      result <- tryCatch({
        set_sync_progress(5, "Preparing sync plan", active = TRUE)

        if (plan$type == "full") {
          batches <- list()
          if (length(plan$packages_a_to_b) > 0) {
            batches[[length(batches) + 1L]] <- list(
              label = "A to B",
              source_path = plan$source_a,
              target_path = plan$target_b,
              packages = plan$packages_a_to_b
            )
          }
          if (length(plan$packages_b_to_a) > 0) {
            batches[[length(batches) + 1L]] <- list(
              label = "B to A",
              source_path = plan$source_b,
              target_path = plan$target_a,
              packages = plan$packages_b_to_a
            )
          }
        } else {
          batches <- list(list(
            label = plan$type,
            source_path = plan$source_path,
            target_path = plan$target_path,
            packages = plan$packages
          ))
        }

        total_count <- sum(vapply(batches, function(batch) length(batch$packages), integer(1)))
        failed_count <- 0L
        add_sync_log("Estimated sync time: ", estimate_sync_time(total_count), ".")
        batch_progress <- if (length(batches) == 0) 0 else 65 / length(batches)
        progress_start <- 10

        for (i in seq_along(batches)) {
          batch <- batches[[i]]
          package_preview <- paste(utils::head(batch$packages, 8), collapse = ", ")
          if (length(batch$packages) > 8) {
            package_preview <- paste0(package_preview, sprintf(", and %d more", length(batch$packages) - 8))
          }

          detail <- sprintf(
            "Installing %d package(s): %s",
            length(batch$packages),
            package_preview
          )
          set_sync_progress(progress_start + (i - 1L) * batch_progress, detail, active = TRUE)
          add_sync_log(sprintf(
            "Starting %s sync: %d package(s) from %s to %s.",
            batch$label,
            length(batch$packages),
            route_display(batch$source_path),
            route_display(batch$target_path)
          ))
          add_sync_log("Packages: ", paste(batch$packages, collapse = ", "))

          ship_result <- courieR::ship(
            source_path = batch$source_path,
            target_path = batch$target_path,
            packages = batch$packages,
            upgrade = TRUE,
            log_callback = add_sync_log,
            mode = input$transfer_mode
          )

          add_plan_log(ship_result)
          add_result_log(ship_result)

          if ("results" %in% names(ship_result) && nrow(ship_result$results) > 0) {
            failures <- ship_result$results[ship_result$results$status == "error", ]
            failed_count <- failed_count + nrow(failures)
            if (nrow(failures) > 0) {
              add_sync_log(sprintf(
                "Finished %s sync with %d failure(s): %s.",
                batch$label,
                nrow(failures),
                paste(failures$package, collapse = ", ")
              ))
            } else {
              add_sync_log(sprintf("Finished %s sync successfully.", batch$label))
            }
          } else {
            add_sync_log(sprintf("Finished %s sync.", batch$label))
          }

          set_sync_progress(progress_start + i * batch_progress, sprintf("Finished %s sync", batch$label), active = TRUE)
        }

        set_sync_progress(80, "Refreshing comparison after sync", active = TRUE)
        add_sync_log("Refreshing comparison after sync.")
        refresh_comparison(
          input$install_a,
          input$install_b,
          progress_detail = "Refreshing comparison after sync",
          pct_base = 80,
          pct_span = 18
        )
        comp_after <- comparison_data()
        remaining <- if (is.null(comp_after)) {
          NA_integer_
        } else {
          sum(comp_after[["status"]] != "same")
        }
        set_sync_progress(100, "Sync complete", active = TRUE)
        add_sync_log("Post-sync comparison refreshed: ", comparison_counts_text(comp_after), ".")
        list(count = total_count, failed = failed_count, remaining = remaining)
      }, error = function(e) {
        set_sync_progress(0, "Sync failed", active = FALSE)
        add_sync_log("Sync failed: ", e$message)
        showNotification(paste("Sync failed:", e$message), type = "error", duration = NULL)
        if (is.function(push_error)) push_error(e$message, context = "Syncing packages")
        NULL
      })

      if (!is.null(result)) {
        add_sync_log(sprintf("Sync complete. %d package(s) processed.", result$count))
        if (result$failed > 0) {
          showNotification(
            sprintf("Sync finished with %d failed package(s). See sync log.", result$failed),
            type = "warning",
            duration = NULL
          )
        } else if (!is.na(result$remaining) && result$remaining > 0) {
          showNotification(
            sprintf("Sync finished, but %d package difference(s) remain. See sync log.", result$remaining),
            type = "warning",
            duration = NULL
          )
        } else {
          showNotification(sprintf("Sync complete. %d package(s) processed; comparison refreshed.", result$count), type = "message")
        }
        set_sync_progress(100, "Sync complete", active = FALSE)
      }

      pending_sync(NULL)
    })
  })
}
