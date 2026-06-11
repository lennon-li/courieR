server <- function(input, output, session) {
  from_r_path      <- reactiveVal(NULL)
  to_r_path        <- reactiveVal(NULL)
  routes_cache     <- reactiveVal(NULL)
  comparison_rv    <- reactiveVal(NULL)
  sync_direction_rv <- reactiveVal("source_to_target")
  transfer_mode_rv  <- reactiveVal("online")
  actionable_count  <- reactiveVal(0L)

  error_rv <- reactiveVal(NULL)
  push_error <- function(message, context = NULL) {
    error_rv(list(message = message, context = context, ts = Sys.time()))
  }
  mod_error_reporter_server("reporter", error_rv)

  output$custom_dispatch_badge <- renderUI({
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
  mod_manifest_server("report", from_r_path, to_r_path, reactiveVal(NULL))
  mod_sync_server(
    "sync",
    install_source_path = from_r_path,
    install_target_path = to_r_path,
    routes_cache      = routes_cache,
    push_error        = push_error,
    comparison_out    = comparison_rv,
    actionable_out    = actionable_count,
    sync_direction_out = sync_direction_rv,
    transfer_mode_out  = transfer_mode_rv
  )
}
