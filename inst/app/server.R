server <- function(input, output, session) {
  from_r_path   <- reactiveVal(NULL)
  to_r_path     <- reactiveVal(NULL)
  migration_log <- reactiveVal(NULL)
  routes_cache  <- reactiveVal(NULL)

  # ── Error reporter ──────────────────────────────────────────────────
  error_rv <- reactiveVal(NULL)
  push_error <- function(message, context = NULL) {
    error_rv(list(message = message, context = context, ts = Sys.time()))
  }
  mod_error_reporter_server("reporter", error_rv)

  session$onFlushed(function() {
    r <- tryCatch(sort_routes(courieR::find_routes()), error = function(e) NULL)
    routes_cache(r)
  }, once = TRUE)

  route_label_top <- function(path) {
    if (grepl("Program Files", path, ignore.case = TRUE)) return("Program Files")
    if (grepl("AppData",       path, ignore.case = TRUE)) return("AppData")
    if (grepl("Documents",     path, ignore.case = TRUE)) return("Documents")
    if (grepl("homebrew|Cellar", path, ignore.case = TRUE)) return("Homebrew")
    if (grepl("/opt/R/",       path))                     return("rig")
    if (grepl("\\.local/share/rig", path))                return("rig (user)")
    if (grepl("conda",         path, ignore.case = TRUE)) return("conda")
    if (grepl("Library/Frameworks", path))                return("Framework")
    basename(dirname(dirname(path)))
  }

  output$top_install_summary <- renderUI({
    routes <- routes_cache()
    if (is.null(routes) || nrow(routes) == 0) return(NULL)

    sel_a <- from_r_path()
    sel_b <- to_r_path()

    tags$div(
      class = "top-install-summary",
      tags$span(class = "top-install-detected-label", "Detected installations:"),
      lapply(seq_len(nrow(routes)), function(i) {
        path <- routes$rscript_path[[i]]
        extra <- if (!is.null(sel_a) && identical(path, sel_a)) {
          "top-install-pill-a"
        } else if (!is.null(sel_b) && identical(path, sel_b)) {
          "top-install-pill-b"
        } else {
          ""
        }
        tags$div(
          class = paste("top-install-pill", extra),
          tags$span(class = "top-install-pill-version", sprintf("R %s", routes$version[[i]])),
          " ",
          tags$span(class = "top-install-pill-location", route_label_top(path))
        )
      })
    )
  })

  output$details_panel <- renderUI({
    src <- from_r_path()
    tgt <- to_r_path()
    bslib::layout_column_wrap(
      width = 1/2,
      bslib::card(
        bslib::card_header("Origin R"),
        bslib::card_body(if (is.null(src)) "Not selected" else src)
      ),
      bslib::card(
        bslib::card_header("Destination R"),
        bslib::card_body(if (is.null(tgt)) "Not selected" else tgt)
      )
    )
  })

  mod_origin_server("env", from_r_path, push_error = push_error)
  mod_receipt_server("results", migration_log)
  mod_manifest_server("report", from_r_path, to_r_path, migration_log)
  mod_sync_server("sync", from_r_path, to_r_path, push_error = push_error)
  mod_update_server("update", from_r_path, to_r_path, push_error = push_error)
}
