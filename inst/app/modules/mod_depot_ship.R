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

    # Zone 1 — context bar
    uiOutput(ns("context_bar")),

    # Zone 2 — filters + search + toolbar + table
    uiOutput(ns("ship_chips")),
    div(
      class = "depot-ship-toolbar",
      textInput(ns("ship_search"), label = NULL,
                placeholder = "Search packages…", width = "220px"),
      div(
        class = "depot-ship-bulk",
        selectInput(
          ns("bulk_action"), label = NULL,
          choices  = c("Skip" = "skip", "Ship as-is" = "ship", "Install online" = "online"),
          selected = "online",
          selectize = FALSE,
          width = "160px"
        ),
        actionButton(ns("bulk_apply"), "Apply to selected",
                     class = "btn btn-sm depot-bulk-apply-btn")
      )
    ),
    DT::dataTableOutput(ns("ship_table")),

    # Zone 3 — plan summary + ship
    uiOutput(ns("plan_summary")),
    div(
      class = "depot-ship-footer",
      actionButton(ns("depot_ship_btn"), "Ship",
                   class = "btn sync-compare-btn depot-ship-execute-btn")
    ),

    # Post-ship inline receipt
    uiOutput(ns("depot_receipt"))
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
    pkg_actions        <- reactiveVal(NULL)  # named char vec: pkg -> "skip"|"ship"|"online"
    ship_filter_status <- reactiveVal(NULL)  # NULL = all diff statuses shown
    depot_ship_result  <- reactiveVal(NULL)

    get_direction <- function() {
      if (is.function(sync_direction_rv)) sync_direction_rv() else "A_to_B"
    }
    get_mode <- function() {
      if (is.function(transfer_mode_rv)) transfer_mode_rv() else "online"
    }
    get_comp <- function() {
      if (is.function(comparison_rv)) comparison_rv() else NULL
    }

    # ── Initialise defaults when comparison changes ─────────────────────────
    observeEvent(get_comp(), {
      comp <- get_comp()
      if (is.null(comp) || nrow(comp) == 0) { pkg_actions(NULL); return() }

      direction      <- get_direction()
      default_action <- switch(get_mode(),
        online   = "online",
        offline  = "ship",
        preserve = "ship",
        "online"
      )

      diff_pkgs <- switch(direction,
        A_to_B = comp[["package"]][comp[["status"]] %in% c("missing-from-B", "newer-in-A")],
        B_to_A = comp[["package"]][comp[["status"]] %in% c("missing-from-A", "newer-in-B")],
        full   = comp[["package"]][comp[["status"]] != "same"],
        character(0)
      )

      actions             <- rep("skip", nrow(comp))
      names(actions)      <- comp[["package"]]
      actions[diff_pkgs]  <- default_action

      pkg_actions(actions)
      ship_filter_status(c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B"))
      depot_ship_result(NULL)
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

    # ── Context bar ────────────────────────────────────────────────────────
    output$context_bar <- renderUI({
      comp <- get_comp()
      if (is.null(comp)) {
        return(div(
          class = "depot-ship-context-bar depot-ship-context-empty",
          tags$span("Run Compare in Dispatch first to load packages.")
        ))
      }
      dir  <- get_direction()
      mode <- get_mode()
      from <- if (is.function(from_r_path)) from_r_path() else NULL
      to   <- if (is.function(to_r_path))   to_r_path()   else NULL

      dir_label <- switch(dir,
        A_to_B = "→ B",
        B_to_A = "← A",
        full   = "Two-way",
        dir
      )
      div(
        class = "depot-ship-context-bar",
        tags$span(class = "depot-ship-context-item",
          tags$strong("A: "), tags$code(basename(dirname(dirname(from %||% ""))))),
        tags$span(class = "depot-ship-context-sep", dir_label),
        tags$span(class = "depot-ship-context-item",
          tags$strong("B: "), tags$code(basename(dirname(dirname(to %||% ""))))),
        tags$span(class = "depot-ship-context-mode",
          tags$strong("Mode: "), mode)
      )
    })

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
        make_chip("same",           "identical",  "chip-same"),
        make_chip("newer-in-A",     "newer in A", "chip-diff-a"),
        make_chip("newer-in-B",     "newer in B", "chip-diff-b"),
        make_chip("missing-from-B", "not in B",   "chip-diff-a"),
        make_chip("missing-from-A", "not in A",   "chip-diff-b")
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

    # ── Bulk action apply ──────────────────────────────────────────────────
    observeEvent(input$bulk_apply, {
      selected_idx <- input$ship_table_rows_selected
      if (is.null(selected_idx) || length(selected_idx) == 0L) {
        showNotification("Select rows in the table first.", type = "warning")
        return()
      }
      visible     <- visible_comp()
      if (is.null(visible)) return()
      target_pkgs <- visible[["package"]][selected_idx]
      action      <- input$bulk_action
      current     <- isolate(pkg_actions())
      current[target_pkgs] <- action
      pkg_actions(current)
    })

    # ── Table ──────────────────────────────────────────────────────────────
    empty_ship_dt <- function() {
      DT::datatable(
        data.frame(Package = character(), `Version A` = character(),
                   `Version B` = character(), Status = character(),
                   Action = character(), check.names = FALSE),
        rownames  = FALSE,
        selection = "multiple",
        options   = list(dom = "t", pageLength = -1)
      )
    }

    output$ship_table <- DT::renderDataTable({
      visible <- visible_comp()
      actions <- pkg_actions()
      if (is.null(visible) || nrow(visible) == 0L || is.null(actions))
        return(empty_ship_dt())

      pkgs <- visible[["package"]]
      display <- data.frame(
        Package    = pkgs,
        `Version A` = ifelse(is.na(visible[["version_in_a"]]),
                              "not installed", visible[["version_in_a"]]),
        `Version B` = ifelse(is.na(visible[["version_in_b"]]),
                              "not installed", visible[["version_in_b"]]),
        Status     = visible[["status"]],
        Action     = actions[pkgs],
        check.names = FALSE,
        stringsAsFactors = FALSE
      )

      DT::datatable(
        display,
        rownames  = FALSE,
        selection = "multiple",
        options   = list(
          dom        = "t",
          pageLength = -1,
          scrollY    = "400px",
          scrollCollapse = TRUE
        )
      ) |>
        DT::formatStyle(
          "Action",
          backgroundColor = DT::styleEqual(
            c("skip",    "ship",    "online"),
            c("#f5f5f5", "#fff4ec", "#eef6ff")
          ),
          color = DT::styleEqual(
            c("skip",    "ship",    "online"),
            c("#9aabba", "#c27a3a", "#1d6fa5")
          ),
          fontWeight = DT::styleEqual(
            c("skip", "ship", "online"),
            c("400",  "600",  "700")
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
      actions <- pkg_actions()
      if (is.null(actions)) return(NULL)
      n_online <- sum(actions == "online")
      n_ship   <- sum(actions == "ship")
      n_skip   <- sum(actions == "skip")
      if (n_online + n_ship == 0L) {
        shinyjs::disable("depot_ship_btn")
      } else {
        shinyjs::enable("depot_ship_btn")
      }
      div(
        class = "depot-ship-summary",
        if (n_online > 0)
          tags$span(class = "depot-summary-online",
                    sprintf("%d × install online", n_online)),
        if (n_ship > 0)
          tags$span(class = "depot-summary-ship",
                    sprintf("%d × ship as-is", n_ship)),
        if (n_skip > 0)
          tags$span(class = "depot-summary-skip",
                    sprintf("%d × skip", n_skip))
      )
    })

    # ── Ship button ────────────────────────────────────────────────────────
    observeEvent(input$depot_ship_btn, {
      actions <- isolate(pkg_actions())
      comp    <- isolate(get_comp())
      from    <- if (is.function(from_r_path)) isolate(from_r_path()) else NULL
      to      <- if (is.function(to_r_path))   isolate(to_r_path())   else NULL
      dir     <- isolate(get_direction())

      if (is.null(actions) || is.null(comp) || is.null(from) || is.null(to)) {
        showNotification("Missing configuration — run Compare in Dispatch first.",
                         type = "warning")
        return()
      }

      batches <- .build_depot_ship_batches(actions, comp, dir, from, to)
      if (length(batches) == 0L) {
        showNotification("No packages selected for shipping.", type = "warning")
        return()
      }

      total <- sum(sapply(batches, function(b) length(b$pkgs)))
      depot_ship_result(NULL)
      start <- Sys.time()

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
        }
        TRUE
      }, error = function(e) {
        showNotification(paste("Ship failed:", e$message),
                         type = "error", duration = NULL)
        if (is.function(push_error))
          push_error(e$message, context = "Depot Ship execution")
        FALSE
      })

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

      depot_ship_result(list(
        results     = combined_results,
        plan        = combined_plans,
        elapsed_sec = elapsed,
        ok          = ok
      ))

      if (ok) {
        showNotification(
          sprintf("Ship complete. %d package(s) processed.", total),
          type = "message"
        )
        current <- isolate(pkg_actions())
        shipped <- names(actions)[actions != "skip"]
        current[shipped] <- "skip"
        pkg_actions(current)
      }
    })

    # ── Inline receipt after depot ship ────────────────────────────────────
    output$depot_receipt <- renderUI({
      res <- depot_ship_result()
      if (is.null(res)) return(NULL)

      results <- res$results
      n_total <- if (!is.null(results)) nrow(results) else 0L
      n_ok    <- if (!is.null(results)) sum(results$status == "success") else 0L
      theme   <- if (n_ok == n_total) "success" else if (n_ok == 0L) "danger" else "warning"

      bslib::card(
        class = "sync-receipt-card",
        bslib::card_header("Delivery Receipt"),
        bslib::card_body(
          bslib::value_box(
            "Result",
            sprintf("%d / %d packages delivered", n_ok, n_total),
            sprintf("%.1fs", res$elapsed_sec %||% 0),
            theme = theme
          ),
          if (!is.null(results) && nrow(results) > 0L) {
            DT::renderDataTable(
              DT::datatable(results,
                options = list(pageLength = 15, dom = "tip"),
                rownames = FALSE
              )
            )
          }
        )
      )
    })
  })
}
