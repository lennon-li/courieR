mod_origin_browse_ui <- function(id) {
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
        DT::dataTableOutput(ns("packages")),
        uiOutput(ns("browse_to_ship_btn"))
      )
    )
  )
}

mod_origin_ship_ui <- function(id) {
  ns <- NS(id)
  mod_depot_ship_ui(ns("depot_ship"))
}

mod_origin_server <- function(id,
                              from_r_path       = NULL,
                              routes_cache      = NULL,
                              push_error        = NULL,
                              comparison_rv     = NULL,
                              to_r_path         = NULL,
                              sync_direction_rv  = NULL,
                              transfer_mode_rv   = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    routes_rv  <- reactiveVal(NULL)
    detecting  <- reactiveVal(FALSE)
    loading_pkg <- reactiveVal(FALSE)

    # Short form of a library path (its last two components) used to
    # disambiguate installs that share a version but write to different libraries.
    lib_short <- function(library) {
      if (is.null(library) || length(library) == 0 || is.na(library) || !nzchar(library)) {
        return(NA_character_)
      }
      parts <- strsplit(library, "[/\\\\]+")[[1]]
      parts <- parts[nzchar(parts)]
      if (length(parts) >= 2) paste(utils::tail(parts, 2), collapse = "/") else library
    }

    depot_label <- function(path, ver, library = NA_character_) {
      loc <- if (grepl("AppData", path, ignore.case = TRUE)) "AppData"
             else if (grepl("Program Files", path, ignore.case = TRUE)) "Program Files"
             else if (grepl("Documents", path, ignore.case = TRUE)) "Documents"
             else basename(dirname(dirname(path)))
      base <- paste0("R ", ver, "  —  ", loc)
      ls <- lib_short(library)
      if (!is.na(ls)) paste0(base, "  ·  lib: ", ls) else base
    }

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
        routes[, intersect(c("version", "rscript_path", "library", "is_current"), names(routes))],
        options = list(pageLength = 5, dom = "tip"),
        rownames = FALSE
      )
    })

    output$pkg_controls <- renderUI({
      routes <- routes_rv()
      if (detecting()) return(NULL)
      if (is.null(routes)) {
        return(tags$p(class = "update-no-selection", "Switch to Dispatch and run Compare to detect installations."))
      }
      if (nrow(routes) == 0) {
        return(tags$p(class = "update-no-selection", "No depots detected."))
      }

      lib_col <- if ("library" %in% names(routes)) routes$library else rep(NA_character_, nrow(routes))
      labels  <- mapply(depot_label, routes$rscript_path, routes$version, lib_col, USE.NAMES = FALSE)

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

      src_label <- vapply(seq_len(nrow(pkgs)), function(i) {
        s  <- pkgs$source[[i]]
        rt <- if ("remotetype"     %in% names(pkgs)) pkgs$remotetype[[i]]     else NA_character_
        ru <- if ("remoteusername" %in% names(pkgs)) pkgs$remoteusername[[i]] else NA_character_
        rr <- if ("remoterepo"     %in% names(pkgs)) pkgs$remoterepo[[i]]     else NA_character_
        if (identical(s, "GitHub") && !is.na(ru) && !is.na(rr) && nzchar(ru) && nzchar(rr)) {
          paste0("GitHub  ", ru, "/", rr)
        } else if (identical(s, "GitHub") && !is.na(ru) && nzchar(ru)) {
          paste0("GitHub  ", ru)
        } else if (!is.null(s) && !is.na(s) && nzchar(s)) {
          s
        } else if (!is.na(rt) && nzchar(rt)) {
          rt
        } else {
          "unknown"
        }
      }, character(1))

      display <- data.frame(
        Package = pkgs$package,
        Version = pkgs$version,
        Source  = src_label,
        Library = if ("libpath" %in% names(pkgs)) pkgs$libpath else NA_character_,
        stringsAsFactors = FALSE
      )

      DT::datatable(
        display,
        rownames = FALSE,
        options = list(pageLength = 15, dom = "frtip", autoWidth = FALSE)
      ) |>
        DT::formatStyle(
          "Source",
          backgroundColor = DT::styleEqual(
            c("CRAN", "Bioconductor"),
            c("rgba(237,244,250,0.7)", "rgba(232,249,250,0.7)")
          ),
          color = DT::styleEqual(
            c("CRAN", "Bioconductor", "unknown"),
            c("#355066",              "#15606a",       "#9aabba")
          ),
          fontWeight = DT::styleEqual(
            c("CRAN"), c("400")
          )
        )
    })

    observeEvent(routes_rv(), {
      routes <- routes_rv()
      if (is.null(routes) || nrow(routes) == 0) return()
      lib_col <- if ("library" %in% names(routes)) routes$library else rep(NA_character_, nrow(routes))
      labels <- mapply(depot_label, routes$rscript_path, routes$version, lib_col, USE.NAMES = FALSE)
      choices <- stats::setNames(routes$rscript_path, labels)
      updateSelectInput(session, "selected_path", choices = choices,
                        selected = routes$rscript_path[[1]])
    }, ignoreNULL = TRUE)

    # ── Browse → Ship bridge ──────────────────────────────────────────────
    browse_to_ship_pkg <- reactiveVal(NULL)

    output$browse_to_ship_btn <- renderUI({
      req(pkg_data())
      selected <- input$packages_rows_selected
      if (length(selected) == 0) return(NULL)
      pkgs <- pkg_data()
      pkgs <- pkgs[is.na(pkgs$priority) |
                     !(pkgs$priority %in% c("base", "recommended")), ]
      pkg_name <- pkgs$package[selected[[1]]]
      actionButton(
        ns("view_in_ship"), sprintf("View '%s' in Custom Dispatch", pkg_name),
        class = "btn btn-sm browse-to-ship-btn"
      )
    })

    observeEvent(input$view_in_ship, {
      selected <- input$packages_rows_selected
      if (length(selected) == 0) return()
      pkgs <- pkg_data()
      pkgs <- pkgs[is.na(pkgs$priority) |
                     !(pkgs$priority %in% c("base", "recommended")), ]
      pkg_name <- pkgs$package[selected[[1]]]
      browse_to_ship_pkg(pkg_name)
      shinyjs::runjs("navigateToCustomDispatch();")
    })

    # ── Ship sub-module ───────────────────────────────────────────────────
    mod_depot_ship_server(
      "depot_ship",
      comparison_rv     = comparison_rv,
      from_r_path       = from_r_path,
      to_r_path         = to_r_path,
      sync_direction_rv  = sync_direction_rv,
      transfer_mode_rv   = transfer_mode_rv,
      push_error        = push_error,
      incoming_search   = browse_to_ship_pkg
    )
  })
}
