# Helper: build ship batches from per-package action assignments.
# Returns a list of batch specs: list(pkgs, src, tgt, mode).
#
# actions   named character vector: package -> "skip" | "ship" | "online"
# comp      data.frame/data.table with columns: package, status
# direction one of "source_to_target", "target_to_source", "full"
# from_path Rscript path for source installation
# to_path   Rscript path for target installation
.build_depot_ship_batches <- function(actions, comp, direction, from_path, to_path) {
  non_skip <- names(actions)[actions != "skip"]
  if (length(non_skip) == 0L) return(list())

  status_map <- stats::setNames(
    comp[["status"]][match(non_skip, comp[["package"]])],
    non_skip
  )

  if (direction == "full") {
    src_to_tgt <- non_skip[status_map[non_skip] %in% c("missing-from-target", "newer-in-source")]
    tgt_to_src <- non_skip[status_map[non_skip] %in% c("missing-from-source", "newer-in-target")]
  } else if (direction == "source_to_target") {
    src_to_tgt <- non_skip
    tgt_to_src <- character(0)
  } else {
    src_to_tgt <- character(0)
    tgt_to_src <- non_skip
  }

  batches <- list()

  add_batch <- function(pkgs, src, tgt, mode) {
    if (length(pkgs) == 0L) return()
    batches[[length(batches) + 1L]] <<- list(pkgs = pkgs, src = src,
                                              tgt = tgt, mode = mode)
  }

  add_batch(src_to_tgt[actions[src_to_tgt] == "online"], from_path, to_path, "online")
  add_batch(src_to_tgt[actions[src_to_tgt] == "ship"],   from_path, to_path, "offline")
  add_batch(tgt_to_src[actions[tgt_to_src] == "online"], to_path, from_path, "online")
  add_batch(tgt_to_src[actions[tgt_to_src] == "ship"],   to_path, from_path, "offline")

  batches
}

mod_depot_ship_ui <- function(id) {
  ns <- NS(id)
  div(
    class = "depot-ship-pane",

    # Small JS helpers: checkbox select-all + elapsed timer.
    tags$script(HTML(sprintf(
      "function courierDepotSelectAll(tableId, checked){
         var root = document.getElementById(tableId);
         if(!root) return;
         var cbs = root.querySelectorAll('.depot-ship-cb');
         cbs.forEach(function(c){ c.checked = checked; });
         if(cbs.length){ cbs[0].dispatchEvent(new Event('change', {bubbles:true})); }
       }
       (function(){
         var _iv = null, _t0 = null;
         window.courierStartDepotTimer = function() {
           var el = document.getElementById('%s');
           if (!el) return;
           _t0 = Date.now();
           el.style.display = 'inline';
           el.textContent = '0s elapsed';
           clearInterval(_iv);
           _iv = setInterval(function() {
             var s = Math.floor((Date.now() - _t0) / 1000);
             var m = Math.floor(s / 60);
             el.textContent = (m > 0 ? m + 'm ' + (s %% 60) + 's' : s + 's') + ' elapsed';
           }, 1000);
         };
         $(document).on('shiny:idle', function() {
           if (_iv) { clearInterval(_iv); _iv = null; }
           var el = document.getElementById('%s');
           if (el) el.style.display = 'none';
           if (window.courierDepotHero) window.courierDepotHero.stop();
           // Safety net for the global busy lock: idle means no observer is
           // running, so no operation can still be in flight.
           document.body.classList.remove('app-busy');
         });
       })();
       // Live shipping hero panel: shown while the synchronous ship runs.
       // The server pushes status into it via shinyjs::runjs because normal
       // outputs cannot re-render until the blocking observer finishes.
       (function(){
         var heroId = '%s', _iv = null, _t0 = null;
         function el(suffix){ return document.getElementById(heroId + suffix); }
         function fmt(s){
           var m = Math.floor(s / 60);
           return m > 0 ? (m + 'm ' + (s %% 60) + 's') : (s + 's');
         }
         window.courierDepotHero = {
           start: function(total, est){
             var h = el(''); if (!h) return;
             h.style.display = 'block';
             h.innerHTML =
               '<div class=\"depot-hero-kicker\">Shipping in progress</div>' +
               '<div class=\"depot-hero-main\"><span id=\"' + heroId + '_count\">0</span> / ' + total + ' delivered</div>' +
               '<div class=\"depot-hero-pkg\" id=\"' + heroId + '_pkg\">Preparing shipment…</div>' +
               '<div class=\"depot-hero-meta\"><span id=\"' + heroId + '_timer\">0s</span> elapsed · estimated ' + est + '</div>';
             _t0 = Date.now();
             clearInterval(_iv);
             _iv = setInterval(function(){
               var t = el('_timer');
               if (t) t.textContent = fmt(Math.floor((Date.now() - _t0) / 1000));
             }, 1000);
           },
           status: function(txt){ var p = el('_pkg'); if (p) p.textContent = txt; },
           count:  function(k){ var c = el('_count'); if (c) c.textContent = k; },
           stop:   function(){
             clearInterval(_iv); _iv = null;
             var h = el(''); if (h) h.style.display = 'none';
           }
         };
       })();",
      ns("depot_timer"), ns("depot_timer"), ns("depot_hero")
    ))),

    # Filter chips span the full width above the workspace
    uiOutput(ns("route_summary")),
    uiOutput(ns("ship_chips")),

    div(
      class = "sync-workspace",

      # Left pane — toolbar + table + plan summary + ship button
      div(
        class = "sync-comparison-pane",
        div(
          class = "depot-ship-toolbar",
          textInput(ns("ship_search"), label = NULL,
                    placeholder = "Search packages…", width = "220px"),
          div(
            class = "depot-ship-bulk",
            tags$span(class = "depot-ship-mode-label", "How to ship:"),
            selectInput(
              ns("ship_mode"), label = NULL,
              choices  = c("Install online" = "online", "Ship as-is" = "ship"),
              selected = "online",
              selectize = FALSE,
              width = "150px"
            ),
            actionButton(ns("select_all"), "Select all shown",
                         class = "btn btn-sm depot-select-all-btn",
                         onclick = sprintf("courierDepotSelectAll('%s', true)", ns("ship_table"))),
            actionButton(ns("clear_sel"), "Clear",
                         class = "btn btn-sm depot-clear-sel-btn",
                         onclick = sprintf("courierDepotSelectAll('%s', false)", ns("ship_table")))
          )
        ),
        DT::dataTableOutput(ns("ship_table")),
        uiOutput(ns("plan_summary")),
        div(
          class = "depot-ship-footer",
          actionButton(ns("depot_ship_btn"), "Ship",
                       class = "btn sync-compare-btn depot-ship-execute-btn",
                       onclick = "if(window.courierAppBusy) courierAppBusy(true); if(window.courierStartDepotTimer) window.courierStartDepotTimer();"),
          tags$span(id = ns("depot_timer"), class = "depot-ship-timer", style = "display:none;")
        )
      ),

      # Right pane — live hero (during ship) + log
      div(
        class = "sync-log-pane",
        tags$div(id = ns("depot_hero"), class = "depot-hero", style = "display:none;"),
        uiOutput(ns("depot_log_ui"))
      )
    )
  )
}

mod_depot_ship_server <- function(id,
                                   comparison_rv     = NULL,
                                   from_r_path       = NULL,
                                   to_r_path         = NULL,
                                   sync_direction_rv  = NULL,
                                   transfer_mode_rv   = NULL,
                                   push_error        = NULL,
                                   incoming_search   = NULL,
                                   refresh_after_ship = NULL,
                                   route_label       = NULL,
                                   shared_scans      = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Reactive state ─────────────────────────────────────────────────────
    # The checked rows ARE the shipment: input$ship_cb_rows holds 1-based row
    # indices into visible_comp(). The "How to ship" dropdown (input$ship_mode)
    # decides the mode applied to that checked set.
    ship_filter_status   <- reactiveVal("missing-from-target")
    depot_ship_result    <- reactiveVal(NULL)
    shipping_in_progress <- reactiveVal(FALSE)
    awaiting_refresh     <- reactiveVal(FALSE)
    depot_log <- reactiveVal(character(0))
    # Mirrors mod_sync's add_sync_log: besides the reactiveVal (which cannot
    # re-render while the synchronous ship loop blocks the event loop), each
    # line is echoed to the R console via message() and pushed straight into
    # the DOM with shinyjs::runjs so the log pane updates in real time.
    depot_log_append <- function(...) {
      msg <- paste0(...)
      entry <- sprintf("%s  %s", format(Sys.time(), "%H:%M:%S"), msg)
      depot_log(utils::tail(c(isolate(depot_log()), entry), 1000L))
      message(entry)
      try({
        entry_json <- jsonlite::toJSON(entry, auto_unbox = TRUE)
        shinyjs::runjs(sprintf(
          "(function(){var el=document.getElementById('%s'); if(!el) return; var raw=%s; var s=raw.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); if(el.getAttribute('data-empty')==='true'){el.removeAttribute('data-empty');el.innerHTML=s;}else{el.innerHTML=s+(el.innerHTML?'\\n'+el.innerHTML:'');} el.scrollTop=0;})();",
          ns("depot_log_pre"),
          entry_json
        ))
      }, silent = TRUE)
      invisible(NULL)
    }

    get_direction <- function() {
      if (is.function(sync_direction_rv)) sync_direction_rv() else "source_to_target"
    }
    get_mode <- function() {
      if (is.function(transfer_mode_rv)) transfer_mode_rv() else "online"
    }
    get_comp <- function() {
      if (is.function(comparison_rv)) comparison_rv() else NULL
    }

    install_label <- function(path) {
      if (is.null(path) || length(path) == 0L || is.na(path) || !nzchar(path)) {
        return("not selected")
      }
      paste0(basename(dirname(dirname(path))), " · ", path)
    }

    # Ship button reflects the checked-row count: disabled with 0 selected or
    # while a ship is running, and its label shows the count ("Ship 3 selected").
    observe({
      n           <- length(input$ship_cb_rows)
      in_progress <- shipping_in_progress()
      enabled     <- !in_progress && n > 0L
      label       <- if (n > 0L) sprintf("Ship %d selected", n) else "Ship"
      shinyjs::runjs(sprintf(
        "var b=document.getElementById('%s'); if(b){ b.disabled=%s; b.textContent=%s; }",
        ns("depot_ship_btn"),
        if (enabled) "false" else "true",
        jsonlite::toJSON(label, auto_unbox = TRUE)
      ))
    })

    # ── Defaults when comparison changes ────────────────────────────────────
    # Default to packages absent from the target only. Users can click the chips
    # above the table to add newer/reverse/same statuses when they need a wider
    # view. Selection starts empty so the user checks exactly what they want.
    observeEvent(get_comp(), {
      comp <- get_comp()
      if (is.null(comp) || nrow(comp) == 0) return()
      if (isTRUE(awaiting_refresh())) {
        awaiting_refresh(FALSE)
        depot_log_append("Comparison refreshed - the table now reflects the delivered packages.")
      }
      ship_filter_status("missing-from-target")
      depot_ship_result(NULL)
      mode_default <- switch(get_mode(), offline = "ship", preserve = "ship", "online")
      updateSelectInput(session, "ship_mode", selected = mode_default)
    }, ignoreNULL = FALSE)

    # Prefer the detection-derived label (version, location AND library path)
    # over the bare executable path; the full path stays in the tooltip.
    node_label <- function(path) {
      rich <- if (is.function(route_label)) route_label(path) else NULL
      rich %||% install_label(path)
    }

    output$route_summary <- renderUI({
      from <- if (is.function(from_r_path)) from_r_path() else NULL
      to   <- if (is.function(to_r_path))   to_r_path()   else NULL
      div(
        class = "depot-route-summary",
        div(
          class = "depot-route-node depot-route-source",
          tags$span(class = "depot-route-kicker", "Source"),
          tags$span(class = "depot-route-path", title = from %||% "", node_label(from))
        ),
        tags$span(class = "depot-route-arrow", "\u2192"),
        div(
          class = "depot-route-node depot-route-target",
          tags$span(class = "depot-route-kicker", "Target"),
          tags$span(class = "depot-route-path", title = to %||% "", node_label(to))
        )
      )
    })

    # ── Pre-populate search from Browse "View in Ship" ──────────────────────
    if (!is.null(incoming_search)) {
      observeEvent(incoming_search(), {
        val <- incoming_search()
        if (!is.null(val) && nzchar(val)) {
          updateTextInput(session, "ship_search", value = val)
        }
      }, ignoreNULL = TRUE)
    }

    # ── Chip filters ───────────────────────────────────────────────────────
    output$ship_chips <- renderUI({
      comp <- get_comp()
      if (is.null(comp)) return(NULL)
      counts       <- table(comp[["status"]])
      filter_state <- ship_filter_status()

      make_chip <- function(status, label, css_extra = "") {
        n <- as.integer(counts[status])
        if (is.na(n) || n == 0L) return(NULL)
        is_active <- is.null(filter_state) || status %in% filter_state
        tags$span(
          class = paste("sync-summary-chip",
                        if (is_active) "chip-active" else "", css_extra),
          `data-status` = status,
          onclick = sprintf("courierChipClick(this,'%s','%s')",
                            status, ns("depot_chip_filter")),
          tags$strong(n), " × ", label
        )
      }
      div(
        class = "sync-summary-bar",
        make_chip("same",           "identical",        "chip-same"),
        make_chip("newer-in-source",     "newer in source",  "chip-diff-a"),
        make_chip("newer-in-target",     "newer in target",  "chip-diff-b"),
        make_chip("missing-from-target", "not in target",    "chip-diff-a"),
        make_chip("missing-from-source", "not in source",    "chip-diff-b")
      )
    })

    observeEvent(input$depot_chip_filter, {
      vals <- input$depot_chip_filter
      ship_filter_status(if (is.null(vals) || length(vals) == 0L) NULL else vals)
    }, ignoreNULL = FALSE, ignoreInit = TRUE)

    # ── Filtered package list (chip + search) ──────────────────────────────
    visible_comp <- reactive({
      comp <- get_comp()
      if (is.null(comp)) return(NULL)
      filter <- ship_filter_status()
      out <- if (is.null(filter)) comp else comp[comp[["status"]] %in% filter, ]
      search <- input$ship_search
      if (!is.null(search) && nzchar(trimws(search))) {
        out <- out[grepl(trimws(search), out[["package"]], ignore.case = TRUE), ]
      }
      out
    })

    # ── Table ──────────────────────────────────────────────────────────────
    empty_ship_dt <- function() {
      DT::datatable(
        data.frame(` ` = character(), Package = character(),
                   Source = character(), Target = character(),
                   Status = character(),
                   check.names = FALSE),
        rownames  = FALSE,
        selection = "none",
        escape    = FALSE,
        options   = list(dom = "t", pageLength = -1)
      )
    }

    output$ship_table <- DT::renderDataTable({
      visible <- visible_comp()
      if (is.null(visible) || nrow(visible) == 0L)
        return(empty_ship_dt())

      pkgs <- visible[["package"]]
      cbs  <- vapply(seq_along(pkgs), function(i)
        sprintf('<input type="checkbox" class="depot-ship-cb" data-rowidx="%d">', i),
        character(1))

      display <- data.frame(
        ` `     = cbs,
        Package = pkgs,
        Source  = ifelse(is.na(visible[["version_in_source"]]),
                         "not installed", visible[["version_in_source"]]),
        Target  = ifelse(is.na(visible[["version_in_target"]]),
                         "not installed", visible[["version_in_target"]]),
        Status  = visible[["status"]],
        check.names = FALSE,
        stringsAsFactors = FALSE
      )

      cb_input <- ns("ship_cb_rows")

      DT::datatable(
        display,
        rownames  = FALSE,
        selection = "none",
        escape    = FALSE,
        options   = list(
          dom        = "t",
          pageLength = -1,
          scrollY    = "600px",
          scrollCollapse = TRUE,
          columnDefs = list(list(
            targets   = 0,
            orderable = FALSE,
            width     = "30px",
            className = "dt-center"
          )),
          drawCallback = DT::JS(sprintf(
            'function(settings) {
               var inputId = "%s";
               var tbl = settings.nTable;
               Shiny.setInputValue(inputId, null, {priority: "event"});
               $(tbl).off("change.cbsel").on("change.cbsel", ".depot-ship-cb", function() {
                 var rows = [];
                 $(tbl).find(".depot-ship-cb:checked").each(function() {
                   rows.push(parseInt($(this).attr("data-rowidx")));
                 });
                 Shiny.setInputValue(inputId, rows.length ? rows : null, {priority: "event"});
               });
             }',
            cb_input
          ))
        )
      ) |>
        DT::formatStyle(
          "Status",
          backgroundColor = DT::styleEqual(
            c("same",    "missing-from-target", "missing-from-source", "newer-in-source", "newer-in-target"),
            c("#ffffff", "#fff6ef",        "#eefafb",        "#fff4ea",    "#edf8fb")
          )
        )
    })

    # ── Plan summary ───────────────────────────────────────────────────────
    output$plan_summary <- renderUI({
      comp <- get_comp()
      if (is.null(comp)) return(NULL)
      in_progress <- shipping_in_progress()
      if (in_progress) {
        return(div(
          class = "depot-ship-summary depot-ship-summary-busy",
          tags$span(class = "sync-detecting-spinner", ""),
          tags$span("Shipping in progress…")
        ))
      }
      n    <- length(input$ship_cb_rows)
      mode <- input$ship_mode %||% "online"
      mode_label <- if (identical(mode, "ship")) "ship as-is" else "install online"
      if (n == 0L) {
        return(div(
          class = "depot-ship-summary depot-ship-summary-empty",
          tags$span("Check packages to ship, then press Ship.")
        ))
      }
      # Estimated time for the current selection, from per-machine calibrated
      # rates (every completed ship updates them).
      est_text <- tryCatch({
        visible <- visible_comp()
        sel     <- visible[["package"]][input$ship_cb_rows]
        dir     <- get_direction()
        repo_col <- if (identical(dir, "target_to_source")) "repo_in_target" else "repo_in_source"
        repo <- if (!is.null(visible) && repo_col %in% names(visible)) {
          visible[[repo_col]][match(sel, visible[["package"]])]
        } else {
          rep(NA_character_, length(sel))
        }
        est <- if (identical(mode, "ship")) {
          courieR:::estimate_ship_secs(n_copy = length(sel))
        } else {
          resolvable <- !is.na(repo) & repo %in% c("CRAN", "Bioconductor", "GitHub")
          courieR:::estimate_ship_secs(
            n_copy   = sum(!resolvable),
            n_binary = sum(resolvable & repo == "CRAN"),
            n_source = sum(resolvable & repo %in% c("Bioconductor", "GitHub"))
          )
        }
        est$text
      }, error = function(e) NULL)
      div(
        class = "depot-ship-summary",
        tags$span(class = if (identical(mode, "ship")) "depot-summary-ship" else "depot-summary-online",
                  sprintf("%d package(s) selected — %s", n, mode_label)),
        if (!is.null(est_text)) {
          tags$span(class = "depot-summary-est", sprintf("estimated time: %s", est_text))
        }
      )
    })

    # ── Ship button ────────────────────────────────────────────────────────
    observeEvent(input$depot_ship_btn, {
      if (isTRUE(shipping_in_progress())) return()

      comp    <- isolate(get_comp())
      visible <- isolate(visible_comp())
      sel_idx <- isolate(input$ship_cb_rows)
      mode    <- isolate(input$ship_mode) %||% "online"
      from    <- if (is.function(from_r_path)) isolate(from_r_path()) else NULL
      to      <- if (is.function(to_r_path))   isolate(to_r_path())   else NULL
      dir     <- isolate(get_direction())

      if (is.null(comp) || is.null(from) || is.null(to)) {
        showNotification("Run Compare in Dispatch first, then return here to ship.",
                         type = "warning", duration = 8)
        return()
      }

      if (is.null(sel_idx) || length(sel_idx) == 0L || is.null(visible)) {
        showNotification("Check at least one package to ship.", type = "warning")
        return()
      }

      # The checked rows are the shipment. Build the per-package action vector
      # ship() expects: selected packages get the chosen mode, everything else
      # is skipped. Batch routing (direction, online vs offline) is unchanged.
      selected_pkgs        <- visible[["package"]][sel_idx]
      actions              <- rep("skip", nrow(comp))
      names(actions)       <- comp[["package"]]
      actions[selected_pkgs] <- mode

      batches <- .build_depot_ship_batches(actions, comp, dir, from, to)
      if (length(batches) == 0L) {
        showNotification("No packages are queued to ship.", type = "warning")
        return()
      }

      total <- sum(sapply(batches, function(b) length(b$pkgs)))
      depot_ship_result(NULL)
      depot_log(character(0))
      shipping_in_progress(TRUE)
      on.exit(shipping_in_progress(FALSE), add = TRUE)
      start <- Sys.time()

      depot_log_append("─────── Ship ───────")
      for (b in batches) {
        pkg_preview <- paste(utils::head(b$pkgs, 6), collapse = ", ")
        if (length(b$pkgs) > 6)
          pkg_preview <- paste0(pkg_preview, sprintf(", +%d more", length(b$pkgs) - 6))
        depot_log_append(sprintf("Shipping %d package(s) [%s]: %s", length(b$pkgs), b$mode, pkg_preview))
      }
      depot_log_append("Tip: real-time pak output streams to the R console — monitor there while this runs.")

      # ── Estimated time + live hero panel ────────────────────────────────
      # Categorise the shipment by route, estimate with per-machine calibrated
      # rates, and light up the hero panel; ship_log_cb keeps it updated with
      # the package currently in flight while the observer blocks the UI.
      est <- local({
        repo_col <- if (identical(dir, "target_to_source")) "repo_in_target" else "repo_in_source"
        repo <- if (repo_col %in% names(comp)) {
          comp[[repo_col]][match(selected_pkgs, comp[["package"]])]
        } else {
          rep(NA_character_, length(selected_pkgs))
        }
        if (identical(mode, "ship")) {
          courieR:::estimate_ship_secs(n_copy = length(selected_pkgs))
        } else {
          resolvable <- !is.na(repo) & repo %in% c("CRAN", "Bioconductor", "GitHub")
          courieR:::estimate_ship_secs(
            n_copy   = sum(!resolvable),
            n_binary = sum(resolvable & repo == "CRAN"),
            n_source = sum(resolvable & repo %in% c("Bioconductor", "GitHub"))
          )
        }
      })
      depot_log_append(sprintf("Estimated time: %s (calibrates from each completed ship).", est$text))

      hero_js <- function(fn, arg = NULL) {
        arg_js <- if (is.null(arg)) "" else jsonlite::toJSON(arg, auto_unbox = TRUE)
        try(shinyjs::runjs(sprintf(
          "if(window.courierDepotHero) window.courierDepotHero.%s(%s);", fn, arg_js
        )), silent = TRUE)
      }
      try(shinyjs::runjs(sprintf(
        "if(window.courierDepotHero) window.courierDepotHero.start(%d, %s);",
        total, jsonlite::toJSON(est$text, auto_unbox = TRUE)
      )), silent = TRUE)

      delivered <- 0L
      ship_log_cb <- function(msg) {
        depot_log_append(msg)
        m <- regmatches(msg, regexec("^\\[(\\d+)/(\\d+)\\] (\\S+) - copying", msg))[[1]]
        if (length(m) == 4L) {
          hero_js("status", sprintf("Copying %s (%s/%s) ...", m[[4]], m[[2]], m[[3]]))
          return(invisible(NULL))
        }
        m <- regmatches(msg, regexec("^\\[ok\\] (\\S+) - copied", msg))[[1]]
        if (length(m) == 2L) {
          delivered <<- delivered + 1L
          hero_js("count", delivered)
          hero_js("status", sprintf("%s delivered", m[[2]]))
          return(invisible(NULL))
        }
        if (grepl("^Reinstalling \\d+ package", msg)) {
          hero_js("status", "Installing online via pak - live output in the R console ...")
        } else if (grepl("^pak subprocess finished successfully", msg)) {
          hero_js("status", "pak install finished; verifying target library ...")
        }
        invisible(NULL)
      }

      showNotification(
        sprintf("Shipping %d package(s)… watch the R console for real-time progress.", total),
        type = "message", duration = NULL, id = "depot-ship-busy"
      )

      all_results <- list()
      all_plans   <- list()

      # One library scan per installation, served from the app-wide shared
      # cache: a ship right after Compare reuses the Compare scans and spawns
      # NO scan subprocesses (scans are the slowest step on some machines).
      # Installing into a target invalidates its cached scan.
      lib_scans <- list()  # local fallback when no shared cache is provided
      get_scan <- function(path) {
        m <- if (!is.null(shared_scans)) {
          shared_scans$get(path, log = depot_log_append)
        } else if (!is.null(lib_scans[[path]])) {
          lib_scans[[path]]
        } else {
          depot_log_append(sprintf("Scanning library of %s ...", path))
          t0 <- Sys.time()
          m_local <- courieR::manifest(rscript_path = path, format = "data.table",
                                       timeout_sec = 300L)
          if (!isTRUE(attr(m_local, "timed_out"))) {
            lib_scans[[path]] <<- m_local
            depot_log_append(sprintf(
              "Scan complete: %d package(s) (%.1fs).", nrow(m_local),
              as.numeric(difftime(Sys.time(), t0, units = "secs"))
            ))
          }
          m_local
        }
        # A timed-out scan is an empty table; shipping against it would plan
        # to reinstall everything. Fail the ship instead.
        if (isTRUE(attr(m, "timed_out"))) {
          stop(sprintf("Library scan of %s timed out - retry, or check that this R installation can start.", path))
        }
        m
      }
      invalidate_scan <- function(path) {
        if (!is.null(shared_scans)) shared_scans$invalidate(path)
        lib_scans[[path]] <<- NULL
      }

      ok <- tryCatch({
        for (i in seq_along(batches)) {
          b <- batches[[i]]
          batch_t0 <- Sys.time()
          res <- courieR::ship(
            source_path  = b$src,
            target_path  = b$tgt,
            packages     = b$pkgs,
            # FALSE still installs/upgrades the *selected* packages (named pak
            # specs always resolve to the latest compatible version); TRUE
            # would additionally upgrade their entire dependency trees, which
            # turns a one-package ship into a long multi-package job.
            upgrade      = FALSE,
            mode         = b$mode,
            log_callback = ship_log_cb,
            source_pkgs  = get_scan(b$src),
            target_pkgs  = get_scan(b$tgt)
          )
          invalidate_scan(b$tgt)
          # Calibrate the per-package time estimate from what really happened
          # on this machine (offline/preserve batches are pure copies; online
          # batches are predominantly pak installs).
          batch_secs <- as.numeric(difftime(Sys.time(), batch_t0, units = "secs"))
          n_b <- length(b$pkgs)
          if (n_b > 0 && batch_secs > 0) {
            route <- if (b$mode %in% c("offline", "preserve")) "copy" else "binary"
            try(courieR:::record_ship_rate(route, batch_secs / n_b), silent = TRUE)
          }
          if (!is.null(res$results) && nrow(res$results) > 0L)
            all_results[[i]] <- res$results
          if (!is.null(res$plan) && nrow(res$plan) > 0L)
            all_plans[[i]] <- res$plan
          # Authoritative delivered count (pak successes are only known here).
          delivered <- sum(vapply(
            all_results, function(r) sum(r$status == "success"), integer(1)
          ))
          hero_js("count", delivered)
          depot_log_append(sprintf("Batch complete: %d package(s) [%s] → %s",
                                   length(b$pkgs), b$mode,
                                   basename(dirname(dirname(b$tgt)))))
        }
        TRUE
      }, error = function(e) {
        depot_log_append("[ERR] ", e$message)
        showNotification(paste("Ship failed:", e$message),
                         type = "error", duration = NULL)
        if (is.function(push_error))
          push_error(e$message, context = "Depot Ship execution")
        FALSE
      })

      removeNotification("depot-ship-busy")

      elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))

      combined_results <- if (length(all_results) > 0L)
        data.table::rbindlist(all_results, fill = TRUE)
      else
        data.table::data.table(package = character(),
                               status = character(), message = character())

      combined_plans <- if (length(all_plans) > 0L)
        data.table::rbindlist(all_plans, fill = TRUE)
      else
        data.table::data.table(package = character(), action = character())

      if (ok) {
        n_done <- nrow(combined_results)
        if (n_done > 0L) {
          ok_pkgs   <- combined_results$package[combined_results$status == "success"]
          fail_pkgs <- combined_results$package[combined_results$status != "success"]
          if (length(ok_pkgs) > 0L) {
            preview <- paste(utils::head(ok_pkgs, 8), collapse = ", ")
            if (length(ok_pkgs) > 8)
              preview <- paste0(preview, sprintf(", +%d more", length(ok_pkgs) - 8))
            depot_log_append(sprintf("Delivered: %s", preview))
          }
          if (length(fail_pkgs) > 0L)
            depot_log_append(sprintf("[ERR] Failed: %s", paste(fail_pkgs, collapse = ", ")))
          depot_log_append(sprintf("─── Done: %d/%d delivered in %.0fs ───",
                                   length(ok_pkgs), n_done, elapsed))
        } else {
          depot_log_append(sprintf("─── Done: %d package(s) in %.0fs ───", total, elapsed))
        }
      }

      depot_ship_result(list(
        results     = combined_results,
        plan        = combined_plans,
        elapsed_sec = elapsed,
        ok          = ok
      ))

      if (ok) {
        showNotification(
          sprintf("Ship complete — %d package(s) processed in %.0fs.", total, elapsed),
          type = "message", duration = 10
        )
        if (is.function(refresh_after_ship)) {
          depot_log_append("Refreshing comparison tables (rescanning the shipped-into library) ...")
          awaiting_refresh(TRUE)
          # Only the shipped-into libraries changed; the shared scan cache
          # still holds everything else, so the refresh re-scans the minimum.
          changed_tgts <- unique(vapply(batches, function(b) b$tgt, character(1)))
          try(refresh_after_ship(changed = changed_tgts), silent = TRUE)
        }
        # Clear the selection so the shipped packages aren't accidentally re-sent.
        shinyjs::runjs(sprintf("courierDepotSelectAll('%s', false);", ns("ship_table")))
      }
      hero_js("stop")
    })

    # ── Log pane (mirrors Bulk Dispatch) ───────────────────────────────────
    format_depot_log <- function(entry) {
      if (startsWith(entry, "[ERR] ")) {
        clean <- htmltools::htmlEscape(substr(entry, 7L, nchar(entry)))
        sprintf('<span class="sync-log-error">%s</span>', clean)
      } else {
        htmltools::htmlEscape(entry)
      }
    }

    output$depot_log_ui <- renderUI({
      entries <- depot_log()
      active  <- shipping_in_progress()
      res     <- depot_ship_result()

      progress_ui <- if (active) {
        tags$div(
          class = "sync-inline-progress",
          tags$div(class = "sync-progress-label", "Shipping…"),
          tags$div(
            class = "progress",
            tags$div(
              class = "progress-bar progress-bar-striped progress-bar-animated",
              role = "progressbar",
              style = "width: 100%;",
              `aria-valuenow` = "100",
              `aria-valuemin` = "0",
              `aria-valuemax` = "100"
            )
          )
        )
      } else {
        NULL
      }

      receipt_ui <- if (!is.null(res)) {
        results <- res$results
        n_total <- if (!is.null(results)) nrow(results) else 0L
        n_ok    <- if (!is.null(results)) sum(results$status == "success") else 0L
        theme   <- if (n_total == 0L) "secondary"
                   else if (n_ok == n_total) "success"
                   else if (n_ok == 0L) "danger" else "warning"
        bslib::value_box(
          "Delivery Receipt",
          sprintf("%d / %d packages delivered", n_ok, n_total),
          sprintf("%.1fs", res$elapsed_sec %||% 0),
          theme = theme
        )
      } else {
        NULL
      }

      empty_text <- "Check packages, then press Ship. Activity appears here."
      tags$div(
        class = paste("sync-log", if (length(entries) == 0) "sync-log-empty" else ""),
        tags$div(
          class = "sync-log-title",
          "Log panel",
          tags$span(
            class = "sync-log-subtitle",
            if (length(entries) == 0) "Waiting for activity" else "Ship actions and delivery results"
          )
        ),
        progress_ui,
        receipt_ui,
        tags$pre(
          id = ns("depot_log_pre"),
          `data-empty` = if (length(entries) == 0) "true" else NULL,
          if (length(entries) == 0) {
            empty_text
          } else {
            HTML(paste(
              vapply(rev(utils::tail(entries, 250)), format_depot_log, character(1)),
              collapse = "\n"
            ))
          }
        )
      )
    })
  })
}
