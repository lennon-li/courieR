mod_sync_ui <- function(id) {
  ns <- NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      class = "sync-sidebar",
      uiOutput(ns("detecting_msg")),
      uiOutput(ns("detected_installs")),
      hr(),
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
      actionButton(ns("compare"), "Compare", class = "btn sync-compare-btn",
        onclick = "this.disabled = true;"),
      hr(),
      div(
        class = "sync-select-block",
        tags$div(class = "sync-select-label", "Transfer mode"),
        selectInput(ns("transfer_mode"), NULL, width = "100%", selectize = FALSE, choices = c(
          "Online reinstall" = "online",
          "Offline copy" = "offline",
          "Preserve version" = "preserve"
        ), selected = "online"),
        uiOutput(ns("transfer_mode_desc"))
      ),
      div(
        class = "sync-select-block",
        tags$div(class = "sync-select-label", "Sync direction"),
        selectInput(ns("sync_direction"), NULL, width = "100%", selectize = FALSE, choices = c(
          "A → B" = "A_to_B",
          "B → A" = "B_to_A",
          "Two-way" = "full"
        ), selected = "A_to_B")
      ),
      actionButton(ns("sync_btn"), "Ship", class = "btn sync-compare-btn"),
      hr(),
      tags$div(class = "sync-select-label", "Maintenance"),
      div(
        class = "sync-restock-wrap",
        actionButton(ns("restock_a"), "Restock A from CRAN",
                     class = "btn sync-restock-btn"),
        actionButton(ns("restock_b"), "Restock B from CRAN",
                     class = "btn sync-restock-btn")
      ),
    ),
    div(
      id = "nav-progress-wrap",
      style = "display:none;",
      div(id = "nav-progress-bar")
    ),
    bslib::card(
      class = "sync-card",
      bslib::card_header("Comparison"),
      bslib::card_body(
        div(
          class = "sync-workspace",
          div(
            class = "sync-comparison-pane",
            uiOutput(ns("comparison_summary")),
            DT::dataTableOutput(ns("comparison_table"))
          ),
          div(
            class = "sync-log-pane",
            uiOutput(ns("sync_log"))
          )
        )
      )
    ),
    uiOutput(ns("delivery_receipt_panel"))
  )
}

mod_sync_server <- function(id,
                            install_a_path     = NULL,
                            install_b_path     = NULL,
                            routes_cache       = NULL,
                            push_error         = NULL,
                            comparison_out     = NULL,
                            actionable_out     = NULL,
                            sync_direction_out = NULL,
                            transfer_mode_out  = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    pending_sync     <- reactiveVal(NULL)
    routes_data      <- reactiveVal(data.frame())
    comparison_data  <- reactiveVal(NULL)
    detecting        <- reactiveVal(TRUE)
    detection_status <- reactiveVal(NULL)
    sync_log         <- reactiveVal(character())
    sync_active      <- reactiveVal(FALSE)
    sync_pct         <- reactiveVal(0)
    sync_step        <- reactiveVal("Idle")
    selected_statuses <- reactiveVal(NULL)
    last_ship_result  <- reactiveVal(NULL)

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
      sync_log(c(isolate(sync_log()), entry))
      try({
        entry_json <- jsonlite::toJSON(entry, auto_unbox = TRUE)
        shinyjs::runjs(sprintf(
          "(function(){var el=document.getElementById('%s'); if(!el) return; if(el.getAttribute('data-empty')==='true'){el.innerHTML=''; el.removeAttribute('data-empty');} var raw=%s; var s=raw.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); el.innerHTML+=(el.innerHTML?'\\n':'')+s; el.scrollTop=el.scrollHeight;})();",
          ns("sync_log_pre"),
          entry_json
        ))
      }, silent = TRUE)
      invisible(NULL)
    }

    add_sync_log_error <- function(...) {
      msg <- paste(..., collapse = "")
      display <- sprintf("%s  %s", format(Sys.time(), "%H:%M:%S"), msg)
      sync_log(c(isolate(sync_log()), paste0("[ERR] ", display)))
      try({
        display_json <- jsonlite::toJSON(display, auto_unbox = TRUE)
        shinyjs::runjs(sprintf(
          "(function(){var el=document.getElementById('%s'); if(!el) return; if(el.getAttribute('data-empty')==='true'){el.innerHTML=''; el.removeAttribute('data-empty');} var raw=%s; var s=raw.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); el.innerHTML+=(el.innerHTML?'\\n':'')+'<span class=\"sync-log-error\">'+s+'</span>'; el.scrollTop=el.scrollHeight;})();",
          ns("sync_log_pre"),
          display_json
        ))
      }, silent = TRUE)
      invisible(NULL)
    }

    set_sync_progress <- function(pct = NULL, step = NULL, active = TRUE) {
      sync_active(isTRUE(active))
      if (!is.null(pct)) sync_pct(max(0, min(100, as.numeric(pct))))
      if (!is.null(step)) sync_step(step)
      pct_val  <- if (!is.null(pct)) max(0, min(100, as.numeric(pct))) else isolate(sync_pct())
      step_val <- if (!is.null(step)) step else isolate(sync_step())
      try({
        step_json <- jsonlite::toJSON(step_val %||% "", auto_unbox = TRUE)
        shinyjs::runjs(sprintf(
          "(function(){
            var w=document.getElementById('nav-progress-wrap');
            var b=document.getElementById('nav-progress-bar');
            if(!w||!b) return;
            if(%s){
              w.style.display='block';
              b.style.width='%s%%';
            } else {
              b.style.width='100%%';
              setTimeout(function(){ w.style.display='none'; b.style.width='0%%'; }, 350);
            }
          })()",
          if (isTRUE(active)) "true" else "false",
          pct_val
        ))
      }, silent = TRUE)
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
        line <- sprintf("  - %s: %s — %s", results$package[[i]], results$status[[i]], results$message[[i]])
        if (identical(results$status[[i]], "error")) {
          add_sync_log_error(line)
        } else {
          add_sync_log(line)
        }
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

      # ~8-25 seconds per package via pak (network + compile)
      min_minutes <- ceiling(max(1, package_count * 8 / 60))
      max_minutes <- ceiling(max(min_minutes + 1, package_count * 25 / 60))

      sprintf("%d-%d minutes", min_minutes, max_minutes)
    }

    log_libpaths <- function(label, pkgs) {
      if (is.null(pkgs) || !"libpath" %in% names(pkgs) || nrow(pkgs) == 0) {
        add_sync_log(label, ": no packages found.")
        return(invisible(NULL))
      }
      libs <- unique(pkgs$libpath)
      add_sync_log(sprintf("%s: %d package(s) across %d librar%s:",
                           label, nrow(pkgs), length(libs),
                           if (length(libs) == 1) "y" else "ies"))
      for (lib in libs) add_sync_log("    ", lib)
      invisible(NULL)
    }

    refresh_comparison <- function(a_path, b_path, progress_detail = "Refreshing comparison", pct_base = 0, pct_span = 100) {
      set_sync_progress(pct_base, progress_detail, active = TRUE)
      add_sync_log(progress_detail, ".")
      add_sync_log("Installation A: ", route_display(a_path))
      add_sync_log("Installation B: ", route_display(b_path))
      set_sync_progress(pct_base + pct_span * 0.2, "Scanning first installation", active = TRUE)
      a_pkgs <- courieR::manifest(rscript_path = a_path)
      log_libpaths("Installation A library", a_pkgs)
      set_sync_progress(pct_base + pct_span * 0.55, "Scanning second installation", active = TRUE)
      b_pkgs <- courieR::manifest(rscript_path = b_path)
      log_libpaths("Installation B library", b_pkgs)
      if (identical(sort(unique(a_pkgs$libpath)), sort(unique(b_pkgs$libpath)))) {
        add_sync_log("WARNING: both installations resolve to the SAME library path. ",
                     "They share a package library (likely via R_LIBS_USER in .Renviron), ",
                     "so every package will compare as identical.")
      }
      set_sync_progress(pct_base + pct_span * 0.8, "Building comparison", active = TRUE)
      comparison_data(build_sync_comparison(a_pkgs, b_pkgs))
      set_sync_progress(pct_base + pct_span, "Comparison ready", active = TRUE)
    }

    apply_routes <- function(r) {
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
      detecting(FALSE)
    }

    load_routes <- function() {
      detecting(TRUE)
      detection_status(NULL)
      add_sync_log("Scanning for R installations...")
      tryCatch({
        r <- sort_routes(courieR::find_routes())
        apply_routes(r)
      }, error = function(e) {
        detection_status("Detection failed. See error details below.")
        add_sync_log("Detection failed: ", e$message)
        showNotification(paste("Route scan failed:", e$message), type = "error")
        if (is.function(push_error)) push_error(e$message, context = "Detecting R installations")
        detecting(FALSE)
      })
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
          class = "sync-detecting-sidebar",
          role = "status",
          tags$div(class = "sync-detecting-pulse"),
          tags$div(class = "sync-detecting-text", "Scanning for R installations…")
        ))
      }
      NULL
    })

    route_location <- function(path) {
      if (grepl("AppData", path, ignore.case = TRUE)) return("AppData")
      if (grepl("Program Files", path, ignore.case = TRUE)) return("Program Files")
      if (grepl("Documents", path, ignore.case = TRUE)) return("Documents")
      if (grepl("homebrew|Cellar", path, ignore.case = TRUE)) return("Homebrew")
      if (grepl("/opt/R/", path)) return("rig")
      if (grepl("\\.local/share/rig", path)) return("rig (user)")
      if (grepl("conda", path, ignore.case = TRUE)) return("conda")
      if (grepl("Library/Frameworks", path)) return("Framework")
      basename(dirname(dirname(path)))
    }

    output$detected_installs <- renderUI({
      if (detecting()) return(NULL)
      routes <- routes_data()
      if (nrow(routes) == 0) return(NULL)

      sel_a <- input$install_a
      sel_b <- input$install_b

      tags$div(
        class = "sidebar-installs",
        tags$div(class = "sidebar-installs-label", "Installations found:"),
        lapply(seq_len(nrow(routes)), function(i) {
          path <- routes$rscript_path[[i]]
          bucket <- if (!is.null(sel_a) && identical(path, sel_a)) "a"
                    else if (!is.null(sel_b) && identical(path, sel_b)) "b"
                    else ""
          extra_cls <- if (nzchar(bucket)) paste0("sidebar-install-", bucket) else ""
          tags$div(
            class = paste("sidebar-install-row", extra_cls),
            tags$span(class = "sidebar-install-version",
              sprintf("R %s", routes$version[[i]])),
            tags$span(class = "sidebar-install-loc",
              route_location(path))
          )
        })
      )
    })

    output$comparison_summary <- renderUI({
      comp <- comparison_data()
      if (is.null(comp) || nrow(comp) == 0) return(NULL)
      a_version <- route_version(input$install_a)
      b_version <- route_version(input$install_b)

      counts <- table(comp[["status"]])
      filter_state <- selected_statuses()
      make_chip <- function(status, label, css_extra = "") {
        n <- as.integer(counts[status])
        if (is.na(n) || n == 0) return(NULL)
        is_active <- is.null(filter_state) || status %in% filter_state
        tags$span(
          class = paste("sync-summary-chip", if (is_active) "chip-active" else "", css_extra),
          `data-status` = status,
          onclick = sprintf("courierChipClick(this, '%s', '%s')", status, ns("filter_statuses")),
          tags$strong(n), " × ", label
        )
      }

      a_lbl <- if (!is.na(a_version)) paste("newer in R", a_version) else "newer in A"
      b_lbl <- if (!is.na(b_version)) paste("newer in R", b_version) else "newer in B"
      na_lbl <- if (!is.na(a_version)) paste("not in R", a_version) else "missing from A"
      nb_lbl <- if (!is.na(b_version)) paste("not in R", b_version) else "missing from B"

      hint_ui <- if (any(comp[["status"]] != "same")) {
        tags$p(
          class = "depot-ship-hint",
          "Cherry-pick packages → ",
          tags$a(
            href    = "#",
            onclick = "navigateToDepotShip(); return false;",
            "Advanced › Depot › Ship"
          )
        )
      } else NULL

      div(
        class = "sync-summary-wrap",
        div(
          class = "sync-summary-bar",
          make_chip("same",           "identical",  "chip-same"),
          make_chip("newer-in-A",     a_lbl,        "chip-diff-a"),
          make_chip("newer-in-B",     b_lbl,        "chip-diff-b"),
          make_chip("missing-from-B", nb_lbl,       "chip-diff-a"),
          make_chip("missing-from-A", na_lbl,       "chip-diff-b")
        ),
        hint_ui
      )
    })

    format_log_entry <- function(entry) {
      if (startsWith(entry, "[ERR] ")) {
        clean <- htmltools::htmlEscape(substr(entry, 7L, nchar(entry)))
        sprintf('<span class="sync-log-error">%s</span>', clean)
      } else {
        htmltools::htmlEscape(entry)
      }
    }

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

      empty_text <- "Scanning installations… then click Compare. Activity appears here."
      tags$div(
        class = paste("sync-log", if (length(entries) == 0) "sync-log-empty" else ""),
        tags$div(
          class = "sync-log-title",
          "Log panel",
          tags$span(
            class = "sync-log-subtitle",
            if (length(entries) == 0) "Waiting for activity" else "Detection, package actions, and post-sync comparison refresh"
          )
        ),
        progress_ui,
        tags$pre(
          id = ns("sync_log_pre"),
          `data-empty` = if (length(entries) == 0) "true" else NULL,
          if (length(entries) == 0) {
            empty_text
          } else {
            HTML(paste(
              vapply(utils::tail(entries, 250), format_log_entry, character(1)),
              collapse = "\n"
            ))
          }
        )
      )
    })

    # No automatic detection on startup — the user clicks Detect (see observer
    # below), which calls load_routes() and shares the result via routes_cache.

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

    # Relabel the sync-direction choices with the actual R versions selected.
    observe({
      va <- route_version(input$install_a)
      vb <- route_version(input$install_b)
      a_lbl <- if (is.na(va)) "A" else paste0("R ", va)
      b_lbl <- if (is.na(vb)) "B" else paste0("R ", vb)
      current <- isolate(input$sync_direction)
      choices <- stats::setNames(
        c("A_to_B", "B_to_A", "full"),
        c(
          paste0(a_lbl, " → ", b_lbl),
          paste0(b_lbl, " → ", a_lbl),
          paste0("Two-way (", a_lbl, " ⇌ ", b_lbl, ")")
        )
      )
      updateSelectInput(session, "sync_direction", choices = choices,
                        selected = if (!is.null(current) && nzchar(current)) current else "A_to_B")
    })

    observe({
      if (is.function(sync_direction_out))
        sync_direction_out(input$sync_direction %||% "A_to_B")
    })
    observe({
      if (is.function(transfer_mode_out))
        transfer_mode_out(input$transfer_mode %||% "online")
    })

    # Disable sync controls when there is nothing to transfer (all packages identical).
    observe({
      comp <- comparison_data()
      all_same <- !is.null(comp) && nrow(comp) > 0 && all(comp[["status"]] == "same")
      shinyjs::toggleState("transfer_mode",  condition = !all_same)
      shinyjs::toggleState("sync_direction", condition = !all_same)
      shinyjs::toggleState("sync_btn",       condition = !all_same)
    })

    re_enable_btn <- function(input_id) {
      shinyjs::runjs(sprintf(
        "var b = document.getElementById('%s'); if (b) b.disabled = false;",
        ns(input_id)
      ))
    }
    re_enable_compare <- function() re_enable_btn("compare")

    mode_description <- function(mode) {
      switch(
        mode %||% "online",
        online   = "Reinstall each package from CRAN / GitHub / Bioconductor via pak.",
        offline  = "Copy package files directly. Packages without a valid source path are skipped.",
        preserve = "Copy files first; anything that cannot be copied is reinstalled at the same version.",
        "Packages are transferred using the selected mode."
      )
    }

    output$transfer_mode_desc <- renderUI({
      tags$div(class = "sync-mode-desc", mode_description(input$transfer_mode))
    })

    # Auto-scan on startup — no manual trigger needed.
    observeEvent(TRUE, {
      set_sync_progress(0, "Detecting R installations", active = TRUE)
      load_routes()
      if (is.function(routes_cache)) routes_cache(isolate(routes_data()))
      set_sync_progress(100, "Detection complete", active = FALSE)
    }, once = TRUE, ignoreNULL = FALSE)

    observeEvent(input$compare, {
      a_path <- input$install_a
      b_path <- input$install_b

      if (is.null(a_path) || !nzchar(a_path) || is.null(b_path) || !nzchar(b_path)) {
        re_enable_compare()
        showNotification("Select two R installations first.", type = "warning")
        return()
      }

      if (identical(a_path, b_path)) {
        re_enable_compare()
        showNotification("Choose two different R installations.", type = "warning")
        return()
      }

      if (is.function(comparison_out))  comparison_out(NULL)
      if (is.function(actionable_out))  actionable_out(0L)
      last_ship_result(NULL)

      sync_log(character())
      selected_statuses(NULL)
      add_sync_log("Starting comparison…")
      set_sync_progress(0, "Comparing installations", active = TRUE)

      tryCatch({
        refresh_comparison(a_path, b_path, progress_detail = "Starting comparison")
        comp <- comparison_data()
        diff_statuses <- c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B")
        if (!is.null(comp) && any(comp[["status"]] %in% diff_statuses)) {
          selected_statuses(diff_statuses)
        }
        if (is.function(comparison_out)) comparison_out(comparison_data())
        diff_n <- sum(comparison_data()[["status"]] != "same")
        if (is.function(actionable_out)) actionable_out(diff_n)
        set_sync_progress(100, "Comparison ready", active = FALSE)
      }, error = function(e) {
        set_sync_progress(0, "Comparison failed", active = FALSE)
        add_sync_log("Comparison failed: ", e$message)
        showNotification(paste("Comparison failed:", e$message), type = "error", duration = NULL)
        if (is.function(push_error)) push_error(e$message, context = "Comparing R libraries")
      })

      re_enable_compare()
    })

    observeEvent(input$filter_statuses, {
      vals <- input$filter_statuses
      if (is.null(vals) || length(vals) == 0) {
        selected_statuses(NULL)
      } else {
        selected_statuses(vals)
      }
    }, ignoreNULL = FALSE, ignoreInit = TRUE)

    sync_comparison <- reactive({
      comp <- comparison_data()
      filter <- selected_statuses()
      if (is.null(filter) || is.null(comp)) return(comp)
      comp[comp[["status"]] %in% filter, ]
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
      a_lbl <- if (is.na(a_version)) "A" else paste0("R ", a_version)
      b_lbl <- if (is.na(b_version)) "B" else paste0("R ", b_version)
      status_labels <- raw_status
      status_labels[raw_status == "same"]           <- "same"
      status_labels[raw_status == "newer-in-A"]     <- paste0("newer in ", a_lbl)
      status_labels[raw_status == "newer-in-B"]     <- paste0("newer in ", b_lbl)
      status_labels[raw_status == "missing-from-A"] <- paste0("not in ", a_lbl)
      status_labels[raw_status == "missing-from-B"] <- paste0("not in ", b_lbl)

      display <- data.frame(
        package = comp[["package"]],
        version_in_a = ifelse(is.na(comp[["version_in_a"]]), "not installed", comp[["version_in_a"]]),
        version_in_b = ifelse(is.na(comp[["version_in_b"]]), "not installed", comp[["version_in_b"]]),
        status = factor(status_labels),
        status_raw = raw_status,
        status_rank = match(raw_status, c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B", "same")),
        stringsAsFactors = FALSE
      )

      diff_statuses <- c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B")

      DT::datatable(
        display,
        rownames = FALSE,
        escape = TRUE,
        width = "100%",
        colnames = c(
          "Package",
          paste0("Version in ", a_lbl),
          paste0("Version in ", b_lbl),
          "Status",
          "status_raw",
          "status_rank"
        ),
        filter = "top",
        options = list(
          pageLength = 50,
          lengthMenu = c(25, 50, 100, -1),
          scrollX = FALSE,
          autoWidth = FALSE,
          dom = "rt<'sync-table-foot'lip>",
          order = list(list(5, "asc"), list(0, "asc")),
          columnDefs = list(list(targets = c(4, 5), visible = FALSE))
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
      mode_note <- mode_description(input$transfer_mode)

      if (plan$type == "full") {
        package_count <- length(plan$packages_a_to_b) + length(plan$packages_b_to_a)
      } else {
        package_count <- length(plan$packages)
      }

      showModal(modalDialog(
        title = span(style = "font-weight:800; color:#2c1e6e;", "Confirm Ship"),
        div(
          style = "padding: 0.25rem 0;",
          div(
            class = "modal-ship-pkg-count",
            if (plan$type == "full") {
              sprintf("%d + %d packages", length(plan$packages_a_to_b), length(plan$packages_b_to_a))
            } else {
              sprintf("%d package%s", package_count, if (package_count == 1) "" else "s")
            }
          ),
          div(class = "modal-ship-time", estimate_sync_time(package_count), " estimated"),
          div(class = "modal-ship-mode", tags$strong("Mode: "), mode_note)
        ),
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_sync"), "Ship", class = "btn-primary",
            style = "background: linear-gradient(90deg,#5f4ab4 0%,#8a52c8 100%); border:0; font-weight:800;")
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

      ship_start_time <- Sys.time()

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
        accumulated_results <- list()
        accumulated_plans   <- list()
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

          if (!is.null(ship_result$results) && nrow(ship_result$results) > 0)
            accumulated_results[[i]] <- ship_result$results
          if (!is.null(ship_result$plan) && nrow(ship_result$plan) > 0)
            accumulated_plans[[i]] <- ship_result$plan

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

        all_results <- if (length(accumulated_results) > 0)
          data.table::rbindlist(accumulated_results, fill = TRUE)
        else
          data.table::data.table(package = character(), status = character(), message = character())

        all_plans <- if (length(accumulated_plans) > 0)
          data.table::rbindlist(accumulated_plans, fill = TRUE)
        else
          data.table::data.table(package = character(), action = character())

        elapsed <- as.numeric(difftime(Sys.time(), ship_start_time, units = "secs"))
        last_ship_result(list(
          results     = all_results,
          plan        = all_plans,
          elapsed_sec = elapsed
        ))

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
        set_sync_progress(100, "Ship complete", active = TRUE)
        add_sync_log("Post-sync comparison refreshed: ", comparison_counts_text(comp_after), ".")
        list(count = total_count, failed = failed_count, remaining = remaining)
      }, error = function(e) {
        set_sync_progress(0, "Ship failed", active = FALSE)
        add_sync_log("Ship failed: ", e$message)
        showNotification(paste("Ship failed:", e$message), type = "error", duration = NULL)
        if (is.function(push_error)) push_error(e$message, context = "Shipping packages")
        NULL
      })

      if (!is.null(result)) {
        add_sync_log(sprintf("Ship complete. %d package(s) processed.", result$count))
        if (result$failed > 0) {
          showNotification(
            sprintf("Ship finished with %d failed package(s). See the log panel.", result$failed),
            type = "warning",
            duration = NULL
          )
        } else if (!is.na(result$remaining) && result$remaining > 0) {
          showNotification(
            sprintf("Ship finished, but %d package difference(s) remain. See the log panel.", result$remaining),
            type = "warning",
            duration = NULL
          )
        } else {
          showNotification(sprintf("Sync complete. %d package(s) processed; comparison refreshed.", result$count), type = "message")
        }
        set_sync_progress(100, "Ship complete", active = FALSE)
      }

      pending_sync(NULL)
    })

    # ── Delivery Receipt panel ────────────────────────────────────────────
    output$receipt_results_dt <- DT::renderDataTable({
      res <- last_ship_result()
      if (is.null(res) || is.null(res$results) || nrow(res$results) == 0)
        return(DT::datatable(data.frame(), options = list(dom = "t"), rownames = FALSE))
      DT::datatable(res$results,
        options = list(pageLength = 15, dom = "tip"), rownames = FALSE)
    })

    output$receipt_plan_dt <- DT::renderDataTable({
      res <- last_ship_result()
      if (is.null(res) || is.null(res$plan) || nrow(res$plan) == 0)
        return(DT::datatable(data.frame(), options = list(dom = "t"), rownames = FALSE))
      plan <- res$plan
      cols <- intersect(c("package", "version.x", "action", "source", "pak_spec"),
                        names(plan))
      DT::datatable(plan[, cols, with = FALSE],
        options = list(pageLength = 15, dom = "tip"), rownames = FALSE)
    })

    output$delivery_receipt_panel <- renderUI({
      res <- last_ship_result()
      if (is.null(res)) return(NULL)

      results <- res$results
      elapsed <- res$elapsed_sec %||% 0

      n_total <- if (!is.null(results)) nrow(results) else 0L
      n_ok    <- if (!is.null(results)) sum(results$status == "success") else 0L
      n_err   <- n_total - n_ok
      theme   <- if (n_total == 0L) "secondary" else if (n_err == 0) "success" else if (n_ok == 0) "danger" else "warning"

      bslib::card(
        class = "sync-receipt-card",
        bslib::card_header(
          class = "sync-receipt-header",
          tags$span("Delivery Receipt"),
          tags$span(class = "sync-receipt-elapsed",
                    sprintf("%.1fs", elapsed))
        ),
        bslib::card_body(
          bslib::value_box(
            "Result",
            sprintf("%d / %d packages delivered", n_ok, n_total),
            theme = theme
          ),
          if (n_total > 0) {
            plan <- res$plan
            bslib::navset_card_tab(
              bslib::nav_panel("Results",
                DT::dataTableOutput(ns("receipt_results_dt"))
              ),
              bslib::nav_panel("Plan",
                if (!is.null(plan) && nrow(plan) > 0) {
                  DT::dataTableOutput(ns("receipt_plan_dt"))
                } else {
                  tags$p("No plan details available.")
                }
              )
            )
          }
        )
      )
    })

    # ── Restock ───────────────────────────────────────────────────────────
    restock_pending <- reactiveVal(NULL)

    do_restock <- function(path_fn, label) {
      path <- if (is.function(path_fn)) path_fn() else path_fn
      if (is.null(path) || !nzchar(path)) {
        showNotification("Select an installation in the Dispatch tab first.",
                         type = "warning")
        return()
      }
      pkgs <- tryCatch(
        courieR::manifest(rscript_path = path),
        error = function(e) {
          showNotification(paste("Scan failed:", e$message), type = "error")
          if (is.function(push_error))
            push_error(e$message, context = "Scanning packages for restock")
          NULL
        }
      )
      if (is.null(pkgs)) return()
      pkgs <- pkgs[is.na(pkgs$priority) |
                     !(pkgs$priority %in% c("base", "recommended")), ]
      cran_mask <- !is.na(pkgs$source) & pkgs$source == "CRAN"
      cran_pkgs <- pkgs$package[cran_mask]
      non_cran  <- pkgs[!cran_mask, ]

      restock_pending(list(path = path, label = label, cran_pkgs = cran_pkgs))

      warning_ui <- if (nrow(non_cran) > 0) {
        src_raw <- ifelse(
          is.na(non_cran$source) | non_cran$source == "unknown",
          "unknown / other", non_cran$source
        )
        src_tbl   <- sort(table(src_raw), decreasing = TRUE)
        src_items <- mapply(
          function(n, s) tags$li(sprintf("%d package(s) from %s", n, s)),
          as.integer(src_tbl), names(src_tbl), SIMPLIFY = FALSE
        )
        preview <- paste(head(non_cran$package, 8), collapse = ", ")
        if (nrow(non_cran) > 8)
          preview <- paste0(preview, sprintf(", … +%d more", nrow(non_cran) - 8))
        tags$div(
          class = "update-modal-warning",
          tags$p(tags$strong(sprintf(
            "%d package(s) will be skipped — not from CRAN:", nrow(non_cran)
          ))),
          tags$ul(class = "update-modal-warning-list", src_items),
          tags$p(class = "update-modal-warning-pkgs", preview),
          tags$p(class = "update-modal-warning-note",
                 "GitHub, Bioconductor, and unknown-source packages must be updated manually.")
        )
      } else NULL

      showModal(modalDialog(
        title = paste0("Restock Installation ", label, " from CRAN"),
        if (length(cran_pkgs) > 0) {
          tags$p(sprintf("%d CRAN package(s) will be upgraded to their latest versions.",
                         length(cran_pkgs)))
        } else {
          tags$p("No CRAN packages found to update.")
        },
        warning_ui,
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          if (length(cran_pkgs) > 0) {
            actionButton(ns("confirm_restock"), "Restock", class = "btn btn-primary")
          } else {
            tags$span(class = "text-muted small", "Nothing to update.")
          }
        )
      ))
    }

    observeEvent(input$restock_a, { do_restock(install_a_path, "A") })
    observeEvent(input$restock_b, { do_restock(install_b_path, "B") })

    observeEvent(input$confirm_restock, {
      plan <- restock_pending()
      removeModal()
      if (is.null(plan) || length(plan$cran_pkgs) == 0) return()

      lib_res <- processx::run(
        plan$path, c("--vanilla", "-e", "cat(.libPaths()[1])"),
        error_on_status = FALSE
      )
      tgt_lib <- trimws(lib_res$stdout)
      if (lib_res$status != 0 || !nzchar(tgt_lib)) {
        showNotification("Could not determine library path.", type = "error")
        return()
      }

      specs <- plan$cran_pkgs
      ok <- tryCatch({
        callr::r(
          func = function(specs, lib) {
            pak::pkg_install(specs, lib = lib, ask = FALSE, upgrade = TRUE)
          },
          args = list(specs = specs, lib = tgt_lib),
          show = FALSE
        )
        TRUE
      }, error = function(e) {
        showNotification(paste("Restock failed:", e$message),
                         type = "error", duration = NULL)
        if (is.function(push_error))
          push_error(e$message, context = "Restocking packages")
        FALSE
      })

      restock_pending(NULL)
      if (ok) {
        showNotification(
          sprintf("Restocked %d package(s) in installation %s.",
                  length(specs), plan$label),
          type = "message"
        )
      }
    })
  })
}
