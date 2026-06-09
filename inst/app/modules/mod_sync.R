mod_sync_ui <- function(id) {
  ns <- NS(id)
  tagList(
  # Elapsed-time "busy, not stuck" timer. Started client-side on button click
  # (Shiny queues server messages until an observer returns, so during a
  # blocking Compare/Ship the start has to come from the browser) and stopped
  # when the server reports the work finished (set_sync_progress(active=FALSE)).
  tags$script(HTML(
    "window.courierFmt=function(ms){var s=Math.floor(ms/1000);var m=Math.floor(s/60);s=s%60;return m+':'+(s<10?'0':'')+s;};
     window.courierStartTimer=function(){
       var w=document.getElementById('nav-progress-wrap'); if(w) w.style.display='block';
       var sb=document.querySelector('.sync-sidebar'); if(sb) sb.classList.add('sync-busy');
       var st=document.getElementById('nav-progress-step'); if(st && !st.textContent) st.textContent='Working…';
       var b=document.getElementById('nav-progress-bar'); if(b && (!b.style.width || b.style.width==='0%')) b.style.width='100%';
       if(!window.__courierTimer){
         window.__courierTimerStart=Date.now();
         var el=document.getElementById('nav-progress-elapsed'); if(el) el.textContent='0:00';
         window.__courierTimer=setInterval(function(){
           var e=document.getElementById('nav-progress-elapsed');
           if(e) e.textContent=window.courierFmt(Date.now()-window.__courierTimerStart);
         },1000);
       }
     };
     window.courierStopTimer=function(){
       if(window.__courierTimer){clearInterval(window.__courierTimer);window.__courierTimer=null;}
       var el=document.getElementById('nav-progress-elapsed');
       if(el&&window.__courierTimerStart) el.textContent=window.courierFmt(Date.now()-window.__courierTimerStart);
     };"
  )),
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      class = "sync-sidebar",
      div(
        class = "app-brand-mark sync-sidebar-logo",
        tags$div(
          class = "app-logo-wrap",
          tags$img(src = "logo.png", height = "64px",
                   style = "vertical-align: middle; background: transparent;")
        ),
        tags$div(class = "app-version",
                 sprintf("v%s", utils::packageVersion("courieR")))
      ),
      uiOutput(ns("detecting_msg")),
      uiOutput(ns("detected_installs")),
      hr(),
      div(
        class = "sync-select-block sync-select-block-a",
        tags$div(class = "sync-select-label", "Select source installation"),
        selectInput(ns("install_a"), NULL, choices = character(0), selectize = FALSE),
        uiOutput(ns("install_a_badge"))
      ),
      div(
        class = "sync-select-block sync-select-block-b",
        tags$div(class = "sync-select-label", "Select target installation"),
        selectInput(ns("install_b"), NULL, choices = character(0), selectize = FALSE),
        uiOutput(ns("install_b_target_hint")),
        uiOutput(ns("install_b_badge"))
      ),
      actionButton(ns("compare"), "Compare", class = "btn sync-compare-btn",
        onclick = "this.disabled=true; if(window.courierStartTimer) window.courierStartTimer();"),
      hr(),
      div(
        class = "sync-select-block",
        tags$div(class = "sync-select-label sync-label-row",
          "Transfer mode",
          uiOutput(ns("transfer_mode_help"), inline = TRUE)
        ),
        selectInput(ns("transfer_mode"), NULL, width = "100%", selectize = FALSE, choices = c(
          "Online reinstall" = "online",
          "Offline copy" = "offline",
          "Preserve version" = "preserve"
        ), selected = "online")
      ),
      actionButton(ns("preview_btn"), "Preview plan (no install)",
                   class = "btn sync-preview-btn"),
      actionButton(ns("sync_btn"), "Ship", class = "btn sync-compare-btn"),
    ),
    div(
      id = "nav-progress-wrap",
      style = "display:none;",
      div(
        id = "nav-progress-label",
        tags$span(id = "nav-progress-step"),
        tags$span(id = "nav-progress-elapsed", class = "nav-progress-elapsed")
      ),
      div(class = "nav-progress-track", div(id = "nav-progress-bar"))
    ),
    bslib::card(
      class = "sync-card",
      bslib::card_header("Comparison"),
      bslib::card_body(
        div(
          class = "sync-workspace",
          div(
            class = "sync-comparison-pane",
            uiOutput(ns("comparison_summary")),
            DT::dataTableOutput(ns("comparison_table"))
          ),
          div(
            class = "sync-log-pane",
            uiOutput(ns("sync_log"))
          )
        )
      )
    )
  )
  )
}

mod_sync_maintenance_ui <- function(id) {
  ns <- NS(id)
  div(
    class = "sync-restock-wrap",
    actionButton(ns("restock_a"), "Restock source from CRAN",
                 class = "btn sync-restock-btn"),
    actionButton(ns("restock_b"), "Restock target from CRAN",
                 class = "btn sync-restock-btn")
  )
}

mod_sync_server <- function(id,
                            install_a_path     = NULL,
                            install_b_path     = NULL,
                            routes_cache       = NULL,
                            push_error         = NULL,
                            comparison_out     = NULL,
                            actionable_out     = NULL,
                            sync_direction_out = NULL,
                            transfer_mode_out  = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    pending_sync     <- reactiveVal(NULL)
    routes_data      <- reactiveVal(data.frame())
    comparison_data  <- reactiveVal(NULL)
    detecting        <- reactiveVal(TRUE)
    detection_status <- reactiveVal(NULL)
    sync_log         <- reactiveVal(character())
    sync_active      <- reactiveVal(FALSE)
    sync_pct         <- reactiveVal(0)
    sync_step        <- reactiveVal("Idle")
    selected_statuses <- reactiveVal(NULL)
    last_ship_result  <- reactiveVal(NULL)

    # Session cache of manifest() scans keyed by Rscript path, so Compare/Ship/
    # Preview reuse a library scan instead of re-spawning a subprocess each time.
    # Invalidated for a target after a ship (its library changed).
    manifest_cache <- reactiveVal(list())
    get_manifest <- function(path, force = FALSE) {
      cache <- isolate(manifest_cache())
      if (!force && !is.null(cache[[path]])) return(cache[[path]])
      m <- courieR::manifest(rscript_path = path)
      cache[[path]] <- m
      manifest_cache(cache)
      m
    }
    invalidate_manifest <- function(path) {
      cache <- isolate(manifest_cache())
      cache[[path]] <- NULL
      manifest_cache(cache)
    }

    r_label <- function(path, version) {
      loc <- if (grepl("AppData", path, ignore.case = TRUE)) {
        "AppData"
      } else if (grepl("Program Files", path, ignore.case = TRUE)) {
        "Program Files"
      } else if (grepl("Documents", path, ignore.case = TRUE)) {
        "Documents"
      } else {
        basename(dirname(dirname(path)))
      }
      paste0("R ", version, "  —  ", loc)
    }

    r_badge <- function(version, bucket) {
      if (is.null(version) || is.na(version) || !nzchar(version)) {
        return(sprintf("<span class='sync-col-badge sync-col-%s'>R ?</span>", bucket))
      }
      sprintf("<span class='sync-col-badge sync-col-%s'>R %s</span>", bucket, version)
    }

    button_label <- function(from_version, from_bucket, to_version, to_bucket, label, bidirectional = FALSE) {
      from_text <- if (is.null(from_version) || is.na(from_version)) "R ?" else paste("R", from_version)
      to_text   <- if (is.null(to_version)   || is.na(to_version))   "R ?" else paste("R", to_version)
      arrow <- if (bidirectional) "&#8652;" else "&rarr;"
      shiny::HTML(sprintf(
        "<span class='visually-hidden'>%s</span><div class='sync-route-row'><span class='sync-route-pill sync-col-%s'>%s</span><span class='sync-route-arrow-icon'>%s</span><span class='sync-route-pill sync-col-%s'>%s</span></div>",
        htmltools::htmlEscape(label),
        from_bucket, from_text,
        arrow,
        to_bucket, to_text
      ))
    }

    status_badge <- function(status, display = NULL) {
      status_class <- gsub("[^a-z]", "-", tolower(status))
      label <- if (!is.null(display)) display else status
      sprintf("<span class='sync-status sync-status-%s'>%s</span>", status_class, label)
    }

    add_sync_log <- function(...) {
      msg <- paste(..., collapse = "")
      entry <- sprintf("%s  %s", format(Sys.time(), "%H:%M:%S"), msg)
      sync_log(c(isolate(sync_log()), entry))
      message(entry)
      try({
        entry_json <- jsonlite::toJSON(entry, auto_unbox = TRUE)
        shinyjs::runjs(sprintf(
          "(function(){var el=document.getElementById('%s'); if(!el) return; var raw=%s; var s=raw.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); if(el.getAttribute('data-empty')==='true'){el.removeAttribute('data-empty');el.innerHTML=s;}else{el.innerHTML=s+(el.innerHTML?'\\n'+el.innerHTML:'');} el.scrollTop=0;})();",
          ns("sync_log_pre"),
          entry_json
        ))
      }, silent = TRUE)
      invisible(NULL)
    }

    add_sync_log_error <- function(...) {
      msg <- paste(..., collapse = "")
      display <- sprintf("%s  %s", format(Sys.time(), "%H:%M:%S"), msg)
      sync_log(c(isolate(sync_log()), paste0("[ERR] ", display)))
      message("[ERR] ", display)
      try({
        display_json <- jsonlite::toJSON(display, auto_unbox = TRUE)
        shinyjs::runjs(sprintf(
          "(function(){var el=document.getElementById('%s'); if(!el) return; var raw=%s; var s=raw.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); var span='<span class=\"sync-log-error\">'+s+'</span>'; if(el.getAttribute('data-empty')==='true'){el.removeAttribute('data-empty');el.innerHTML=span;}else{el.innerHTML=span+(el.innerHTML?'\\n'+el.innerHTML:'');} el.scrollTop=0;})();",
          ns("sync_log_pre"),
          display_json
        ))
      }, silent = TRUE)
      invisible(NULL)
    }

    set_sync_progress <- function(pct = NULL, step = NULL, active = TRUE) {
      sync_active(isTRUE(active))
      if (!is.null(pct)) sync_pct(max(0, min(100, as.numeric(pct))))
      if (!is.null(step)) sync_step(step)
      pct_val  <- if (!is.null(pct)) max(0, min(100, as.numeric(pct))) else isolate(sync_pct())
      step_val <- if (!is.null(step)) step else isolate(sync_step())
      try({
        step_json <- jsonlite::toJSON(step_val %||% "", auto_unbox = TRUE)
        # The elapsed counter runs client-side (see courierStartTimer in the UI).
        # Here we update the step label + bar and start/stop the timer; the timer
        # is idempotent, so a button's onclick can start it instantly while these
        # server messages (queued behind a blocking observer) catch up later.
        shinyjs::runjs(sprintf(
          "(function(){
            var active=%s;
            var b=document.getElementById('nav-progress-bar');
            var st=document.getElementById('nav-progress-step');
            if(st){ st.textContent=%s; }
            if(active){
              if(window.courierStartTimer) window.courierStartTimer();
              if(b) b.style.width='%s%%';
            } else {
              if(window.courierStopTimer) window.courierStopTimer();
              if(b) b.style.width='100%%';
              var w=document.getElementById('nav-progress-wrap');
              setTimeout(function(){ if(w) w.style.display='none'; if(b) b.style.width='0%%'; }, 1500);
              var sb=document.querySelector('.sync-sidebar');
              if(sb) sb.classList.remove('sync-busy');
            }
          })()",
          if (isTRUE(active)) "true" else "false",
          step_json,
          pct_val
        ))
      }, silent = TRUE)
      invisible(NULL)
    }

    comparison_counts_text <- function(comp) {
      if (is.null(comp) || nrow(comp) == 0) {
        return("no packages in comparison")
      }

      statuses <- c("same", "missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B")
      counts <- table(factor(comp[["status"]], levels = statuses))
      sprintf(
        "%d same, %d missing from B, %d missing from A, %d newer in A, %d newer in B",
        counts[["same"]],
        counts[["missing-from-B"]],
        counts[["missing-from-A"]],
        counts[["newer-in-A"]],
        counts[["newer-in-B"]]
      )
    }

    add_plan_log <- function(ship_result) {
      plan <- ship_result$plan
      if (is.null(plan) || nrow(plan) == 0) {
        add_sync_log("Plan details: no package actions were required by ship().")
        return(invisible(NULL))
      }

      install_n <- sum(plan$action == "install", na.rm = TRUE)
      upgrade_n <- sum(plan$action == "upgrade", na.rm = TRUE)
      add_sync_log(sprintf("Plan details: %d install(s), %d upgrade(s).", install_n, upgrade_n))

      for (i in seq_len(nrow(plan))) {
        source_version <- if ("version.x" %in% names(plan)) plan$version.x[[i]] else NA_character_
        target_version <- if ("version.y" %in% names(plan)) plan$version.y[[i]] else NA_character_
        target_text <- if (is.na(target_version) || !nzchar(target_version)) "not installed" else target_version
        pak_spec <- if ("pak_spec" %in% names(plan)) plan$pak_spec[[i]] else plan$package[[i]]
        add_sync_log(sprintf(
          "  - %s: %s target %s -> source %s using pak spec %s",
          plan$package[[i]],
          plan$action[[i]],
          target_text,
          source_version,
          pak_spec
        ))
      }

      invisible(NULL)
    }

    add_result_log <- function(ship_result) {
      results <- ship_result$results
      if (is.null(results) || nrow(results) == 0) {
        add_sync_log("Result details: no per-package results were returned.")
        return(invisible(NULL))
      }

      for (i in seq_len(nrow(results))) {
        line <- sprintf("  - %s: %s — %s", results$package[[i]], results$status[[i]], results$message[[i]])
        if (identical(results$status[[i]], "error")) {
          add_sync_log_error(line)
        } else {
          add_sync_log(line)
        }
      }

      invisible(NULL)
    }

    route_version <- function(path) {
      routes <- routes_data()
      if (nrow(routes) == 0 || is.null(path) || !nzchar(path)) {
        return(NA_character_)
      }

      idx <- match(path, routes$rscript_path)
      if (is.na(idx)) {
        return(NA_character_)
      }

      as.character(routes$version[[idx]])
    }

    route_display <- function(path) {
      routes <- routes_data()
      if (nrow(routes) == 0 || is.null(path) || !nzchar(path)) {
        return("unknown R installation")
      }

      idx <- match(path, routes$rscript_path)
      if (is.na(idx)) {
        return("selected R installation")
      }

      r_label(path, routes$version[[idx]])
    }

    # Installations eligible as a *target* for a given source: any OTHER
    # installation whose R version is the same or newer than the source. Package
    # transfer only ever goes source → (same-or-newer) target, because an older
    # R cannot reliably hold packages built for / requiring a newer R. Unknown
    # versions stay eligible (online mode adapts to whatever the target is).
    valid_targets <- function(src) {
      r <- routes_data()
      if (is.null(src) || !nzchar(src) || nrow(r) == 0) return(r[0, , drop = FALSE])
      src_v <- tryCatch(package_version(route_version(src)), error = function(e) NULL)
      keep <- vapply(seq_len(nrow(r)), function(i) {
        path <- r$rscript_path[[i]]
        if (identical(path, src)) return(FALSE)
        tv <- tryCatch(package_version(as.character(r$version[[i]])), error = function(e) NULL)
        if (is.null(src_v) || is.null(tv)) return(TRUE)
        tv >= src_v
      }, logical(1))
      r[keep, , drop = FALSE]
    }

    normalize_manifest <- function(pkgs) {
      dt <- data.table::as.data.table(pkgs)

      if (ncol(dt) == 0) {
        return(data.table::data.table(
          package = character(),
          version = character(),
          priority = character(),
          source = character()
        ))
      }

      if (!"priority" %in% names(dt)) {
        data.table::set(dt, j = "priority", value = rep(NA_character_, nrow(dt)))
      }
      if (!"source" %in% names(dt)) {
        data.table::set(dt, j = "source", value = rep(NA_character_, nrow(dt)))
      }

      dt <- dt[is.na(dt[["priority"]]) | !(dt[["priority"]] %in% c("base", "recommended")), ]
      dt[, c("package", "version", "source"), with = FALSE]
    }

    build_sync_comparison <- function(a_pkgs, b_pkgs) {
      a_dt <- normalize_manifest(a_pkgs)
      b_dt <- normalize_manifest(b_pkgs)

      comp <- data.table::merge.data.table(
        a_dt,
        b_dt,
        by = "package",
        all = TRUE,
        suffixes = c(".a", ".b")
      )

      data.table::setnames(comp, c("version.a", "version.b"), c("version_in_a", "version_in_b"))
      if ("source.a" %in% names(comp)) {
        data.table::setnames(comp, "source.a", "source_in_a")
      }
      if ("source.b" %in% names(comp)) {
        data.table::setnames(comp, "source.b", "source_in_b")
      }

      status <- rep("same", nrow(comp))
      missing_b <- is.na(comp[["version_in_b"]]) & !is.na(comp[["version_in_a"]])
      missing_a <- is.na(comp[["version_in_a"]]) & !is.na(comp[["version_in_b"]])
      status[missing_b] <- "missing-from-B"
      status[missing_a] <- "missing-from-A"

      both_present <- !is.na(comp[["version_in_a"]]) & !is.na(comp[["version_in_b"]])
      if (any(both_present)) {
        ver_a <- package_version(comp[["version_in_a"]][both_present])
        ver_b <- package_version(comp[["version_in_b"]][both_present])
        both_status <- rep("same", sum(both_present))
        both_status[ver_a > ver_b] <- "newer-in-A"
        both_status[ver_b > ver_a] <- "newer-in-B"
        status[both_present] <- both_status
      }

      data.table::set(comp, j = "status", value = status)
      status_rank <- match(
        comp[["status"]],
        c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B", "same")
      )
      comp <- comp[order(status_rank, comp[["package"]]), ]
      comp[]
    }

    # Packages to push source → target: those missing from, or older in, the
    # target. (Packages only in / newer in the target are never touched — the
    # transfer is one-directional.)
    packages_for_direction <- function(comp) {
      comp[["package"]][comp[["status"]] %in% c("missing-from-B", "newer-in-A")]
    }

    # Build the single source → target ship() batch from a comparison.
    build_batches <- function(comp, source_path, target_path) {
      pkgs <- packages_for_direction(comp)
      if (length(pkgs) == 0) return(list())
      list(list(label = "source to target", source_path = source_path,
                target_path = target_path, packages = pkgs))
    }

    estimate_sync_time <- function(package_count) {
      if (package_count <= 0) {
        return("less than 1 minute")
      }

      # ~8-25 seconds per package via pak (network + compile)
      min_minutes <- ceiling(max(1, package_count * 8 / 60))
      max_minutes <- ceiling(max(min_minutes + 1, package_count * 25 / 60))

      sprintf("%d-%d minutes", min_minutes, max_minutes)
    }

    # Classify the packages of one batch into cost tiers, mirroring ship()'s
    # logic, to produce the pre-ship "invoice". Returns a one-row list of counts
    # and an estimated number of seconds.
    #   copy   — pure-R or local: copied directly (no download, no compile)
    #   binary — compiled CRAN package: reinstalled from a pre-built binary
    #   source — compiled Bioconductor/GitHub: must compile from source (slow)
    invoice_batch <- function(packages, source_path, mode) {
      n <- length(packages)
      if (n == 0) return(list(copy = 0L, binary = 0L, source = 0L, secs = 0))
      if (mode %in% c("offline", "preserve")) {
        return(list(copy = n, binary = 0L, source = 0L, secs = n * 0.5))
      }
      src <- data.table::as.data.table(get_manifest(source_path))
      rows <- src[match(packages, src$package), ]
      libpath <- if ("libpath" %in% names(rows)) rows$libpath else rep(NA_character_, n)
      src_col <- if ("source" %in% names(rows)) rows$source else rep(NA_character_, n)
      compiled <- !is.na(libpath) & nzchar(libpath) & file.exists(file.path(libpath, "libs"))
      resolvable <- !is.na(src_col) & src_col %in% c("CRAN", "Bioconductor", "GitHub")
      needs_pak  <- resolvable & compiled
      is_source  <- needs_pak & src_col %in% c("Bioconductor", "GitHub")
      is_binary  <- needs_pak & !is_source
      is_copy    <- !needs_pak
      list(
        copy   = sum(is_copy),
        binary = sum(is_binary),
        source = sum(is_source),
        secs   = sum(is_copy) * 0.5 + sum(is_binary) * 5 + sum(is_source) * 45
      )
    }

    # Aggregate the invoice across the source → target batch of a pending plan.
    build_invoice <- function(plan, mode) {
      batches <- list(list(packages = plan$packages, source_path = plan$source_path))
      tot <- list(copy = 0L, binary = 0L, source = 0L, secs = 0)
      for (b in batches) {
        inv <- invoice_batch(b$packages, b$source_path, mode)
        tot$copy   <- tot$copy   + inv$copy
        tot$binary <- tot$binary + inv$binary
        tot$source <- tot$source + inv$source
        tot$secs   <- tot$secs   + inv$secs
      }
      tot
    }

    # One concrete sentence stating exactly what the ship will do, by action,
    # so the plan is specific rather than a general mode description. Only
    # non-zero actions are listed. Mirrors the route tiers from invoice_batch().
    action_summary_ui <- function(n_copy, n_binary, n_source) {
      parts <- character(0)
      if (n_copy   > 0) parts <- c(parts, sprintf("copy %d directly", n_copy))
      if (n_binary > 0) parts <- c(parts, sprintf("reinstall %d via pak", n_binary))
      if (n_source > 0) parts <- c(parts, sprintf("compile %d from source", n_source))
      if (length(parts) == 0) return(NULL)
      tags$div(
        class = "ship-plan-summary",
        tags$span(class = "ship-plan-summary-lead", "This will "),
        paste(parts, collapse = " · ")
      )
    }

    fmt_duration <- function(secs) {
      if (secs < 60) return(sprintf("~%ds", round(secs)))
      mins <- secs / 60
      if (mins < 60) return(sprintf("~%d min", max(1, round(mins))))
      sprintf("~%.1f h", mins / 60)
    }

    log_libpaths <- function(label, pkgs) {
      if (is.null(pkgs) || !"libpath" %in% names(pkgs) || nrow(pkgs) == 0) {
        add_sync_log(label, ": no packages found.")
        return(invisible(NULL))
      }
      libs <- unique(pkgs$libpath)
      add_sync_log(sprintf("%s: %d package(s) across %d librar%s:",
                           label, nrow(pkgs), length(libs),
                           if (length(libs) == 1) "y" else "ies"))
      for (lib in libs) add_sync_log("    ", lib)
      invisible(NULL)
    }

    refresh_comparison <- function(a_path, b_path, progress_detail = "Refreshing comparison", pct_base = 0, pct_span = 100) {
      set_sync_progress(pct_base, progress_detail, active = TRUE)
      add_sync_log(progress_detail, ".")
      add_sync_log("Source: ", route_display(a_path))
      add_sync_log("Target: ", route_display(b_path))
      set_sync_progress(pct_base + pct_span * 0.2, "Scanning source installation", active = TRUE)
      a_pkgs <- get_manifest(a_path)
      log_libpaths("Source library", a_pkgs)
      set_sync_progress(pct_base + pct_span * 0.55, "Scanning target installation", active = TRUE)
      b_pkgs <- get_manifest(b_path)
      log_libpaths("Target library", b_pkgs)
      if (identical(sort(unique(a_pkgs$libpath)), sort(unique(b_pkgs$libpath)))) {
        add_sync_log("WARNING: both installations resolve to the SAME library path. ",
                     "They share a package library (likely via R_LIBS_USER in .Renviron), ",
                     "so every package will compare as identical.")
      }
      set_sync_progress(pct_base + pct_span * 0.8, "Building comparison", active = TRUE)
      comparison_data(build_sync_comparison(a_pkgs, b_pkgs))
      set_sync_progress(pct_base + pct_span, "Comparison ready", active = TRUE)
    }

    apply_routes <- function(r) {
      routes_data(r)
      detection_status(sprintf("Detection complete: found %d installation(s).", nrow(r)))
      add_sync_log(sprintf("Detection complete: found %d installation(s).", nrow(r)))
      if (nrow(r) == 0) {
        showNotification("No R installations detected.", type = "warning")
        updateSelectInput(session, "install_a", choices = character(0), selected = character(0))
        updateSelectInput(session, "install_b", choices = character(0), selected = character(0))
      } else {
        labels <- mapply(r_label, r$rscript_path, r$version)
        choices <- stats::setNames(r$rscript_path, labels)

        current_a <- isolate(input$install_a)
        current_b <- isolate(input$install_b)

        # Routes are sorted newest-first. Default source to the OLDEST install
        # and target to the newest — the common "carry packages up to my newest
        # R" case — so a valid same-or-newer target is always preselected (the
        # target-filter observer then keeps install_b constrained to the source).
        selected_a <- if (!is.null(current_a) && nzchar(current_a) && current_a %in% r$rscript_path) {
          current_a
        } else {
          r$rscript_path[[nrow(r)]]
        }

        selected_b <- if (!is.null(current_b) && nzchar(current_b) && current_b %in% r$rscript_path && !identical(current_b, selected_a)) {
          current_b
        } else {
          r$rscript_path[[1]]
        }

        updateSelectInput(session, "install_a", choices = choices, selected = selected_a)
        updateSelectInput(session, "install_b", choices = choices, selected = selected_b)
      }
      detecting(FALSE)
    }

    load_routes <- function() {
      detecting(TRUE)
      detection_status(NULL)
      manifest_cache(list())  # fresh detection → drop any cached library scans
      add_sync_log("Scanning for R installations...")
      tryCatch({
        r <- sort_routes(courieR::find_routes())
        apply_routes(r)
      }, error = function(e) {
        detection_status("Detection failed. See error details below.")
        add_sync_log("Detection failed: ", e$message)
        showNotification(paste("Route scan failed:", e$message), type = "error")
        if (is.function(push_error)) push_error(e$message, context = "Detecting R installations")
        detecting(FALSE)
      })
    }


    output$install_a_badge <- renderUI({
      a_version <- route_version(input$install_a)
      div(
        class = "sync-install-meta sync-install-meta-a",
        shiny::HTML(r_badge(a_version, "a"))
      )
    })

    output$install_b_badge <- renderUI({
      b_version <- route_version(input$install_b)
      div(
        class = "sync-install-meta sync-install-meta-b",
        shiny::HTML(r_badge(b_version, "b"))
      )
    })

    output$detecting_msg <- renderUI({
      if (detecting()) {
        return(div(
          class = "sync-detecting-sidebar",
          role = "status",
          tags$div(class = "sync-detecting-pulse"),
          tags$div(class = "sync-detecting-text", "Scanning for R installations…")
        ))
      }
      NULL
    })

    route_location <- function(path) {
      if (grepl("AppData", path, ignore.case = TRUE)) return("AppData")
      if (grepl("Program Files", path, ignore.case = TRUE)) return("Program Files")
      if (grepl("Documents", path, ignore.case = TRUE)) return("Documents")
      if (grepl("homebrew|Cellar", path, ignore.case = TRUE)) return("Homebrew")
      if (grepl("/opt/R/", path)) return("rig")
      if (grepl("\\.local/share/rig", path)) return("rig (user)")
      if (grepl("conda", path, ignore.case = TRUE)) return("conda")
      if (grepl("Library/Frameworks", path)) return("Framework")
      basename(dirname(dirname(path)))
    }

    output$detected_installs <- renderUI({
      if (detecting()) return(NULL)
      routes <- routes_data()
      if (nrow(routes) == 0) return(NULL)

      sel_a <- input$install_a
      sel_b <- input$install_b

      tags$div(
        class = "sidebar-installs",
        tags$div(class = "sidebar-installs-label", "Installations found:"),
        lapply(seq_len(nrow(routes)), function(i) {
          path <- routes$rscript_path[[i]]
          bucket <- if (!is.null(sel_a) && identical(path, sel_a)) "a"
                    else if (!is.null(sel_b) && identical(path, sel_b)) "b"
                    else ""
          extra_cls <- if (nzchar(bucket)) paste0("sidebar-install-", bucket) else ""
          tags$div(
            class = paste("sidebar-install-row", extra_cls),
            tags$span(class = "sidebar-install-version",
              sprintf("R %s", routes$version[[i]])),
            tags$span(class = "sidebar-install-loc",
              route_location(path))
          )
        })
      )
    })

    output$comparison_summary <- renderUI({
      comp <- comparison_data()
      if (is.null(comp) || nrow(comp) == 0) return(NULL)
      a_version <- route_version(input$install_a)
      b_version <- route_version(input$install_b)

      counts <- table(comp[["status"]])
      filter_state <- selected_statuses()
      make_chip <- function(status, label, css_extra = "") {
        n <- as.integer(counts[status])
        if (is.na(n) || n == 0) return(NULL)
        is_active <- is.null(filter_state) || status %in% filter_state
        tags$span(
          class = paste("sync-summary-chip", if (is_active) "chip-active" else "", css_extra),
          `data-status` = status,
          onclick = sprintf("courierChipClick(this, '%s', '%s')", status, ns("filter_statuses")),
          tags$strong(n), " × ", label
        )
      }

      a_lbl <- if (!is.na(a_version)) paste("newer in R", a_version) else "newer in A"
      b_lbl <- if (!is.na(b_version)) paste("newer in R", b_version) else "newer in B"
      na_lbl <- if (!is.na(a_version)) paste("not in R", a_version) else "missing from A"
      nb_lbl <- if (!is.na(b_version)) paste("not in R", b_version) else "missing from B"

      hint_ui <- if (any(comp[["status"]] != "same")) {
        tags$p(
          class = "depot-ship-hint",
          "Cherry-pick packages → ",
          tags$a(
            href    = "#",
            onclick = "navigateToDepotShip(); return false;",
            "Advanced › Depot › Ship"
          )
        )
      } else NULL

      div(
        class = "sync-summary-wrap",
        div(
          class = "sync-summary-bar",
          make_chip("same",           "identical",  "chip-same"),
          make_chip("newer-in-A",     a_lbl,        "chip-diff-a"),
          make_chip("newer-in-B",     b_lbl,        "chip-diff-b"),
          make_chip("missing-from-B", nb_lbl,       "chip-diff-a"),
          make_chip("missing-from-A", na_lbl,       "chip-diff-b")
        ),
        hint_ui
      )
    })

    format_log_entry <- function(entry) {
      if (startsWith(entry, "[ERR] ")) {
        clean <- htmltools::htmlEscape(substr(entry, 7L, nchar(entry)))
        sprintf('<span class="sync-log-error">%s</span>', clean)
      } else {
        htmltools::htmlEscape(entry)
      }
    }

    output$sync_log <- renderUI({
      entries <- sync_log()
      active <- sync_active()
      pct <- sync_pct()
      step <- sync_step()

      progress_ui <- if (active) {
        tags$div(
          class = "sync-inline-progress",
          tags$div(class = "sync-progress-label", step),
          tags$div(
            class = "progress",
            tags$div(
              class = "progress-bar progress-bar-striped progress-bar-animated",
              role = "progressbar",
              style = sprintf("width: %.0f%%;", pct),
              `aria-valuenow` = sprintf("%.0f", pct),
              `aria-valuemin` = "0",
              `aria-valuemax` = "100",
              sprintf("%.0f%%", pct)
            )
          )
        )
      } else {
        NULL
      }

      empty_text <- "Scanning installations… then click Compare. Activity appears here."
      tags$div(
        class = paste("sync-log", if (length(entries) == 0) "sync-log-empty" else ""),
        tags$div(
          class = "sync-log-title",
          "Log panel",
          tags$span(
            class = "sync-log-subtitle",
            if (length(entries) == 0) "Waiting for activity" else "Detection, package actions, and post-sync comparison refresh"
          )
        ),
        progress_ui,
        tags$pre(
          id = ns("sync_log_pre"),
          `data-empty` = if (length(entries) == 0) "true" else NULL,
          if (length(entries) == 0) {
            empty_text
          } else {
            HTML(paste(
              vapply(rev(utils::tail(entries, 250)), format_log_entry, character(1)),
              collapse = "\n"
            ))
          }
        )
      )
    })

    # No automatic detection on startup — the user clicks Detect (see observer
    # below), which calls load_routes() and shares the result via routes_cache.

    observeEvent(input$install_a, {
      if (is.function(install_a_path)) {
        install_a_path(input$install_a)
      }
      comparison_data(NULL)
    }, ignoreNULL = FALSE)

    observeEvent(input$install_b, {
      if (is.function(install_b_path)) {
        install_b_path(input$install_b)
      }
      comparison_data(NULL)
    }, ignoreNULL = FALSE)

    # Keep the target dropdown limited to same-or-newer installations whenever
    # the source changes (or installations are re-detected). Preserve the
    # current target if it is still eligible, otherwise pick the first valid one.
    observe({
      src <- input$install_a
      valid <- valid_targets(src)
      if (nrow(valid) == 0) {
        updateSelectInput(session, "install_b", choices = character(0), selected = character(0))
        return()
      }
      labels  <- mapply(r_label, valid$rscript_path, valid$version)
      choices <- stats::setNames(valid$rscript_path, labels)
      current_b <- isolate(input$install_b)
      sel <- if (!is.null(current_b) && current_b %in% valid$rscript_path) current_b else valid$rscript_path[[1]]
      updateSelectInput(session, "install_b", choices = choices, selected = sel)
    })

    # Hint shown under the target dropdown when the chosen source is the newest
    # installation, so there is nowhere same-or-newer to ship into.
    output$install_b_target_hint <- renderUI({
      src <- input$install_a
      if (is.null(src) || !nzchar(src) || nrow(routes_data()) == 0) return(NULL)
      if (nrow(valid_targets(src)) > 0) return(NULL)
      tags$div(
        class = "sync-target-hint",
        "No same-or-newer R installation to ship into. Packages only transfer to an equal or newer R version."
      )
    })

    # Direction is fixed source → target; expose the constant for shared modules.
    observe({
      if (is.function(sync_direction_out)) sync_direction_out("A_to_B")
    })
    observe({
      if (is.function(transfer_mode_out))
        transfer_mode_out(input$transfer_mode %||% "online")
    })

    # Disable sync controls when there is nothing to transfer (all packages identical).
    observe({
      comp <- comparison_data()
      all_same <- !is.null(comp) && nrow(comp) > 0 && all(comp[["status"]] == "same")
      shinyjs::toggleState("transfer_mode",  condition = !all_same)
      shinyjs::toggleState("sync_btn",       condition = !all_same)
    })

    re_enable_btn <- function(input_id) {
      shinyjs::runjs(sprintf(
        "var b = document.getElementById('%s'); if (b) b.disabled = false;",
        ns(input_id)
      ))
    }
    disable_btn <- function(input_id) {
      shinyjs::runjs(sprintf(
        "var b = document.getElementById('%s'); if (b) b.disabled = true;",
        ns(input_id)
      ))
    }
    re_enable_compare <- function() re_enable_btn("compare")

    # Stop the client-side elapsed timer and hide the progress bar. Used on exit
    # paths that don't go through set_sync_progress(active = FALSE) — e.g. early
    # returns and Restock, whose buttons start the timer on click.
    stop_busy <- function() {
      shinyjs::runjs(
        "if(window.courierStopTimer) window.courierStopTimer();
         var b=document.getElementById('nav-progress-bar'); if(b) b.style.width='100%';
         var w=document.getElementById('nav-progress-wrap');
         setTimeout(function(){ if(w) w.style.display='none'; if(b) b.style.width='0%'; }, 1200);
         var sb=document.querySelector('.sync-sidebar'); if(sb) sb.classList.remove('sync-busy');"
      )
    }

    # The three transfer modes are the complete, mutually-exclusive set of ways
    # ship() moves packages. Kept in one place so the UI can list them all.
    transfer_modes <- list(
      online = list(
        label = "Online reinstall",
        desc  = "Best when moving between different R versions. Only compiled packages are rebuilt for the target R via pak (latest compatible version, dependencies resolved). Pure-R packages and local/unknown packages are copied directly from the source — no download or compile, since they are not version-specific. Needs internet for the rebuilt packages."
      ),
      offline = list(
        label = "Offline copy",
        desc  = "Copy package files directly from the source library — fast, no internet, exact same versions. Safe only within the same R x.y series (copying compiled packages across R minor versions can break them)."
      ),
      preserve = list(
        label = "Preserve version",
        desc  = "Same direct copy as Offline, but anything that can't be copied is reinstalled via pak at its exact source version. A network safety net for same-series syncs."
      )
    )
    # Copy-based modes are only safe within the same compiled-ABI series; online
    # works across any versions.
    copy_modes <- c("offline", "preserve")

    mode_description <- function(mode) {
      m <- transfer_modes[[mode %||% "online"]]
      if (is.null(m)) "Packages are transferred using the selected mode." else m$desc
    }

    # "Mode: <label> — <full explanation>" for the modals, which have room for
    # the complete description (the sidebar uses the compact "?" tooltip).
    mode_note_ui <- function(mode) {
      m <- transfer_modes[[mode %||% "online"]]
      label <- if (is.null(m)) "selected mode" else m$label
      tagList(
        tags$strong(paste0("Mode: ", label)),
        tags$div(class = "modal-ship-mode-desc", mode_description(mode))
      )
    }

    # TRUE when both installations share the same R major.minor (e.g. both 4.5.x),
    # where binary packages are compatible and direct copying is safe. NA/unknown
    # versions are treated as NOT compatible (conservative — online only).
    same_abi_series <- function(va, vb) {
      if (is.na(va) || is.na(vb) || !nzchar(va) || !nzchar(vb)) return(FALSE)
      pa <- tryCatch(package_version(va), error = function(e) NULL)
      pb <- tryCatch(package_version(vb), error = function(e) NULL)
      if (is.null(pa) || is.null(pb)) return(FALSE)
      ca <- unclass(pa)[[1]]; cb <- unclass(pb)[[1]]
      length(ca) >= 2 && length(cb) >= 2 && identical(ca[1:2], cb[1:2])
    }

    copy_compatible <- reactive({
      same_abi_series(route_version(input$install_a), route_version(input$install_b))
    })

    available_modes <- reactive({
      if (isTRUE(copy_compatible())) names(transfer_modes) else "online"
    })

    # Offer copy/preserve only when the selected installations are copy-safe.
    observe({
      avail <- available_modes()
      choices <- stats::setNames(
        avail,
        vapply(avail, function(m) transfer_modes[[m]]$label, character(1))
      )
      current <- isolate(input$transfer_mode) %||% "online"
      # Default to Offline when copy is available — it is far faster than an
      # online reinstall. Keep an explicit copy-mode pick the user already made.
      sel <- if (current %in% avail && current != "online") {
        current
      } else if (isTRUE(copy_compatible())) {
        "offline"
      } else {
        "online"
      }
      updateSelectInput(session, "transfer_mode", choices = choices, selected = sel)
    })

    # A small "?" badge beside the Transfer mode label; hovering (or focusing)
    # shows the selected mode's explanation as a Bootstrap tooltip, so the
    # description no longer takes a block of space under the dropdown. Full mode
    # reference and the version-compatibility rules live in the manual.
    output$transfer_mode_help <- renderUI({
      bslib::tooltip(
        tags$span(class = "sync-help-badge", tabindex = "0", "?"),
        mode_description(input$transfer_mode),
        placement = "right"
      )
    })

    # Auto-scan on startup — defer 50 ms so the detecting animation renders before blocking.
    observeEvent(TRUE, {
      set_sync_progress(0, "Detecting R installations", active = TRUE)
      shinyjs::delay(50, {
        load_routes()
        if (is.function(routes_cache)) routes_cache(isolate(routes_data()))
        set_sync_progress(100, "Detection complete", active = FALSE)
      })
    }, once = TRUE, ignoreNULL = FALSE)

    observeEvent(input$compare, {
      a_path <- input$install_a
      b_path <- input$install_b

      if (is.null(a_path) || !nzchar(a_path) || is.null(b_path) || !nzchar(b_path)) {
        re_enable_compare()
        stop_busy()
        showNotification("Select a source and a target installation first.", type = "warning")
        return()
      }

      if (identical(a_path, b_path)) {
        re_enable_compare()
        stop_busy()
        showNotification("Source and target must be different installations.", type = "warning")
        return()
      }

      if (is.function(comparison_out))  comparison_out(NULL)
      if (is.function(actionable_out))  actionable_out(0L)
      last_ship_result(NULL)

      selected_statuses(NULL)
      add_sync_log("─────── Compare ───────")
      add_sync_log("Starting comparison…")
      set_sync_progress(0, "Comparing installations", active = TRUE)

      tryCatch({
        refresh_comparison(a_path, b_path, progress_detail = "Starting comparison")
        comp <- comparison_data()
        diff_statuses <- c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B")
        if (!is.null(comp) && any(comp[["status"]] %in% diff_statuses)) {
          selected_statuses(diff_statuses)
        }
        if (is.function(comparison_out)) comparison_out(comparison_data())
        diff_n <- sum(comparison_data()[["status"]] != "same")
        if (is.function(actionable_out)) actionable_out(diff_n)
        set_sync_progress(100, "Comparison ready", active = FALSE)
      }, error = function(e) {
        set_sync_progress(0, "Comparison failed", active = FALSE)
        add_sync_log("Comparison failed: ", e$message)
        showNotification(paste("Comparison failed:", e$message), type = "error", duration = NULL)
        if (is.function(push_error)) push_error(e$message, context = "Comparing R libraries")
      })

      re_enable_compare()
    })

    observeEvent(input$filter_statuses, {
      vals <- input$filter_statuses
      if (is.null(vals) || length(vals) == 0) {
        selected_statuses(NULL)
      } else {
        selected_statuses(vals)
      }
    }, ignoreNULL = FALSE, ignoreInit = TRUE)

    sync_comparison <- reactive({
      comp <- comparison_data()
      filter <- selected_statuses()
      if (is.null(filter) || is.null(comp)) return(comp)
      comp[comp[["status"]] %in% filter, ]
    })

    # Map a ship() per-package status/message to a plain verb for the Result
    # column. Plain text (not HTML) so the column can use a select-dropdown
    # filter; colour is applied separately via formatStyle.
    result_levels <- c("installed", "updated", "copied", "synced", "failed", "skipped")
    result_label <- function(status, message) {
      message <- message %||% ""
      if (identical(status, "error"))   return("failed")
      if (identical(status, "skipped")) return("skipped")
      if (grepl("^Installed", message)) return("installed")
      if (grepl("^Upgraded", message))  return("updated")
      if (grepl("copied", message, ignore.case = TRUE)) return("copied")
      "synced"
    }

    output$comparison_table <- DT::renderDataTable({
      comp <- sync_comparison()
      if (is.null(comp)) {
        return(DT::datatable(
          data.frame(
            package = character(),
            version_in_a = character(),
            version_in_b = character(),
            status = character()
          ),
          filter = "top",
          options = list(dom = "ft"),
          caption = htmltools::tags$caption("Select two installations and click Compare.")
        ))
      }

      a_version <- route_version(input$install_a)
      b_version <- route_version(input$install_b)
      raw_status <- comp[["status"]]
      a_lbl <- if (is.na(a_version)) "A" else paste0("R ", a_version)
      b_lbl <- if (is.na(b_version)) "B" else paste0("R ", b_version)
      status_labels <- raw_status
      status_labels[raw_status == "same"]           <- "same"
      status_labels[raw_status == "newer-in-A"]     <- paste0("newer in ", a_lbl)
      status_labels[raw_status == "newer-in-B"]     <- paste0("newer in ", b_lbl)
      status_labels[raw_status == "missing-from-A"] <- paste0("not in ", a_lbl)
      status_labels[raw_status == "missing-from-B"] <- paste0("not in ", b_lbl)

      # Source: a package's source is the same in either installation; take
      # whichever side reported it, defaulting to "unknown".
      src_a <- if ("source_in_a" %in% names(comp)) comp[["source_in_a"]] else rep(NA_character_, nrow(comp))
      src_b <- if ("source_in_b" %in% names(comp)) comp[["source_in_b"]] else rep(NA_character_, nrow(comp))
      source_col <- ifelse(!is.na(src_a) & nzchar(src_a), src_a, src_b)
      source_col <- ifelse(is.na(source_col) | !nzchar(source_col), "unknown", source_col)

      # Result: per-package outcome from the most recent ship(), joined by name.
      # Blank for untouched / "same" packages; failure reason shown on hover.
      result_col <- rep("", nrow(comp))
      res_obj <- last_ship_result()
      if (!is.null(res_obj) && !is.null(res_obj$results) && nrow(res_obj$results) > 0) {
        rr <- res_obj$results
        idx <- match(comp[["package"]], rr$package)
        result_col <- vapply(seq_along(idx), function(i) {
          j <- idx[i]
          if (is.na(j)) return("")
          result_label(rr$status[[j]], rr$message[[j]])
        }, character(1))
      }

      # factor() on source/result makes DT render a select-dropdown filter for
      # those columns (instead of a free-text search box).
      display <- data.frame(
        package = comp[["package"]],
        source = factor(source_col),
        version_in_a = ifelse(is.na(comp[["version_in_a"]]), "not installed", comp[["version_in_a"]]),
        version_in_b = ifelse(is.na(comp[["version_in_b"]]), "not installed", comp[["version_in_b"]]),
        status = factor(status_labels),
        result = factor(result_col, levels = c("", result_levels)),
        status_raw = raw_status,
        status_rank = match(raw_status, c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B", "same")),
        stringsAsFactors = FALSE
      )

      diff_statuses <- c("missing-from-B", "missing-from-A", "newer-in-A", "newer-in-B")

      DT::datatable(
        display,
        rownames = FALSE,
        escape = TRUE,
        width = "100%",
        colnames = c(
          "Package",
          "Source",
          paste0("Version in ", a_lbl),
          paste0("Version in ", b_lbl),
          "Status",
          "Result",
          "status_raw",
          "status_rank"
        ),
        filter = "top",
        options = list(
          pageLength = 50,
          lengthMenu = c(25, 50, 100, -1),
          scrollX = FALSE,
          autoWidth = FALSE,
          dom = "rt<'sync-table-foot'lip>",
          order = list(list(7, "asc"), list(0, "asc")),
          columnDefs = list(list(targets = c(6, 7), visible = FALSE))
        ),
        class = "stripe hover compact sync-table"
      ) |>
        DT::formatStyle(
          "status_raw",
          target = "row",
          backgroundColor = DT::styleEqual(
            c("same", diff_statuses),
            c("#ffffff", "#fff6ef", "#eefafb", "#fff4ea", "#edf8fb")
          )
        ) |>
        DT::formatStyle(
          "status_raw",
          target = "row",
          fontWeight = DT::styleEqual(
            c("same", diff_statuses),
            c("400", "600", "600", "600", "600")
          )
        ) |>
        DT::formatStyle(
          "result",
          fontWeight = 650,
          color = DT::styleEqual(
            c("installed", "updated", "copied", "synced", "failed", "skipped"),
            c("#1f7a4d", "#1f7a4d", "#1f7a4d", "#1f7a4d", "#c0392b", "#6d879b")
          )
        )
    })

    show_sync_confirmation <- function(plan) {

      package_count <- length(plan$packages)

      inv <- build_invoice(plan, input$transfer_mode)

      line <- function(label, n, klass, hint) {
        if (n <= 0) return(NULL)
        div(
          class = paste("invoice-line", klass),
          tags$span(class = "invoice-qty", n),
          tags$span(class = "invoice-label", label),
          tags$span(class = "invoice-hint", hint)
        )
      }

      showModal(modalDialog(
        title = span(style = "font-weight:800; color:#2c1e6e;", "Confirm Ship"),
        div(
          style = "padding: 0.25rem 0;",
          div(
            class = "modal-ship-pkg-count",
            sprintf("%d package%s", package_count, if (package_count == 1) "" else "s")
          ),
          action_summary_ui(inv$copy, inv$binary, inv$source),
          div(class = "modal-ship-mode", mode_note_ui(input$transfer_mode)),
          # ── Invoice: itemised cost estimate ──
          div(
            class = "invoice-card",
            div(class = "invoice-head", "Estimate"),
            line("to be copied",   inv$copy,   "invoice-copy",   "pure-R / local — no download or compile"),
            line("to be installed", inv$binary, "invoice-binary", "compiled CRAN — pre-built binary"),
            line("to be compiled",  inv$source, "invoice-source", "Bioconductor / GitHub — slow"),
            div(
              class = "invoice-total",
              tags$span("Estimated time"),
              tags$span(class = "invoice-total-val", fmt_duration(inv$secs))
            )
          )
        ),
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton(ns("confirm_sync"), "Ship", class = "btn-primary",
            onclick = "if(window.courierStartTimer) window.courierStartTimer();",
            style = "background: linear-gradient(90deg,#5f4ab4 0%,#8a52c8 100%); border:0; font-weight:800;")
        )
      ))
    }

    observeEvent(input$sync_btn, {
      comp <- sync_comparison()
      if (is.null(comp)) {
        showNotification("Run Compare first.", type = "warning")
        return()
      }

      packages <- packages_for_direction(comp)
      if (length(packages) == 0) {
        showNotification("The target already has every source package at the same or newer version.", type = "message")
        return()
      }
      pending_sync(list(
        type        = "source_to_target",
        source_path = input$install_a,
        target_path = input$install_b,
        packages    = packages
      ))
      show_sync_confirmation(pending_sync())
    })

    # Per-package route classification for the preview (mirrors ship() logic).
    classify_packages <- function(packages, source_path, mode) {
      n <- length(packages)
      if (n == 0) return(data.frame(package = character(), route = character(), stringsAsFactors = FALSE))
      if (mode %in% c("offline", "preserve")) {
        return(data.frame(package = packages, route = "copied", stringsAsFactors = FALSE))
      }
      src <- data.table::as.data.table(get_manifest(source_path))
      rows <- src[match(packages, src$package), ]
      libpath <- if ("libpath" %in% names(rows)) rows$libpath else rep(NA_character_, n)
      src_col <- if ("source" %in% names(rows)) rows$source else rep(NA_character_, n)
      compiled   <- !is.na(libpath) & nzchar(libpath) & file.exists(file.path(libpath, "libs"))
      resolvable <- !is.na(src_col) & src_col %in% c("CRAN", "Bioconductor", "GitHub")
      needs_pak  <- resolvable & compiled
      route <- ifelse(!needs_pak, "copied",
                ifelse(src_col %in% c("Bioconductor", "GitHub"), "compiled from source", "binary install"))
      data.frame(package = packages, route = route, stringsAsFactors = FALSE)
    }

    preview_rows <- reactiveVal(NULL)

    # Preview: classify what a sync would do and show it in a popup — no install,
    # nothing written to the log.
    observeEvent(input$preview_btn, {
      comp <- sync_comparison()
      if (is.null(comp)) {
        showNotification("Run Compare first.", type = "warning")
        return()
      }
      batches <- build_batches(comp, input$install_a, input$install_b)
      if (length(batches) == 0) {
        showNotification("Nothing to ship — the target already matches the source.", type = "message")
        return()
      }

      mode <- input$transfer_mode
      rows <- do.call(rbind, lapply(batches, function(b) {
        classify_packages(b$packages, b$source_path, mode)
      }))
      preview_rows(rows)

      n_copy   <- sum(rows$route == "copied")
      n_binary <- sum(rows$route == "binary install")
      n_source <- sum(rows$route == "compiled from source")
      secs     <- n_copy * 0.5 + n_binary * 5 + n_source * 45

      # Always render all three tiers so the preview answers "how many copied /
      # installed / compiled" at a glance; zero-count tiers are muted, not hidden.
      line <- function(label, n, klass, hint) {
        zero <- if (n <= 0) " invoice-line-zero" else ""
        div(class = paste0("invoice-line ", klass, zero),
            tags$span(class = "invoice-qty", n),
            tags$span(class = "invoice-label", label),
            tags$span(class = "invoice-hint", hint))
      }

      showModal(modalDialog(
        title = span(style = "font-weight:800; color:#2c1e6e;", "Transfer preview"),
        size = "l",
        easyClose = TRUE,
        div(
          action_summary_ui(n_copy, n_binary, n_source),
          div(class = "modal-ship-mode", mode_note_ui(mode)),
          div(
            class = "invoice-card",
            div(class = "invoice-head", "Estimate"),
            line("to be copied",   n_copy,   "invoice-copy",   "pure-R / local — no download or compile"),
            line("to be installed", n_binary, "invoice-binary", "compiled CRAN — pre-built binary"),
            line("to be compiled",  n_source, "invoice-source", "Bioconductor / GitHub — slow"),
            div(class = "invoice-total",
                tags$span("Estimated time"),
                tags$span(class = "invoice-total-val", fmt_duration(secs)))
          ),
          DT::dataTableOutput(ns("preview_dt"))
        ),
        footer = modalButton("Close")
      ))
    })

    output$preview_dt <- DT::renderDataTable({
      rows <- preview_rows()
      if (is.null(rows) || nrow(rows) == 0) {
        return(DT::datatable(data.frame(), options = list(dom = "t"), rownames = FALSE))
      }
      route_levels <- c("to be copied", "to be installed", "to be compiled")
      disp <- data.frame(
        package   = rows$package,
        route     = factor(rows$route,
                           levels = c("copied", "binary install", "compiled from source"),
                           labels = route_levels),
        stringsAsFactors = FALSE
      )
      DT::datatable(
        disp,
        rownames = FALSE,
        colnames = c("Package", "Route"),
        filter = "top",
        options = list(pageLength = 15, dom = "rt<'sync-table-foot'lip>"),
        class = "stripe hover compact"
      ) |>
        DT::formatStyle(
          "route",
          fontWeight = 650,
          color = DT::styleEqual(
            route_levels,
            c("#1f7a4d", "#2c6fb0", "#c0392b")
          )
        )
    })

    observeEvent(input$confirm_sync, {
      plan <- pending_sync()
      removeModal()

      if (is.null(plan)) {
        stop_busy()
        return()
      }

      # Lock Compare/Ship for the duration of the (potentially long) ship; both
      # are re-enabled at the end of this observer. The buttons were never
      # disabled on click — cancelling the modal leaves them usable.
      disable_btn("compare")
      disable_btn("sync_btn")

      add_sync_log("─────── Ship ───────")
      add_sync_log("Preparing sync plan.")
      add_sync_log("Tip: real-time output is shown in the RStudio console — monitor there, then return here for the summary.")
      add_sync_log("Base and recommended R packages are skipped; only user-installed packages are compared/synced.")
      add_sync_log("Current comparison before sync: ", comparison_counts_text(comparison_data()), ".")

      ship_start_time <- Sys.time()

      result <- tryCatch({
        set_sync_progress(5, "Preparing sync plan", active = TRUE)

        batches <- list(list(
          label = "source to target",
          source_path = plan$source_path,
          target_path = plan$target_path,
          packages = plan$packages
        ))

        total_count <- sum(vapply(batches, function(batch) length(batch$packages), integer(1)))
        failed_count <- 0L
        accumulated_results <- list()
        accumulated_plans   <- list()
        add_sync_log("Estimated sync time: ", estimate_sync_time(total_count), ".")
        batch_progress <- if (length(batches) == 0) 0 else 65 / length(batches)
        progress_start <- 10

        for (i in seq_along(batches)) {
          batch <- batches[[i]]
          package_preview <- paste(utils::head(batch$packages, 8), collapse = ", ")
          if (length(batch$packages) > 8) {
            package_preview <- paste0(package_preview, sprintf(", and %d more", length(batch$packages) - 8))
          }

          detail <- sprintf(
            "Installing %d package(s): %s",
            length(batch$packages),
            package_preview
          )
          set_sync_progress(progress_start + (i - 1L) * batch_progress, detail, active = TRUE)
          add_sync_log(sprintf(
            "Shipping %d package(s): %s → %s.",
            length(batch$packages),
            route_display(batch$source_path),
            route_display(batch$target_path)
          ))
          add_sync_log("Packages: ", paste(batch$packages, collapse = ", "))

          ship_result <- courieR::ship(
            source_path = batch$source_path,
            target_path = batch$target_path,
            packages = batch$packages,
            upgrade = TRUE,
            log_callback = add_sync_log,
            mode = input$transfer_mode,
            source_pkgs = get_manifest(batch$source_path),
            target_pkgs = get_manifest(batch$target_path)
          )
          # The target library changed — drop its cached scan so the post-sync
          # comparison re-scans it fresh.
          invalidate_manifest(batch$target_path)

          add_plan_log(ship_result)
          add_result_log(ship_result)

          if (!is.null(ship_result$results) && nrow(ship_result$results) > 0)
            accumulated_results[[i]] <- ship_result$results
          if (!is.null(ship_result$plan) && nrow(ship_result$plan) > 0)
            accumulated_plans[[i]] <- ship_result$plan

          if ("results" %in% names(ship_result) && nrow(ship_result$results) > 0) {
            failures <- ship_result$results[ship_result$results$status == "error", ]
            failed_count <- failed_count + nrow(failures)
            if (nrow(failures) > 0) {
              add_sync_log(sprintf(
                "Finished shipping with %d failure(s): %s.",
                nrow(failures),
                paste(failures$package, collapse = ", ")
              ))
            } else {
              add_sync_log("Finished shipping successfully.")
            }
          } else {
            add_sync_log("Finished shipping.")
          }

          set_sync_progress(progress_start + i * batch_progress, "Finished shipping", active = TRUE)
        }

        all_results <- if (length(accumulated_results) > 0)
          data.table::rbindlist(accumulated_results, fill = TRUE)
        else
          data.table::data.table(package = character(), status = character(), message = character())

        all_plans <- if (length(accumulated_plans) > 0)
          data.table::rbindlist(accumulated_plans, fill = TRUE)
        else
          data.table::data.table(package = character(), action = character())

        elapsed <- as.numeric(difftime(Sys.time(), ship_start_time, units = "secs"))
        last_ship_result(list(
          results     = all_results,
          plan        = all_plans,
          elapsed_sec = elapsed
        ))

        # Overall summary to the log panel (replaces the old receipt panel).
        if (nrow(all_results) > 0) {
          st  <- all_results$status
          msg <- all_results$message %||% rep("", length(st))
          n_installed <- sum(st == "success" & grepl("^Installed", msg))
          n_updated   <- sum(st == "success" & grepl("^Upgraded", msg))
          n_copied    <- sum(st == "success" & grepl("copied", msg, ignore.case = TRUE))
          n_other_ok  <- sum(st == "success") - n_installed - n_updated - n_copied
          n_failed    <- sum(st == "error")
          n_skipped   <- sum(st == "skipped")
          parts <- c(
            if (n_installed > 0) sprintf("%d installed", n_installed),
            if (n_updated   > 0) sprintf("%d updated",   n_updated),
            if (n_copied    > 0) sprintf("%d copied",    n_copied),
            if (n_other_ok  > 0) sprintf("%d synced",    n_other_ok),
            if (n_failed    > 0) sprintf("%d failed",    n_failed),
            if (n_skipped   > 0) sprintf("%d skipped",   n_skipped)
          )
          add_sync_log(sprintf(
            "Summary: %s  ·  %.1fs",
            if (length(parts) > 0) paste(parts, collapse = ", ") else "no changes",
            elapsed
          ))
        }

        set_sync_progress(80, "Refreshing comparison after sync", active = TRUE)
        add_sync_log("Refreshing comparison after sync.")
        refresh_comparison(
          input$install_a,
          input$install_b,
          progress_detail = "Refreshing comparison after sync",
          pct_base = 80,
          pct_span = 18
        )
        comp_after <- comparison_data()
        remaining <- if (is.null(comp_after)) {
          NA_integer_
        } else {
          sum(comp_after[["status"]] != "same")
        }
        set_sync_progress(100, "Ship complete", active = TRUE)
        add_sync_log("Post-sync comparison refreshed: ", comparison_counts_text(comp_after), ".")
        list(count = total_count, failed = failed_count, remaining = remaining)
      }, error = function(e) {
        set_sync_progress(0, "Ship failed", active = FALSE)
        add_sync_log("Ship failed: ", e$message)
        showNotification(paste("Ship failed:", e$message), type = "error", duration = NULL)
        if (is.function(push_error)) push_error(e$message, context = "Shipping packages")
        NULL
      })

      if (!is.null(result)) {
        add_sync_log(sprintf("Ship complete. %d package(s) processed.", result$count))
        if (result$failed > 0) {
          showNotification(
            sprintf("Ship finished with %d failed package(s). See the log panel.", result$failed),
            type = "warning",
            duration = NULL
          )
        } else if (!is.na(result$remaining) && result$remaining > 0) {
          showNotification(
            sprintf("Ship finished, but %d package difference(s) remain. See the log panel.", result$remaining),
            type = "warning",
            duration = NULL
          )
        } else {
          showNotification(sprintf("Sync complete. %d package(s) processed; comparison refreshed.", result$count), type = "message")
        }
        set_sync_progress(100, "Ship complete", active = FALSE)
      }

      pending_sync(NULL)
      # Clear the status filter so successfully-synced packages (now "same")
      # stay visible with their Result column populated.
      selected_statuses(NULL)
      re_enable_compare()
      re_enable_btn("sync_btn")
    })

    # Per-package outcomes now appear inline in the comparison table's Result
    # column; the overall summary is written to the log panel after each sync.

    # ── Restock ───────────────────────────────────────────────────────────
    restock_pending <- reactiveVal(NULL)

    do_restock <- function(path_fn, label) {
      path <- if (is.function(path_fn)) path_fn() else path_fn
      if (is.null(path) || !nzchar(path)) {
        showNotification("Select an installation in the Dispatch tab first.",
                         type = "warning")
        return()
      }
      pkgs <- tryCatch(
        courieR::manifest(rscript_path = path),
        error = function(e) {
          showNotification(paste("Scan failed:", e$message), type = "error")
          if (is.function(push_error))
            push_error(e$message, context = "Scanning packages for restock")
          NULL
        }
      )
      if (is.null(pkgs)) return()
      pkgs <- pkgs[is.na(pkgs$priority) |
                     !(pkgs$priority %in% c("base", "recommended")), ]
      cran_mask <- !is.na(pkgs$source) & pkgs$source == "CRAN"
      cran_pkgs <- pkgs$package[cran_mask]
      non_cran  <- pkgs[!cran_mask, ]

      restock_pending(list(path = path, label = label, cran_pkgs = cran_pkgs))

      warning_ui <- if (nrow(non_cran) > 0) {
        src_raw <- ifelse(
          is.na(non_cran$source) | non_cran$source == "unknown",
          "unknown / other", non_cran$source
        )
        src_tbl   <- sort(table(src_raw), decreasing = TRUE)
        src_items <- mapply(
          function(n, s) tags$li(sprintf("%d package(s) from %s", n, s)),
          as.integer(src_tbl), names(src_tbl), SIMPLIFY = FALSE
        )
        preview <- paste(head(non_cran$package, 8), collapse = ", ")
        if (nrow(non_cran) > 8)
          preview <- paste0(preview, sprintf(", … +%d more", nrow(non_cran) - 8))
        tags$div(
          class = "update-modal-warning",
          tags$p(tags$strong(sprintf(
            "%d package(s) will be skipped — not from CRAN:", nrow(non_cran)
          ))),
          tags$ul(class = "update-modal-warning-list", src_items),
          tags$p(class = "update-modal-warning-pkgs", preview),
          tags$p(class = "update-modal-warning-note",
                 "GitHub, Bioconductor, and unknown-source packages must be updated manually.")
        )
      } else NULL

      showModal(modalDialog(
        title = paste0("Restock ", label, " installation from CRAN"),
        if (length(cran_pkgs) > 0) {
          tags$p(sprintf("%d CRAN package(s) will be upgraded to their latest versions.",
                         length(cran_pkgs)))
        } else {
          tags$p("No CRAN packages found to update.")
        },
        warning_ui,
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          if (length(cran_pkgs) > 0) {
            actionButton(ns("confirm_restock"), "Restock", class = "btn btn-primary",
                         onclick = "if(window.courierStartTimer) window.courierStartTimer();")
          } else {
            tags$span(class = "text-muted small", "Nothing to update.")
          }
        )
      ))
    }

    observeEvent(input$restock_a, { do_restock(install_a_path, "source") })
    observeEvent(input$restock_b, { do_restock(install_b_path, "target") })

    observeEvent(input$confirm_restock, {
      plan <- restock_pending()
      removeModal()
      if (is.null(plan) || length(plan$cran_pkgs) == 0) { stop_busy(); return() }

      lib_res <- processx::run(
        plan$path, c("--vanilla", "-e", "cat(.libPaths()[1])"),
        error_on_status = FALSE
      )
      tgt_lib <- trimws(lib_res$stdout)
      if (lib_res$status != 0 || !nzchar(tgt_lib)) {
        stop_busy()
        showNotification("Could not determine library path.", type = "error")
        return()
      }

      specs <- plan$cran_pkgs
      ok <- tryCatch({
        callr::r(
          func = function(specs, lib) {
            pak::pkg_install(specs, lib = lib, ask = FALSE, upgrade = TRUE)
          },
          args = list(specs = specs, lib = tgt_lib),
          show = FALSE
        )
        TRUE
      }, error = function(e) {
        showNotification(paste("Restock failed:", e$message),
                         type = "error", duration = NULL)
        if (is.function(push_error))
          push_error(e$message, context = "Restocking packages")
        FALSE
      })

      restock_pending(NULL)
      stop_busy()
      if (ok) {
        invalidate_manifest(plan$path)  # restock changed this library
        showNotification(
          sprintf("Restocked %d package(s) in the %s installation.",
                  length(specs), plan$label),
          type = "message"
        )
      }
    })
  })
}
