server <- function(input, output, session) {
  from_r_path      <- reactiveVal(NULL)
  to_r_path        <- reactiveVal(NULL)
  routes_cache     <- reactiveVal(NULL)
  comparison_rv    <- reactiveVal(NULL)
  sync_direction_rv <- reactiveVal("source_to_target")
  transfer_mode_rv  <- reactiveVal("online")
  actionable_count  <- reactiveVal(0L)
  refresh_request   <- reactiveVal(NULL)

  error_rv <- reactiveVal(NULL)
  push_error <- function(message, context = NULL) {
    error_rv(list(message = message, context = context, ts = Sys.time()))
  }
  mod_error_reporter_server("reporter", error_rv)

  # One manifest scan per library per session, shared by every tab (Compare,
  # Custom Dispatch ship, previews). Library scans are the slowest operation
  # in the app on some machines (minutes on synced/network drives), so a ship
  # right after a Compare must not rescan anything. Writers invalidate the
  # paths they changed; timed-out scans are never cached.
  scan_store <- new.env(parent = emptyenv())
  shared_scans <- list(
    get = function(path, force = FALSE, log = NULL) {
      if (!force && !is.null(scan_store[[path]])) return(scan_store[[path]])
      if (is.function(log)) try(log(sprintf("Scanning library of %s ...", path)), silent = TRUE)
      t0 <- Sys.time()
      m <- courieR::manifest(rscript_path = path, format = "data.table",
                             timeout_sec = 300L)
      if (isTRUE(attr(m, "timed_out"))) {
        if (is.function(log)) {
          try(log(sprintf("[ERR] Library scan of %s timed out.", path)), silent = TRUE)
        }
        return(m)
      }
      scan_store[[path]] <- m
      if (is.function(log)) {
        try(log(sprintf(
          "Scan complete: %d package(s) (%.1fs).", nrow(m),
          as.numeric(difftime(Sys.time(), t0, units = "secs"))
        )), silent = TRUE)
      }
      m
    },
    invalidate = function(path) {
      if (!is.null(path) && nzchar(path) &&
          exists(path, envir = scan_store, inherits = FALSE)) {
        rm(list = path, envir = scan_store)
      }
      invisible(NULL)
    },
    clear = function() {
      rm(list = ls(envir = scan_store), envir = scan_store)
      invisible(NULL)
    }
  )

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
    transfer_mode_rv  = transfer_mode_rv,
    refresh_after_ship = function(changed = NULL) {
      refresh_request(list(
        source_path   = from_r_path(),
        target_path   = to_r_path(),
        changed_paths = changed,
        ts = Sys.time()
      ))
    },
    shared_scans       = shared_scans
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
    transfer_mode_out  = transfer_mode_rv,
    refresh_request    = refresh_request,
    shared_scans       = shared_scans
  )
}
