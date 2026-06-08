server <- function(input, output, session) {
  from_r_path      <- reactiveVal(NULL)
  to_r_path        <- reactiveVal(NULL)
  migration_log    <- reactiveVal(NULL)
  routes_cache     <- reactiveVal(NULL)
  comparison_rv    <- reactiveVal(NULL)
  sync_direction_rv <- reactiveVal("A_to_B")
  transfer_mode_rv  <- reactiveVal("online")
  actionable_count  <- reactiveVal(0L)

  error_rv <- reactiveVal(NULL)
  push_error <- function(message, context = NULL) {
    error_rv(list(message = message, context = context, ts = Sys.time()))
  }
  mod_error_reporter_server("reporter", error_rv)

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

  output$advanced_badge <- renderUI({
    n <- actionable_count()
    if (n == 0L) return(NULL)
    tags$span(class = "advanced-tab-badge", n)
  })

  mod_origin_server(
    "env",
    from_r_path      = from_r_path,
    routes_cache     = routes_cache,
    push_error       = push_error,
    comparison_rv    = comparison_rv,
    to_r_path        = to_r_path,
    sync_direction_rv = sync_direction_rv,
    transfer_mode_rv  = transfer_mode_rv
  )
  mod_receipt_server("results", migration_log)
  mod_manifest_server("report", from_r_path, to_r_path, migration_log)
  mod_sync_server(
    "sync",
    install_a_path    = from_r_path,
    install_b_path    = to_r_path,
    routes_cache      = routes_cache,
    push_error        = push_error,
    comparison_out    = comparison_rv,
    actionable_out    = actionable_count,
    sync_direction_out = sync_direction_rv,
    transfer_mode_out  = transfer_mode_rv
  )
  mod_update_server("update", from_r_path, to_r_path, push_error = push_error)
}
