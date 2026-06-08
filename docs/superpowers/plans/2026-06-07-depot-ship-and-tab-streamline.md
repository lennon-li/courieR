# courieR: Depot Ship Tab + Tab Streamline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Streamline the Advanced tab from 5 sub-tabs to 2, fold Restock and Receipt into Dispatch, and add a package-level selection + action UI as a new Depot › Ship sub-tab.

**Architecture:** Four new `reactiveVal`s in `server.R` — `comparison_rv`, `sync_direction_rv`, `transfer_mode_rv`, `actionable_count` — flow from `mod_sync` (Dispatch tab) into `mod_depot_ship` (Depot › Ship sub-tab). A new `mod_depot_ship.R` handles all Ship sub-tab logic. `mod_update.R` and `mod_receipt.R` have their logic folded into `mod_sync.R` and are then deleted. `global.R` auto-sources every `.R` file in `modules/`, so adding/removing files takes effect automatically.

**Tech Stack:** R, Shiny, bslib (≥ 0.7), DT, shinyjs, processx, callr, pak, testthat

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `inst/app/server.R` | Modify | Add 4 shared reactiveVals; update module call signatures; add Advanced badge observer |
| `inst/app/ui.R` | Modify | Remove Route/Restock/Receipt nav panels; add Depot sub-tabs; add Advanced badge uiOutput |
| `inst/app/modules/mod_sync.R` | Modify | Add Restock sidebar buttons+logic; post-ship receipt panel; comparison_rv sharing; Depot hint |
| `inst/app/modules/mod_origin.R` | Modify | Restructure into Browse/Ship sub-tab container; pass args to mod_depot_ship |
| `inst/app/modules/mod_depot_ship.R` | **Create** | Ship sub-tab: context bar, chip filters, search, DT table, bulk actions, plan summary, Ship button |
| `inst/app/modules/mod_update.R` | Delete | Logic folded into mod_sync.R |
| `inst/app/modules/mod_receipt.R` | Delete | Logic folded into mod_sync.R |
| `inst/app/www/styles.css` | Modify | Styles for receipt panel, restock sidebar, depot-ship-hint, Ship sub-tab zones, action badges |
| `tests/testthat/test-depot-ship-batches.R` | **Create** | Unit tests for `.build_depot_ship_batches()` helper |

---

## Task 1: Add shared reactiveVals to server.R

**Files:**
- Modify: `inst/app/server.R`

- [ ] **Step 1: Add the four new reactiveVals and update module calls**

Replace the entire contents of `inst/app/server.R` with:

```r
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
```

> Note: `mod_receipt_server` and `mod_update_server` calls remain until Tasks 3–4 fold them in. They are removed in Task 13.

- [ ] **Step 2: Verify the app still launches**

```r
# In R console from the repo root:
courieR::open_hub()
```

Expected: App opens, Dispatch tab works, no console errors about missing arguments.

- [ ] **Step 3: Commit**

```bash
git add inst/app/server.R
git commit -m "feat: add shared reactiveVals for comparison, direction, mode, badge"
```

---

## Task 2: Restructure ui.R

**Files:**
- Modify: `inst/app/ui.R`

- [ ] **Step 1: Replace ui.R**

```r
ui <- bslib::page_navbar(
  title = div(
    class = "app-brand",
    div(
      class = "app-brand-mark",
      tags$div(
        class = "app-logo-wrap",
        tags$img(src = "logo.png", height = "84px",
                 style = "vertical-align: middle; background: transparent;")
      ),
      tags$div(class = "app-version",
               sprintf("v%s", utils::packageVersion("courieR")))
    )
  ),
  window_title = "courieR",
  theme = bslib::bs_theme(version = 5, preset = "shiny"),
  header = tagList(
    shinyjs::useShinyjs(),
    tags$head(
      tags$link(rel = "stylesheet", href = "styles.css"),
      tags$script(HTML(
        "$(document).on('shiny:busy', function(){ $('.app-brand-mark').addClass('app-busy'); });
         $(document).on('shiny:idle', function(){ $('.app-brand-mark').removeClass('app-busy'); });
         function courierChipClick(el, status, inputId) {
           el.classList.toggle('chip-active');
           var bar = el.closest('.sync-summary-bar');
           var activeChips = bar ? Array.from(bar.querySelectorAll('.chip-active')) : [];
           if (activeChips.length === 0) {
             Array.from(bar.querySelectorAll('.sync-summary-chip'))
               .forEach(function(c) { c.classList.add('chip-active'); });
             Shiny.setInputValue(inputId, null, {priority: 'event'});
           } else {
             Shiny.setInputValue(inputId, activeChips.map(function(c) {
               return c.dataset.status;
             }), {priority: 'event'});
           }
         }
         function navigateToDepotShip() {
           var advTab = document.querySelector('[data-value=\"Advanced\"]');
           if (advTab) advTab.click();
           setTimeout(function() {
             var shipTab = document.querySelector('[data-value=\"Ship\"]');
             if (shipTab) shipTab.click();
           }, 150);
         }"
      ))
    ),
    mod_error_reporter_ui("reporter")
  ),

  bslib::nav_panel(
    "Dispatch",
    mod_sync_ui("sync")
  ),

  bslib::nav_panel(
    title = tagList(
      "Advanced",
      uiOutput("advanced_badge", inline = TRUE)
    ),
    value = "Advanced",
    bslib::navset_card_tab(
      bslib::nav_panel(
        "Depot",
        div(class = "advanced-pane advanced-depot", mod_origin_ui("env"))
      ),
      bslib::nav_panel(
        "Manifest",
        div(class = "advanced-pane advanced-manifest", mod_manifest_ui("report"))
      )
    )
  )
)
```

- [ ] **Step 2: Launch app and verify structure**

```r
courieR::open_hub()
```

Expected: Dispatch tab unchanged. Advanced tab shows two sub-tabs: Depot and Manifest. Depot shows existing Browse content (not yet sub-tabbed — that comes in Task 6). No Route, Restock, or Receipt tabs visible.

- [ ] **Step 3: Commit**

```bash
git add inst/app/ui.R
git commit -m "feat: restructure ui.R — remove Route/Restock/Receipt tabs, add Depot/Manifest"
```

---

## Task 3: Fold Restock into mod_sync.R sidebar

**Files:**
- Modify: `inst/app/modules/mod_sync.R`

The existing Restock logic lives in `mod_update.R`: `do_click()` scans the manifest, splits CRAN vs non-CRAN, shows a modal, and on confirm calls `callr::r()` with `pak::pkg_install()`. Replicate this inside mod_sync.

- [ ] **Step 1: Add Restock UI to mod_sync_ui**

In `mod_sync_ui`, after the existing `actionButton(ns("sync_btn"), "Ship", ...)` line and its closing `),` (end of sidebar content), add before the final `)` of `sidebar = bslib::sidebar(...)`:

```r
      hr(),
      tags$div(class = "sync-select-label", "Maintenance"),
      div(
        class = "sync-restock-wrap",
        actionButton(ns("restock_a"), "Restock A from CRAN",
                     class = "btn sync-restock-btn"),
        actionButton(ns("restock_b"), "Restock B from CRAN",
                     class = "btn sync-restock-btn")
      ),
```

- [ ] **Step 2: Add Restock server logic to mod_sync_server**

Add the following inside `mod_sync_server`, before the final `})` closing the `moduleServer` call. Add new args `install_a_path = NULL, install_b_path = NULL` to the `mod_sync_server` signature if not already present (check: existing signature is `mod_sync_server <- function(id, install_a_path = NULL, install_b_path = NULL, routes_cache = NULL, push_error = NULL)`). Add the new output args too — see Task 1. Full updated signature:

```r
mod_sync_server <- function(id,
                            install_a_path     = NULL,
                            install_b_path     = NULL,
                            routes_cache       = NULL,
                            push_error         = NULL,
                            comparison_out     = NULL,
                            actionable_out     = NULL,
                            sync_direction_out = NULL,
                            transfer_mode_out  = NULL) {
```

Then add the Restock logic at the bottom of the module body (before the final `})`):

```r
    # ── Restock ───────────────────────────────────────────────────────
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
        title = paste0("Restock Installation ", label, " from CRAN"),
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
            actionButton(ns("confirm_restock"), "Restock", class = "btn btn-primary")
          } else {
            tags$span(class = "text-muted small", "Nothing to update.")
          }
        )
      ))
    }

    observeEvent(input$restock_a, { do_restock(install_a_path, "A") })
    observeEvent(input$restock_b, { do_restock(install_b_path, "B") })

    observeEvent(input$confirm_restock, {
      plan <- restock_pending()
      removeModal()
      if (is.null(plan) || length(plan$cran_pkgs) == 0) return()

      lib_res <- processx::run(
        plan$path, c("--vanilla", "-e", "cat(.libPaths()[1])"),
        error_on_status = FALSE
      )
      tgt_lib <- trimws(lib_res$stdout)
      if (lib_res$status != 0 || !nzchar(tgt_lib)) {
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
      if (ok) {
        showNotification(
          sprintf("Restocked %d package(s) in installation %s.",
                  length(specs), plan$label),
          type = "message"
        )
      }
    })
```

- [ ] **Step 3: Also add the output reactiveVal writers for comparison, direction, mode, and actionable count**

Inside `mod_sync_server`, find the existing `observeEvent(input$compare, {...})` block. At the end of the successful compare path (just before `re_enable_compare()`), add:

```r
        # Share comparison state with other tabs
        if (is.function(comparison_out)) comparison_out(comparison_data())
        diff_n <- sum(comparison_data()[["status"]] != "same")
        if (is.function(actionable_out)) actionable_out(diff_n)
```

And add observers that write direction and mode to their output reactiveVals (add near the existing `observe({va <- route_version...})` block):

```r
    observe({
      if (is.function(sync_direction_out)) sync_direction_out(input$sync_direction %||% "A_to_B")
    })
    observe({
      if (is.function(transfer_mode_out)) transfer_mode_out(input$transfer_mode %||% "online")
    })
```

Also clear the comparison and count on new Compare start. In `observeEvent(input$compare, {...})`, at the very top before any other logic:

```r
      if (is.function(comparison_out))  comparison_out(NULL)
      if (is.function(actionable_out))  actionable_out(0L)
```

- [ ] **Step 4: Launch and verify Restock buttons appear in sidebar**

```r
courieR::open_hub()
```

Expected: Below the Ship button in Dispatch sidebar, a "Maintenance" label and two "Restock A/B from CRAN" buttons appear. Clicking one with an installation selected opens a modal.

- [ ] **Step 5: Commit**

```bash
git add inst/app/modules/mod_sync.R
git commit -m "feat: fold Restock into Dispatch sidebar; share comparison_rv/direction/mode"
```

---

## Task 4: Fold Delivery Receipt into mod_sync.R

**Files:**
- Modify: `inst/app/modules/mod_sync.R`

After a Ship completes, show an inline receipt card below the comparison table. Hide it on the next Compare.

- [ ] **Step 1: Add receipt reactive state**

At the top of `mod_sync_server` (with the other `reactiveVal` declarations), add:

```r
    last_ship_result <- reactiveVal(NULL)
```

- [ ] **Step 2: Populate last_ship_result after Ship completes**

The current Ship flow calls `courieR::ship()` per batch but only accumulates a count summary. We need to also capture per-package results and plans for the receipt panel.

At the very top of the `observeEvent(input$confirm_sync, {...})` body, add:

```r
      ship_start_time <- Sys.time()
```

Then modify the inner ship loop to accumulate results. Replace the section inside `observeEvent(input$confirm_sync, {...})` that builds `result` with:

```r
      accumulated_results <- list()
      accumulated_plans   <- list()

      for (i in seq_along(batches)) {
        batch <- batches[[i]]
        # ... (existing package_preview / detail / set_sync_progress / add_sync_log lines unchanged) ...

        ship_result <- courieR::ship(
          source_path  = batch$source_path,
          target_path  = batch$target_path,
          packages     = batch$packages,
          upgrade      = TRUE,
          log_callback = add_sync_log,
          mode         = input$transfer_mode
        )

        add_plan_log(ship_result)
        add_result_log(ship_result)

        if (!is.null(ship_result$results) && nrow(ship_result$results) > 0)
          accumulated_results[[i]] <- ship_result$results
        if (!is.null(ship_result$plan) && nrow(ship_result$plan) > 0)
          accumulated_plans[[i]] <- ship_result$plan

        # ... (existing failure counting / notification lines unchanged) ...
      }

      # Store for receipt panel
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
```

Also add `ship_start_time <- Sys.time()` at the very start of the `observeEvent(input$confirm_sync, {...})` body.

And clear it at the start of `observeEvent(input$compare, {...})`:

```r
      last_ship_result(NULL)
```

- [ ] **Step 3: Add receipt panel UI output to mod_sync_ui**

In `mod_sync_ui`, after the `bslib::card(class = "sync-card", ...)` block (the main comparison card), add:

```r
    uiOutput(ns("delivery_receipt_panel")),
```

- [ ] **Step 4: Render receipt panel in mod_sync_server**

Add to mod_sync_server:

```r
    output$delivery_receipt_panel <- renderUI({
      res <- last_ship_result()
      if (is.null(res)) return(NULL)

      results <- res$results
      plan    <- res$plan
      elapsed <- res$elapsed_sec %||% 0

      n_total <- if (!is.null(results)) nrow(results) else 0L
      n_ok    <- if (!is.null(results)) sum(results$status == "success") else 0L
      n_err   <- n_total - n_ok
      theme   <- if (n_err == 0) "success" else if (n_ok == 0) "danger" else "warning"

      bslib::card(
        class = "sync-receipt-card",
        bslib::card_header(
          class = "sync-receipt-header",
          tags$span("Delivery Receipt"),
          tags$span(class = "sync-receipt-elapsed",
                    sprintf("%.1fs", elapsed))
        ),
        bslib::card_body(
          bslib::value_box(
            "Result",
            sprintf("%d / %d packages delivered", n_ok, n_total),
            theme = theme
          ),
          if (!is.null(results) && nrow(results) > 0) {
            bslib::navset_card_tab(
              bslib::nav_panel("Results",
                DT::renderDataTable(
                  DT::datatable(results,
                    options = list(pageLength = 15, dom = "tip"),
                    rownames = FALSE
                  )
                )
              ),
              bslib::nav_panel("Plan",
                if (!is.null(plan) && nrow(plan) > 0) {
                  cols <- intersect(c("package", "version.x", "action", "source", "pak_spec"),
                                    names(plan))
                  DT::renderDataTable(
                    DT::datatable(plan[, cols, with = FALSE],
                      options = list(pageLength = 15, dom = "tip"),
                      rownames = FALSE
                    )
                  )
                } else {
                  tags$p("No plan details available.")
                }
              )
            )
          }
        )
      )
    })
```

- [ ] **Step 5: Verify receipt panel**

```r
courieR::open_hub()
```

Expected: After a successful Ship in Dispatch, a "Delivery Receipt" card appears below the comparison table showing N/N delivered and Results/Plan sub-tabs. The card disappears when Compare is run again.

- [ ] **Step 6: Commit**

```bash
git add inst/app/modules/mod_sync.R
git commit -m "feat: fold Delivery Receipt into Dispatch post-ship panel"
```

---

## Task 5: Add Depot hint to mod_sync.R

**Files:**
- Modify: `inst/app/modules/mod_sync.R`

- [ ] **Step 1: Add hint to comparison_summary output**

Find `output$comparison_summary <- renderUI({...})` in mod_sync_server. At the end of the `div(class = "sync-summary-bar", ...)` block (after the last `make_chip(...)` call), add the hint as a sibling element:

```r
      hint_ui <- if (any(comp[["status"]] != "same")) {
        tags$p(
          class = "depot-ship-hint",
          "Cherry-pick packages",
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
          make_chip("same",           "identical",   "chip-same"),
          make_chip("newer-in-A",     a_lbl,         "chip-diff-a"),
          make_chip("newer-in-B",     b_lbl,         "chip-diff-b"),
          make_chip("missing-from-B", nb_lbl,        "chip-diff-a"),
          make_chip("missing-from-A", na_lbl,        "chip-diff-b")
        ),
        hint_ui
      )
```

> `navigateToDepotShip()` is the JS function added in ui.R (Task 2) that clicks the Advanced tab then the Ship sub-tab.

- [ ] **Step 2: Verify hint appears**

```r
courieR::open_hub()
```

Expected: After Compare shows diffs, a "Cherry-pick packages → Advanced › Depot › Ship" link appears below the chip bar. When all packages are identical, the hint is absent.

- [ ] **Step 3: Commit**

```bash
git add inst/app/modules/mod_sync.R
git commit -m "feat: add Depot hint link to Dispatch comparison summary"
```

---

## Task 6: Write unit tests for `.build_depot_ship_batches()`

**Files:**
- Create: `tests/testthat/test-depot-ship-batches.R`
- Create: helper function in `inst/app/modules/mod_depot_ship.R` (stub — just the helper)

This helper is pure R, no Shiny — test it first.

- [ ] **Step 1: Create mod_depot_ship.R with just the helper function**

Create `inst/app/modules/mod_depot_ship.R`:

```r
# Helper: build ship batches from per-package action assignments.
# Returns a list of batch specs: list(pkgs, src, tgt, mode).
#
# actions       named character vector: package -> "skip" | "ship" | "online"
# comp          data.frame/data.table with columns: package, status
# direction     one of "A_to_B", "B_to_A", "full"
# from_path     Rscript path for installation A
# to_path       Rscript path for installation B
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
```

- [ ] **Step 2: Write the failing tests**

Create `tests/testthat/test-depot-ship-batches.R`:

```r
# Source the helper directly since it's a Shiny app file, not exported.
source(
  system.file("app/modules/mod_depot_ship.R", package = "courieR"),
  local = TRUE
)

comp <- data.frame(
  package = c("ggplot2", "dplyr", "tidyr", "patchwork"),
  status  = c("missing-from-B", "newer-in-A", "missing-from-A", "same"),
  stringsAsFactors = FALSE
)

test_that(".build_depot_ship_batches returns empty list when all skip", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "skip", patchwork = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "A_to_B", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 0L)
})

test_that(".build_depot_ship_batches routes A_to_B correctly", {
  actions <- c(ggplot2 = "online", dplyr = "ship", tidyr = "skip", patchwork = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "A_to_B", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 2L)

  online_batch <- result[[which(sapply(result, `[[`, "mode") == "online")]]
  expect_equal(online_batch$pkgs,  "ggplot2")
  expect_equal(online_batch$src,   "/a/Rscript")
  expect_equal(online_batch$tgt,   "/b/Rscript")

  copy_batch <- result[[which(sapply(result, `[[`, "mode") == "offline")]]
  expect_equal(copy_batch$pkgs, "dplyr")
})

test_that(".build_depot_ship_batches routes B_to_A correctly", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "online", patchwork = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "B_to_A", "/a/Rscript", "/b/Rscript")
  expect_equal(length(result), 1L)
  expect_equal(result[[1]]$pkgs, "tidyr")
  expect_equal(result[[1]]$src,  "/b/Rscript")
  expect_equal(result[[1]]$tgt,  "/a/Rscript")
  expect_equal(result[[1]]$mode, "online")
})

test_that(".build_depot_ship_batches routes full (two-way) correctly", {
  actions <- c(ggplot2 = "online", dplyr = "skip", tidyr = "ship", patchwork = "skip")
  result  <- .build_depot_ship_batches(actions, comp, "full", "/a/Rscript", "/b/Rscript")
  modes <- sapply(result, `[[`, "mode")
  srcs  <- sapply(result, `[[`, "src")

  # ggplot2 is missing-from-B → goes A_to_B online
  ab_online <- result[[which(modes == "online" & srcs == "/a/Rscript")]]
  expect_equal(ab_online$pkgs, "ggplot2")

  # tidyr is missing-from-A → goes B_to_A offline
  ba_copy <- result[[which(modes == "offline" & srcs == "/b/Rscript")]]
  expect_equal(ba_copy$pkgs, "tidyr")
})

test_that(".build_depot_ship_batches ignores 'same' packages in full direction", {
  actions <- c(ggplot2 = "skip", dplyr = "skip", tidyr = "skip", patchwork = "online")
  result  <- .build_depot_ship_batches(actions, comp, "full", "/a/Rscript", "/b/Rscript")
  # patchwork is "same" — has no valid direction in full mode, status_map returns NA
  # NA %in% c("missing-from-B", ...) is FALSE, so patchwork lands in neither batch
  expect_equal(length(result), 0L)
})
```

- [ ] **Step 3: Run tests and confirm they fail**

```bash
cd /home/yeli/repos/courieR
Rscript -e "devtools::test(filter = 'depot-ship-batches')"
```

Expected: Tests fail because `mod_depot_ship.R` exists but `.build_depot_ship_batches` may need the `source()` path fixed. Adjust the `system.file()` path in the test if needed — the file lives at `inst/app/modules/mod_depot_ship.R`.

Actually the `source()` path in the test should be:

```r
source(
  file.path(system.file("app", package = "courieR"), "modules", "mod_depot_ship.R"),
  local = TRUE
)
```

Or use a relative path if running from the package root:

```r
source("inst/app/modules/mod_depot_ship.R", local = TRUE)
```

Use whichever works in the test environment. For `devtools::test()` the working directory is the package root, so the relative path works.

- [ ] **Step 4: Verify tests pass with the helper already written**

```bash
Rscript -e "devtools::test(filter = 'depot-ship-batches')"
```

Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add inst/app/modules/mod_depot_ship.R tests/testthat/test-depot-ship-batches.R
git commit -m "test: add unit tests for .build_depot_ship_batches helper"
```

---

## Task 7: Restructure mod_origin.R into Browse/Ship container

**Files:**
- Modify: `inst/app/modules/mod_origin.R`

- [ ] **Step 1: Update mod_origin_ui to use sub-tabs**

Replace `mod_origin_ui` entirely:

```r
mod_origin_ui <- function(id) {
  ns <- NS(id)
  bslib::navset_card_tab(
    id = ns("depot_tabs"),
    bslib::nav_panel(
      "Browse",
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
    ),
    bslib::nav_panel(
      "Ship",
      mod_depot_ship_ui(ns("depot_ship"))
    )
  )
}
```

- [ ] **Step 2: Update mod_origin_server signature and add sub-module call**

Replace the `mod_origin_server` function signature:

```r
mod_origin_server <- function(id,
                              from_r_path       = NULL,
                              routes_cache      = NULL,
                              push_error        = NULL,
                              comparison_rv     = NULL,
                              to_r_path         = NULL,
                              sync_direction_rv  = NULL,
                              transfer_mode_rv   = NULL) {
```

Inside the server, add at the bottom (before the final `})`):

```r
    # ── Browse → Ship bridge ───────────────────────────────────────────
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
        ns("view_in_ship"), sprintf("View '%s' in Ship", pkg_name),
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
      bslib::nav_select(ns("depot_tabs"), "Ship", session = session)
    })

    # ── Ship sub-module ────────────────────────────────────────────────
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
```

- [ ] **Step 3: Launch and verify Browse sub-tab**

```r
courieR::open_hub()
```

Expected: Advanced › Depot shows "Browse" and "Ship" sub-tabs. Browse tab shows the existing Depot content (Detected Depots + Depot Manifest). Ship tab is empty for now (will be built in Tasks 8–10). App does not crash.

- [ ] **Step 4: Commit**

```bash
git add inst/app/modules/mod_origin.R
git commit -m "feat: restructure mod_origin into Browse/Ship sub-tabs"
```

---

## Task 8: Depot Ship sub-tab — UI

**Files:**
- Modify: `inst/app/modules/mod_depot_ship.R`

- [ ] **Step 1: Add mod_depot_ship_ui to mod_depot_ship.R**

Append to `inst/app/modules/mod_depot_ship.R`:

```r
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
```

- [ ] **Step 2: Launch and verify Ship sub-tab renders the UI skeleton**

```r
courieR::open_hub()
```

Expected: Advanced › Depot › Ship shows the Zone 1/2/3 elements (context bar placeholder, toolbar, empty DT, plan summary area, Ship button). The button is present but will be wired in Task 10.

- [ ] **Step 3: Commit**

```bash
git add inst/app/modules/mod_depot_ship.R
git commit -m "feat: add Ship sub-tab UI skeleton"
```

---

## Task 9: Depot Ship sub-tab — Server: state, context bar, table, bulk actions

**Files:**
- Modify: `inst/app/modules/mod_depot_ship.R`

- [ ] **Step 1: Add mod_depot_ship_server to mod_depot_ship.R**

Append to `inst/app/modules/mod_depot_ship.R`:

```r
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

    # ── Reactive state ────────────────────────────────────────────────
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

    # ── Initialise defaults when comparison changes ───────────────────
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

    # ── Pre-populate search from Browse "View in Ship" ─────────────────
    if (!is.null(incoming_search)) {
      observeEvent(incoming_search(), {
        val <- incoming_search()
        if (!is.null(val) && nzchar(val)) {
          updateTextInput(session, "ship_search", value = val)
        }
      }, ignoreNULL = TRUE)
    }

    # ── Context bar ───────────────────────────────────────────────────
    output$context_bar <- renderUI({
      comp <- get_comp()
      if (is.null(comp)) {
        return(div(
          class = "depot-ship-context-bar depot-ship-context-empty",
          tags$span("Run Compare in Dispatch first to load packages.")
        ))
      }
      dir <- get_direction()
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

    # ── Chip filters ──────────────────────────────────────────────────
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
        make_chip("same",           "identical",     "chip-same"),
        make_chip("newer-in-A",     "newer in A",    "chip-diff-a"),
        make_chip("newer-in-B",     "newer in B",    "chip-diff-b"),
        make_chip("missing-from-B", "not in B",      "chip-diff-a"),
        make_chip("missing-from-A", "not in A",      "chip-diff-b")
      )
    })

    observeEvent(input$depot_chip_filter, {
      vals <- input$depot_chip_filter
      ship_filter_status(if (is.null(vals) || length(vals) == 0L) NULL else vals)
    }, ignoreNULL = FALSE, ignoreInit = TRUE)

    # ── Filtered package list (chip + search) ─────────────────────────
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

    # ── Bulk action apply ─────────────────────────────────────────────
    observeEvent(input$bulk_apply, {
      selected_idx <- input$ship_table_rows_selected
      if (is.null(selected_idx) || length(selected_idx) == 0L) {
        showNotification("Select rows in the table first.", type = "warning")
        return()
      }
      visible  <- visible_comp()
      if (is.null(visible)) return()
      target_pkgs <- visible[["package"]][selected_idx]
      action      <- input$bulk_action
      current     <- isolate(pkg_actions())
      current[target_pkgs] <- action
      pkg_actions(current)
    })

    # ── Table ─────────────────────────────────────────────────────────
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
            c("skip", "ship",  "online"),
            c("400",  "600",   "700")
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

    # ── Plan summary ──────────────────────────────────────────────────
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
  })
}
```

- [ ] **Step 2: Run existing tests to verify nothing is broken**

```bash
Rscript -e "devtools::test()"
```

Expected: All existing tests pass. The new depot-ship-batches tests pass.

- [ ] **Step 3: Launch and verify table + bulk actions**

```r
courieR::open_hub()
```

Expected:
1. Run Compare in Dispatch for two installations with diffs.
2. Navigate to Advanced › Depot › Ship.
3. Context bar shows A, B, direction, mode.
4. Chip filters show status counts. Table shows packages with Action badges colored by assignment.
5. Check some rows → bulk "Skip" → Apply → those rows update to grey "skip" badge.
6. Search for a package name → table filters down.
7. Plan summary shows updated counts. Ship button enables/disables based on non-skip count.

- [ ] **Step 4: Commit**

```bash
git add inst/app/modules/mod_depot_ship.R
git commit -m "feat: Ship sub-tab server — context bar, chip filters, table, bulk actions"
```

---

## Task 10: Depot Ship sub-tab — Ship button execution

**Files:**
- Modify: `inst/app/modules/mod_depot_ship.R`

- [ ] **Step 1: Add Ship button observer to mod_depot_ship_server**

Inside `mod_depot_ship_server`, after the plan summary output, add:

```r
    # ── Ship button ───────────────────────────────────────────────────
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
        # Reset all shipped packages to "skip" so the user can see what's left
        current <- isolate(pkg_actions())
        shipped <- names(actions)[actions != "skip"]
        current[shipped] <- "skip"
        pkg_actions(current)
      }
    })

    # ── Inline receipt after depot ship ───────────────────────────────
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
```

- [ ] **Step 2: Run tests**

```bash
Rscript -e "devtools::test()"
```

Expected: All tests pass.

- [ ] **Step 3: Launch and verify end-to-end Ship flow**

```r
courieR::open_hub()
```

Expected:
1. Compare in Dispatch with two real installations.
2. Navigate to Advanced › Depot › Ship.
3. Select some packages, set actions, click Ship.
4. Ship executes (progress in background), then inline receipt card appears below the Ship button showing delivery result.
5. Shipped packages reset to "skip" in the Action column.

- [ ] **Step 4: Commit**

```bash
git add inst/app/modules/mod_depot_ship.R
git commit -m "feat: Ship sub-tab — execute ship batches, show inline receipt"
```

---

## Task 11: Advanced tab badge

**Files:**
- Modify: `inst/app/www/styles.css`

The badge `output$advanced_badge` is already wired in server.R (Task 1) and rendered inline in the nav title in ui.R (Task 2). It just needs CSS.

- [ ] **Step 1: Add badge styles to styles.css**

Add to the end of `inst/app/www/styles.css`:

```css
/* ── Advanced tab badge ── */
.advanced-tab-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  margin-left: 6px;
  border-radius: 9px;
  background: #5f4ab4;
  color: #ffffff;
  font-size: 0.68rem;
  font-weight: 800;
  line-height: 1;
  vertical-align: middle;
}
```

- [ ] **Step 2: Add remaining new styles**

Add to the end of `inst/app/www/styles.css`:

```css
/* ── Restock sidebar ── */
.sync-restock-wrap {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.sync-restock-btn {
  width: 100%;
  background: #f5f8fb;
  border: 1px solid #d0dde8;
  color: #355066;
  font-size: 0.8rem;
  font-weight: 600;
  border-radius: 8px;
  padding: 0.4rem 0.7rem;
  text-align: left;
  transition: background 0.12s, border-color 0.12s;
}

.sync-restock-btn:hover {
  background: #e8f0f7;
  border-color: #aac4d8;
}

/* ── Depot ship hint (Dispatch tab) ── */
.sync-summary-wrap {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}

.depot-ship-hint {
  font-size: 0.78rem;
  color: #7a95a8;
  margin: 0;
}

.depot-ship-hint a {
  color: #1d6fa5;
  font-weight: 600;
  text-decoration: none;
}

.depot-ship-hint a:hover {
  text-decoration: underline;
}

/* ── Delivery receipt panel ── */
.sync-receipt-card {
  margin-top: 1rem;
}

.sync-receipt-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.sync-receipt-elapsed {
  font-size: 0.78rem;
  color: #7a95a8;
  font-weight: 400;
}

/* ── Depot Ship pane ── */
.depot-ship-pane {
  padding: 0.75rem 0.25rem;
}

.depot-ship-context-bar {
  display: flex;
  align-items: center;
  gap: 0.8rem;
  padding: 0.5rem 0.75rem;
  background: #f5f8fb;
  border: 1px solid #dde8f0;
  border-radius: 10px;
  margin-bottom: 0.75rem;
  font-size: 0.82rem;
}

.depot-ship-context-empty {
  color: #9aabba;
  font-style: italic;
}

.depot-ship-context-sep {
  font-weight: 800;
  color: #5f4ab4;
}

.depot-ship-context-mode {
  margin-left: auto;
  color: #6d879b;
}

.depot-ship-toolbar {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  margin-bottom: 0.5rem;
  flex-wrap: wrap;
}

.depot-ship-bulk {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  margin-left: auto;
}

.depot-bulk-apply-btn {
  background: #f0f2f5;
  border: 1px solid #ccd8e2;
  color: #355066;
  font-weight: 600;
  border-radius: 7px;
}

.depot-bulk-apply-btn:hover {
  background: #e0eaf3;
}

.depot-ship-summary {
  display: flex;
  gap: 0.8rem;
  flex-wrap: wrap;
  margin: 0.75rem 0 0.5rem;
  font-size: 0.82rem;
  font-weight: 600;
}

.depot-summary-online { color: #1d6fa5; }
.depot-summary-ship   { color: #c27a3a; }
.depot-summary-skip   { color: #9aabba; }

.depot-ship-footer {
  margin-top: 0.5rem;
}

.depot-ship-execute-btn {
  min-width: 120px;
}

/* ── Browse → Ship button ── */
.browse-to-ship-btn {
  margin-top: 0.5rem;
  background: #eef6ff;
  border: 1px solid #b3d4f0;
  color: #1d6fa5;
  font-weight: 600;
  border-radius: 7px;
}
```

- [ ] **Step 3: Launch and verify badge**

```r
courieR::open_hub()
```

Expected: After a Compare with diffs, the Advanced nav tab shows a purple badge with the count of non-identical packages. Badge disappears after all packages are shipped or a new Compare with all-same results runs.

- [ ] **Step 4: Commit**

```bash
git add inst/app/www/styles.css
git commit -m "feat: add styles for badge, restock sidebar, depot hint, Ship sub-tab"
```

---

## Task 12: Remove mod_update.R and mod_receipt.R

**Files:**
- Delete: `inst/app/modules/mod_update.R`
- Delete: `inst/app/modules/mod_receipt.R`
- Modify: `inst/app/server.R` (remove the now-dead module calls)

`global.R` auto-sources all `.R` files in `modules/`. Deleting these files removes them from the app automatically.

- [ ] **Step 1: Remove dead module calls from server.R**

In `inst/app/server.R`, delete these two lines:

```r
  mod_receipt_server("results", migration_log)
  mod_update_server("update", from_r_path, to_r_path, push_error = push_error)
```

Also remove `migration_log <- reactiveVal(NULL)` since it's no longer used anywhere (the receipt now lives inside mod_sync). And remove `mod_manifest_server`'s `migration_log` argument if it accepts one — check `mod_manifest.R`: it takes `from_r_path, to_r_path, migration_log`. The Manifest tab generates a download report from `migration_log`. Since we are removing the global `migration_log`, the Manifest tab will always render with `NULL` migration_log — which is acceptable (it degrades gracefully). Update the call:

```r
  mod_manifest_server("report", from_r_path, to_r_path, reactiveVal(NULL))
```

- [ ] **Step 2: Delete the files**

```bash
rm inst/app/modules/mod_update.R
rm inst/app/modules/mod_receipt.R
```

- [ ] **Step 3: Run tests and launch app**

```bash
Rscript -e "devtools::test()"
courieR::open_hub()
```

Expected: All tests pass. App launches without errors. No references to `mod_update_server` or `mod_receipt_server` remain.

- [ ] **Step 4: Commit**

```bash
git add inst/app/server.R
git rm inst/app/modules/mod_update.R inst/app/modules/mod_receipt.R
git commit -m "chore: remove mod_update.R and mod_receipt.R — logic folded into mod_sync"
```

---

## Task 13: Final verification and push

- [ ] **Step 1: Run full test suite**

```bash
Rscript -e "devtools::test()"
```

Expected: All tests pass including `test-depot-ship-batches.R`.

- [ ] **Step 2: Manual end-to-end smoke test**

```r
courieR::open_hub()
```

Verify each item:
- [ ] Dispatch tab: Restock A/B buttons in sidebar, confirm modal works
- [ ] Dispatch tab: Post-ship receipt card appears after Ship, disappears on next Compare
- [ ] Dispatch tab: Depot hint link appears when diffs exist, hidden when all-same
- [ ] Dispatch tab: Hint link navigates to Advanced › Depot › Ship
- [ ] Advanced tab: Badge shows diff count after Compare, clears after ship
- [ ] Advanced › Depot › Browse: existing manifest table works
- [ ] Advanced › Depot › Browse: "View in Ship" button appears on row select, switches tab + pre-fills search
- [ ] Advanced › Depot › Ship: context bar shows A/B/direction/mode from Dispatch
- [ ] Advanced › Depot › Ship: context bar shows "Run Compare first" when no comparison
- [ ] Advanced › Depot › Ship: chip filters work
- [ ] Advanced › Depot › Ship: search box filters table
- [ ] Advanced › Depot › Ship: bulk action toolbar assigns actions to selected rows
- [ ] Advanced › Depot › Ship: plan summary counts update correctly
- [ ] Advanced › Depot › Ship: Ship button disabled when all-skip
- [ ] Advanced › Depot › Ship: Ship button executes and shows inline receipt
- [ ] Advanced › Manifest: download still works

- [ ] **Step 3: Push**

```bash
git push origin master
```
