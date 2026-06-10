# Helper: build ship batches from per-package action assignments.
# Returns a list of batch specs: list(pkgs, src, tgt, mode).
#
# actions   named character vector: package -> "skip" | "ship" | "online"
# comp      data.frame/data.table with columns: package, status
# direction one of "A_to_B", "B_to_A", "full"
# from_path Rscript path for installation A
# to_path   Rscript path for installation B
.build_depot_ship_batches <- function(actions, comp, direction, from_path, to_path) {
  non_skip <- names(actions)[actions != "skip"]
  if (length(non_skip) == 0L) return(list())

  status_map <- stats::setNames(
    comp[["status"]][match(non_skip, comp[["package"]])],
    non_skip
  )

  if (direction == "full") {
    a_to_b <- non_skip[status_map[non_skip] %in% c("missing-from-B", "newer-in-A")]
    b_to_a <- non_skip[status_map[non_skip] %in% c("missing-from-A", "newer-in-B")]
  } else if (direction == "A_to_B") {
    a_to_b <- non_skip
    b_to_a <- character(0)
  } else {
    a_to_b <- character(0)
    b_to_a <- non_skip
  }

  batches <- list()

  add_batch <- function(pkgs, src, tgt, mode) {
    if (length(pkgs) == 0L) return()
    batches[[length(batches) + 1L]] <<- list(pkgs = pkgs, src = src,
                                              tgt = tgt, mode = mode)
  }

  add_batch(a_to_b[actions[a_to_b] == "online"], from_path, to_path, "online")
  add_batch(a_to_b[actions[a_to_b] == "ship"],   from_path, to_path, "offline")
  add_batch(b_to_a[actions[b_to_a] == "online"], to_path, from_path, "online")
  add_batch(b_to_a[actions[b_to_a] == "ship"],   to_path, from_path, "offline")

  batches
}

mod_depot_ship_ui <- function(id) {
  ns <- NS(id)
  div(
    class = "depot-ship-pane",

    # Small JS helper: check/uncheck every visible row checkbox and notify Shiny.
    tags$script(HTML(
      "function courierDepotSelectAll(tableId, checked){
         var root = document.getElementById(tableId);
         if(!root) return;
         var cbs = root.querySelectorAll('.depot-ship-cb');
         cbs.forEach(function(c){ c.checked = checked; });
         if(cbs.length){ cbs[0].dispatchEvent(new Event('change', {bubbles:true})); }
       }"
    )),

    # Filter chips span the full width above the workspace
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
                       onclick = "if(window.courierStartTimer) window.courierStartTimer();")
        )
      ),

      # Right pane — log
      div(
        class = "sync-log-pane",
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
                                   incoming_search   = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Reactive state ─────────────────────────────────────────────────────
    # The checked rows ARE the shipment: input$ship_cb_rows holds 1-based row
    # indices into visible_comp(). The "How to ship" dropdown (input$ship_mode)
    # decides the mode applied to that checked set.
    ship_filter_status   <- reactiveVal(NULL)  # NULL = all diff statuses shown
    depot_ship_result    <- reactiveVal(NULL)
    shipping_in_progress <- reactiveVal(FALSE)
    depot_log <- reactiveVal(character(0))
    depot_log_append <- function(...) {
      msg <- paste0(...)
      depot_log(utils::tail(c(isolate(depot_log()), msg), 1000L))
    }

    get_direction <- function() {
      if (is.function(sync_direction_rv)) sync_direction_rv() else "A_to_B"
    }
    get_mode <- function() {
      if (is.function(transfer_mode_rv)) transfer_mode_rv() else "online"
    }
    get_comp <- function() {
      if (is.function(comparison_rv)) comparison_rv() else NULL
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
    # Show the differing statuses by default; selection starts empty so the user
    # checks exactly what they want to ship. Also default the mode dropdown to
    # the global transfer mode chosen in Dispatch.
    observeEvent(get_comp(), {
      comp <- get_comp()
      if (is.null(comp) || nrow(comp) == 0) return()
      ship_filter_status(c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B"))
      depot_ship_result(NULL)
      mode_default <- switch(get_mode(), offline = "ship", preserve = "ship", "online")
      updateSelectInput(session, "ship_mode", selected = mode_default)
    }, ignoreNULL = FALSE)

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
        make_chip("newer-in-A",     "newer in source",  "chip-diff-a"),
        make_chip("newer-in-B",     "newer in target",  "chip-diff-b"),
        make_chip("missing-from-B", "not in target",    "chip-diff-a"),
        make_chip("missing-from-A", "not in source",    "chip-diff-b")
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
        Source  = ifelse(is.na(visible[["version_in_a"]]),
                         "not installed", visible[["version_in_a"]]),
        Target  = ifelse(is.na(visible[["version_in_b"]]),
                         "not installed", visible[["version_in_b"]]),
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
          scrollY    = "400px",
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
            c("same",    "missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B"),
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
      div(
        class = "depot-ship-summary",
        tags$span(class = if (identical(mode, "ship")) "depot-summary-ship" else "depot-summary-online",
                  sprintf("%d package(s) selected — %s", n, mode_label))
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

      showNotification(
        sprintf("Shipping %d package(s)… this may take a few minutes.", total),
        type = "message", duration = NULL, id = "depot-ship-busy"
      )

      all_results <- list()
      all_plans   <- list()

      ok <- tryCatch({
        for (i in seq_along(batches)) {
          b <- batches[[i]]
          res <- courieR::ship(
            source_path = b$src,
            target_path = b$tgt,
            packages    = b$pkgs,
            upgrade     = TRUE,
            mode        = b$mode
          )
          if (!is.null(res$results) && nrow(res$results) > 0L)
            all_results[[i]] <- res$results
          if (!is.null(res$plan) && nrow(res$plan) > 0L)
            all_plans[[i]] <- res$plan
          depot_log_append(sprintf("Shipped %d package(s) [%s] → %s",
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
      depot_log_append(sprintf("Done — %d package(s) in %.0fs.", total, elapsed))
      combined_results <- if (length(all_results) > 0L)
        data.table::rbindlist(all_results, fill = TRUE)
      else
        data.table::data.table(package = character(),
                               status = character(), message = character())

      combined_plans <- if (length(all_plans) > 0L)
        data.table::rbindlist(all_plans, fill = TRUE)
      else
        data.table::data.table(package = character(), action = character())

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
        # Clear the selection so the shipped packages aren't accidentally re-sent.
        shinyjs::runjs(sprintf("courierDepotSelectAll('%s', false);", ns("ship_table")))
      }
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
