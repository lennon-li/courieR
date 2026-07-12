# Shared Shiny app helpers used by both Bulk Dispatch (mod_sync.R) and Custom
# Dispatch (mod_depot_ship.R): the log-panel writer/formatter, the hero-panel
# JS bridge, and the ship() log_callback that drives the hero panel from
# ship()'s progress lines. Extracted per the 2026-07-11 audit (D2): the two
# modules had copy-pasted these near-verbatim, and the divergence was the
# root cause of A3 (one module's error handler forgot to stop the hero panel).

# Build a log-line writer bound to a reactiveVal and a DOM element id.
# `log_rv` is a reactiveVal holding a character vector of rendered entries;
# `dom_id` is the id of the <pre>/<div> the live line gets mirrored into
# (the reactiveVal alone can't re-render while a synchronous ship loop blocks
# the event loop). `max_lines` caps history (NULL = unbounded).
#
# Takes an already-assembled `msg` string rather than `...`, so each caller
# keeps its own message-assembly semantics (mod_sync's callers use
# `paste(..., collapse = "")`, mod_depot_ship's use `paste0(...)` - not
# equivalent when multiple arguments are passed, since plain `paste()`
# inserts its default `sep = " "` between them).
#
# Call with `live_error = TRUE` to also render the line as a red span in the
# DOM immediately (not just on the next full re-render); the stored entry is
# still prefixed "[ERR] " either way so format_courier_log_entry() renders it
# red on a full redraw regardless of how it was appended.
make_log_appender <- function(log_rv, dom_id, max_lines = NULL) {
  function(msg, live_error = FALSE) {
    entry <- sprintf("%s  %s", format(Sys.time(), "%H:%M:%S"), msg)
    stored <- if (live_error) paste0("[ERR] ", entry) else entry
    new_log <- c(isolate(log_rv()), stored)
    if (!is.null(max_lines)) new_log <- utils::tail(new_log, max_lines)
    log_rv(new_log)
    if (live_error) message("[ERR] ", entry) else message(entry)
    try({
      entry_json <- jsonlite::toJSON(entry, auto_unbox = TRUE)
      js <- if (live_error) {
        "(function(){var el=document.getElementById('%s'); if(!el) return; var raw=%s; var s=raw.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); var span='<span class=\"sync-log-error\">'+s+'</span>'; if(el.getAttribute('data-empty')==='true'){el.removeAttribute('data-empty');el.innerHTML=span;}else{el.innerHTML=span+(el.innerHTML?'\\n'+el.innerHTML:'');} el.scrollTop=0;})();"
      } else {
        "(function(){var el=document.getElementById('%s'); if(!el) return; var raw=%s; var s=raw.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); if(el.getAttribute('data-empty')==='true'){el.removeAttribute('data-empty');el.innerHTML=s;}else{el.innerHTML=s+(el.innerHTML?'\\n'+el.innerHTML:'');} el.scrollTop=0;})();"
      }
      shinyjs::runjs(sprintf(js, dom_id, entry_json))
    }, silent = TRUE)
    invisible(NULL)
  }
}

# Render one stored log entry to HTML for a full log-panel redraw, coloring
# "[ERR] "-prefixed entries red. Shared by mod_sync's and mod_depot_ship's log
# panel renderUI().
format_courier_log_entry <- function(entry) {
  if (startsWith(entry, "[ERR] ")) {
    clean <- htmltools::htmlEscape(substr(entry, 7L, nchar(entry)))
    sprintf('<span class="sync-log-error">%s</span>', clean)
  } else {
    htmltools::htmlEscape(entry)
  }
}

# Build the hero_js(fn, arg) bridge that calls a named JS global's method,
# e.g. window.courierBulkHero.status("..."). Silently no-ops if that JS
# object isn't present (hero panel not open, or in tests).
make_hero_js <- function(window_var) {
  function(fn, arg = NULL) {
    arg_js <- if (is.null(arg)) "" else jsonlite::toJSON(arg, auto_unbox = TRUE)
    try(shinyjs::runjs(sprintf(
      "if(window.%s) window.%s.%s(%s);", window_var, window_var, fn, arg_js
    )), silent = TRUE)
  }
}

# Build the log_callback ship() invokes during a batch (always with exactly
# one message-string argument - see `?ship`'s `log_callback` doc). Forwards
# every line to `log_append`, and drives the hero panel's live status/count
# from the "[n/m] pkg - copying" / "[ok] pkg - copied" / pak progress lines
# ship() emits. `labels` lets each caller keep its own exact wording for the
# copying/installing/pak-done status text (Bulk Dispatch and Custom Dispatch
# have always worded these slightly differently).
make_ship_log_cb <- function(log_append, hero_js, labels) {
  delivered <- 0L
  function(msg) {
    log_append(msg)
    m <- regmatches(msg, regexec("^\\[(\\d+)/(\\d+)\\] (\\S+) - copying", msg))[[1]]
    if (length(m) == 4L) {
      hero_js("status", sprintf(labels$copying, m[[4]], m[[2]], m[[3]]))
      return(invisible(NULL))
    }
    m2 <- regmatches(msg, regexec("^\\[ok\\] (\\S+) - copied", msg))[[1]]
    if (length(m2) == 2L) {
      delivered <<- delivered + 1L
      hero_js("count", delivered)
      hero_js("status", sprintf(labels$delivered, m2[[2]]))
      return(invisible(NULL))
    }
    if (grepl("^Reinstalling \\d+ package", msg)) {
      hero_js("status", labels$installing)
    } else if (grepl("^pak subprocess finished successfully", msg)) {
      hero_js("status", labels$pak_done)
    }
    invisible(NULL)
  }
}
