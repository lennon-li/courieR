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

  # Detection is no longer automatic on startup. The user triggers it with the
  # Detect button in the Sync tab, which populates routes_cache for all tabs.

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

  mod_origin_server("env", from_r_path, routes_cache = routes_cache, push_error = push_error)
  mod_receipt_server("results", migration_log)
  mod_manifest_server("report", from_r_path, to_r_path, migration_log)
  mod_sync_server("sync", from_r_path, to_r_path, routes_cache = routes_cache, push_error = push_error)
  mod_update_server("update", from_r_path, to_r_path, push_error = push_error)
}
