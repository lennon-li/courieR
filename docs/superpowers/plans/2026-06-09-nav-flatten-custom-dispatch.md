# Nav Flatten + Custom Dispatch Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flatten the 3-level tab nesting to a single flat navbar, rename tabs (Dispatch → Bulk Dispatch, Ship → Custom Dispatch), and rebuild the Custom Dispatch panel to mirror the Bulk Dispatch two-pane (table + log) layout.

**Architecture:** This is a Shiny app. `ui.R` declares the navbar; module files under `inst/app/modules/` own each panel's UI + server. We split `mod_origin.R`'s combined Browse/Ship UI into two entry-point functions sharing one server, promote everything to top-level `nav_panel`s, and reshape `mod_depot_ship.R`'s UI to reuse the existing `.sync-workspace` CSS grid plus a log pane modeled on `mod_sync.R`'s `output$sync_log`.

**Tech Stack:** R, Shiny, bslib (page_navbar / nav_panel), DT (datatables), shinyjs.

**Testing note:** This codebase's `testthat` suite covers pure R functions (`find_routes`, `.build_depot_ship_batches`, etc.), not Shiny UI wiring. UI restructuring is verified two ways: (1) the full `testthat` suite must stay green as a regression guard — `R -q -e 'devtools::test()'`; (2) the app must be launched and visually checked. Per project memory, manual testing happens on Windows via `pak::pkg_install("local://...")`. Each task that changes only UI wiring uses "load the app, no error" as its check rather than a fabricated unit test.

---

## File Structure

| File | Change |
|------|--------|
| `inst/app/ui.R` | Rename Dispatch tab; replace Advanced wrapper with 4 flat nav_panels; rename JS helper |
| `inst/app/server.R` | Rename `advanced_badge` output → `custom_dispatch_badge` |
| `inst/app/modules/mod_origin.R` | Split `mod_origin_ui` → `mod_origin_browse_ui` + `mod_origin_ship_ui`; change Browse→Ship bridge to JS nav |
| `inst/app/modules/mod_depot_ship.R` | Remove context bar; rename chip labels & column headers; two-pane layout; log pane server + receipt relocation |

No CSS changes — `.sync-workspace`, `.sync-comparison-pane`, `.sync-log-pane` already exist in `inst/app/www/styles.css`.

---

## Task 1: Rename Dispatch tab and flatten the navbar

**Files:**
- Modify: `inst/app/ui.R:52-82` (nav_panel structure)
- Modify: `inst/app/ui.R:39-46` (JS helper)

- [ ] **Step 1: Rename the Dispatch nav_panel**

In `inst/app/ui.R`, change line 52-55 from:

```r
  bslib::nav_panel(
    "Dispatch",
    mod_sync_ui("sync")
  ),
```

to:

```r
  bslib::nav_panel(
    "Bulk Dispatch",
    mod_sync_ui("sync")
  ),
```

- [ ] **Step 2: Replace the Advanced wrapper with four flat nav_panels**

Replace the entire `bslib::nav_panel("Advanced", ...)` block (lines 57-81, the one containing `navset_card_tab`) with:

```r
  bslib::nav_panel(
    "Browse",
    div(class = "advanced-pane advanced-depot", mod_origin_browse_ui("env"))
  ),

  bslib::nav_panel(
    title = tagList(
      "Custom Dispatch",
      uiOutput("custom_dispatch_badge", inline = TRUE)
    ),
    value = "Custom Dispatch",
    div(class = "advanced-pane", mod_origin_ship_ui("env"))
  ),

  bslib::nav_panel(
    "Manifest",
    div(class = "advanced-pane advanced-manifest", mod_manifest_ui("report"))
  ),

  bslib::nav_panel(
    "Maintenance",
    div(class = "advanced-pane advanced-maintenance",
        bslib::card(
          bslib::card_header("Restock"),
          bslib::card_body(mod_sync_maintenance_ui("sync"))
        ))
  )
```

(Note: `mod_origin_browse_ui` and `mod_origin_ship_ui` are created in Task 3. The app will not load cleanly until Task 3 is done — that is expected; commit happens after Task 3. This task and Tasks 2-3 form one logical unit.)

- [ ] **Step 3: Rename the JS navigation helper**

In `inst/app/ui.R`, replace the `navigateToDepotShip` function (lines 39-45):

```r
         function navigateToDepotShip() {
           var advTab = document.querySelector('[data-value=\"Advanced\"]');
           if (advTab) advTab.click();
           setTimeout(function() {
             var shipTab = document.querySelector('[data-value=\"Ship\"]');
             if (shipTab) shipTab.click();
           }, 150);
         }
```

with:

```r
         function navigateToCustomDispatch() {
           var tab = document.querySelector('[data-value=\"Custom Dispatch\"]');
           if (tab) tab.click();
         }
```

- [ ] **Step 4: (Deferred verification)** App load is verified at the end of Task 3, once the module functions exist.

---

## Task 2: Rename the badge output in server.R

**Files:**
- Modify: `inst/app/server.R:16-20`

- [ ] **Step 1: Rename the output binding**

In `inst/app/server.R`, change lines 16-20 from:

```r
  output$advanced_badge <- renderUI({
    n <- actionable_count()
    if (n == 0L) return(NULL)
    tags$span(class = "advanced-tab-badge", n)
  })
```

to:

```r
  output$custom_dispatch_badge <- renderUI({
    n <- actionable_count()
    if (n == 0L) return(NULL)
    tags$span(class = "advanced-tab-badge", n)
  })
```

(Keep the `advanced-tab-badge` CSS class — it still exists in styles.css and styles the count chip.)

- [ ] **Step 2: Verify no other references to advanced_badge remain**

Run: `grep -rn "advanced_badge" /home/yeli/repos/courieR/inst/app/`
Expected: no matches.

---

## Task 3: Split mod_origin_ui into Browse and Ship entry points

**Files:**
- Modify: `inst/app/modules/mod_origin.R:1-31` (UI functions)
- Modify: `inst/app/modules/mod_origin.R:227-236` (Browse→Ship bridge observer)

- [ ] **Step 1: Replace `mod_origin_ui` with two entry-point functions**

In `inst/app/modules/mod_origin.R`, replace the entire `mod_origin_ui` function (lines 1-31):

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

with:

```r
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
```

- [ ] **Step 2: Update the Browse→Ship bridge to use JS navigation**

The bridge previously switched an inner tab via `bslib::nav_select(ns("depot_tabs"), "Ship", ...)`. There is no longer a `depot_tabs` navset. In `inst/app/modules/mod_origin.R`, replace the `observeEvent(input$view_in_ship, ...)` block (lines 227-236):

```r
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
```

with:

```r
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
```

- [ ] **Step 3: Verify the package still loads/installs cleanly**

Run: `cd /home/yeli/repos/courieR && R -q -e 'devtools::load_all(); cat("OK\n")'`
Expected: loads without parse/collation errors, prints `OK`.

- [ ] **Step 4: Run the full test suite (regression guard)**

Run: `cd /home/yeli/repos/courieR && R -q -e 'devtools::test()'`
Expected: all tests pass (same count as before this branch).

- [ ] **Step 5: Commit Tasks 1-3 together**

```bash
cd /home/yeli/repos/courieR
git add inst/app/ui.R inst/app/server.R inst/app/modules/mod_origin.R
git commit -m "feat(ui): flatten navbar — Bulk Dispatch + Browse/Custom Dispatch/Manifest/Maintenance"
```

---

## Task 4: Remove the context bar from Custom Dispatch

**Files:**
- Modify: `inst/app/modules/mod_depot_ship.R:62` (UI: remove uiOutput)
- Modify: `inst/app/modules/mod_depot_ship.R:170-200` (server: remove renderUI)

- [ ] **Step 1: Remove the context bar uiOutput from the UI**

In `mod_depot_ship_ui` (around line 61-62), delete these two lines (the comment and the output):

```r
    # Zone 1 — context bar
    uiOutput(ns("context_bar")),
```

- [ ] **Step 2: Remove the context_bar server render block**

In `mod_depot_ship_server`, delete the entire `output$context_bar <- renderUI({ ... })` block (lines 170-200), including the `# ── Context bar ──` comment header.

- [ ] **Step 3: Verify no remaining references to context_bar**

Run: `grep -n "context_bar" /home/yeli/repos/courieR/inst/app/modules/mod_depot_ship.R`
Expected: no matches.

(Do not commit yet — committed at the end of Task 7 with the rest of the depot-ship reshape.)

---

## Task 5: Rename chip labels and column headers (A/B → source/target)

**Files:**
- Modify: `inst/app/modules/mod_depot_ship.R:222-229` (chip labels)
- Modify: `inst/app/modules/mod_depot_ship.R:253-282` (column headers)

- [ ] **Step 1: Rename the chip filter labels**

In the `output$ship_chips` render block, change the `make_chip` calls (lines 224-228) from:

```r
        make_chip("same",           "identical",  "chip-same"),
        make_chip("newer-in-A",     "newer in A", "chip-diff-a"),
        make_chip("newer-in-B",     "newer in B", "chip-diff-b"),
        make_chip("missing-from-B", "not in B",   "chip-diff-a"),
        make_chip("missing-from-A", "not in A",   "chip-diff-b")
```

to:

```r
        make_chip("same",           "identical",        "chip-same"),
        make_chip("newer-in-A",     "newer in source",  "chip-diff-a"),
        make_chip("newer-in-B",     "newer in target",  "chip-diff-b"),
        make_chip("missing-from-B", "not in target",    "chip-diff-a"),
        make_chip("missing-from-A", "not in source",    "chip-diff-b")
```

(The status keys — first argument — stay unchanged; only the display label changes.)

- [ ] **Step 2: Rename the empty-table column headers**

In `empty_ship_dt` (lines 252-256), change:

```r
        data.frame(` ` = character(), Package = character(),
                   `Version A` = character(), `Version B` = character(),
                   Status = character(),
                   check.names = FALSE),
```

to:

```r
        data.frame(` ` = character(), Package = character(),
                   Source = character(), Target = character(),
                   Status = character(),
                   check.names = FALSE),
```

- [ ] **Step 3: Rename the populated-table column headers**

In `output$ship_table`, change the `display` data.frame (lines 274-284) from:

```r
      display <- data.frame(
        ` `        = cbs,
        Package    = pkgs,
        `Version A` = ifelse(is.na(visible[["version_in_a"]]),
                              "not installed", visible[["version_in_a"]]),
        `Version B` = ifelse(is.na(visible[["version_in_b"]]),
                              "not installed", visible[["version_in_b"]]),
        Status     = visible[["status"]],
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
```

to:

```r
      display <- data.frame(
        ` `     = cbs,
        Package = pkgs,
        Source  = ifelse(is.na(visible[["version_in_a"]]),
                         "not installed", visible[["version_in_a"]]),
        Target  = ifelse(is.na(visible[["version_in_b"]]),
                         "not installed", visible[["version_in_b"]]),
        Status  = visible[["status"]],
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
```

- [ ] **Step 4: Verify the package still loads**

Run: `cd /home/yeli/repos/courieR && R -q -e 'devtools::load_all(); cat("OK\n")'`
Expected: prints `OK`, no errors.

(No commit yet — bundled at end of Task 7.)

---

## Task 6: Add log-pane reactiveVals and the log render output

**Files:**
- Modify: `inst/app/modules/mod_depot_ship.R:120` (add reactiveVals near `shipping_in_progress`)
- Modify: `inst/app/modules/mod_depot_ship.R` (add `output$depot_log_ui` render block)

- [ ] **Step 1: Add log-state reactiveVals**

In `mod_depot_ship_server`, right after the existing `shipping_in_progress <- reactiveVal(FALSE)` line (line 120), add:

```r
    depot_log <- reactiveVal(character(0))
    depot_log_append <- function(...) {
      msg <- paste0(...)
      depot_log(c(depot_log(), msg))
    }
```

- [ ] **Step 2: Add the log render output**

Add this render block in `mod_depot_ship_server` (place it just before the closing `})` of the moduleServer, near the old receipt block). It mirrors `output$sync_log` in `mod_sync.R`:

```r
    # ── Log pane (mirrors Bulk Dispatch) ───────────────────────────────────
    format_depot_log <- function(entry) {
      if (startsWith(entry, "[ERR] ")) {
        clean <- htmltools::htmlEscape(substr(entry, 7L, nchar(entry)))
        sprintf('<span class="sync-log-error">%s</span>', clean)
      } else {
        htmltools::htmlEscape(entry)
      }
    }

    output$depot_log_ui <- renderUI({
      entries <- depot_log()
      active  <- shipping_in_progress()
      res     <- depot_ship_result()

      progress_ui <- if (active) {
        tags$div(
          class = "sync-inline-progress",
          tags$div(class = "sync-progress-label", "Shipping…"),
          tags$div(
            class = "progress",
            tags$div(
              class = "progress-bar progress-bar-striped progress-bar-animated",
              role = "progressbar",
              style = "width: 100%;",
              `aria-valuenow` = "100",
              `aria-valuemin` = "0",
              `aria-valuemax` = "100"
            )
          )
        )
      } else {
        NULL
      }

      receipt_ui <- if (!is.null(res)) {
        results <- res$results
        n_total <- if (!is.null(results)) nrow(results) else 0L
        n_ok    <- if (!is.null(results)) sum(results$status == "success") else 0L
        theme   <- if (n_total == 0L) "secondary"
                   else if (n_ok == n_total) "success"
                   else if (n_ok == 0L) "danger" else "warning"
        bslib::value_box(
          "Delivery Receipt",
          sprintf("%d / %d packages delivered", n_ok, n_total),
          sprintf("%.1fs", res$elapsed_sec %||% 0),
          theme = theme
        )
      } else {
        NULL
      }

      empty_text <- "Check packages, then press Ship. Activity appears here."
      tags$div(
        class = paste("sync-log", if (length(entries) == 0) "sync-log-empty" else ""),
        tags$div(
          class = "sync-log-title",
          "Log panel",
          tags$span(
            class = "sync-log-subtitle",
            if (length(entries) == 0) "Waiting for activity" else "Ship actions and delivery results"
          )
        ),
        progress_ui,
        receipt_ui,
        tags$pre(
          id = ns("depot_log_pre"),
          `data-empty` = if (length(entries) == 0) "true" else NULL,
          if (length(entries) == 0) {
            empty_text
          } else {
            HTML(paste(
              vapply(rev(utils::tail(entries, 250)), format_depot_log, character(1)),
              collapse = "\n"
            ))
          }
        )
      )
    })
```

- [ ] **Step 3: Verify the package still loads**

Run: `cd /home/yeli/repos/courieR && R -q -e 'devtools::load_all(); cat("OK\n")'`
Expected: prints `OK`.

(No commit yet — bundled at end of Task 7.)

---

## Task 7: Two-pane workspace layout + wire log writes + remove old receipt

**Files:**
- Modify: `inst/app/modules/mod_depot_ship.R:60-100` (UI restructure)
- Modify: `inst/app/modules/mod_depot_ship.R:395-461` (ship observer: write log lines)
- Modify: `inst/app/modules/mod_depot_ship.R:464-498` (remove old receipt outputs)

- [ ] **Step 1: Restructure the UI into the two-pane workspace**

In `mod_depot_ship_ui`, replace everything from the chips line through the receipt (the body after the `tags$script(...)` helper — i.e. the old Zone 2 / Zone 3 / receipt block, roughly lines 64-99) with:

```r
    # Filter chips span the full width above the workspace
    uiOutput(ns("ship_chips")),

    div(
      class = "sync-workspace",

      # Left pane — toolbar + table + plan summary + ship button
      div(
        class = "sync-comparison-pane",
        div(
          class = "depot-ship-toolbar",
          textInput(ns("ship_search"), label = NULL,
                    placeholder = "Search packages…", width = "220px"),
          div(
            class = "depot-ship-bulk",
            tags$span(class = "depot-ship-mode-label", "How to ship:"),
            selectInput(
              ns("ship_mode"), label = NULL,
              choices  = c("Install online" = "online", "Ship as-is" = "ship"),
              selected = "online",
              selectize = FALSE,
              width = "150px"
            ),
            actionButton(ns("select_all"), "Select all shown",
                         class = "btn btn-sm depot-select-all-btn",
                         onclick = sprintf("courierDepotSelectAll('%s', true)", ns("ship_table"))),
            actionButton(ns("clear_sel"), "Clear",
                         class = "btn btn-sm depot-clear-sel-btn",
                         onclick = sprintf("courierDepotSelectAll('%s', false)", ns("ship_table")))
          )
        ),
        DT::dataTableOutput(ns("ship_table")),
        uiOutput(ns("plan_summary")),
        div(
          class = "depot-ship-footer",
          actionButton(ns("depot_ship_btn"), "Ship",
                       class = "btn sync-compare-btn depot-ship-execute-btn",
                       onclick = "if(window.courierStartTimer) window.courierStartTimer();")
        )
      ),

      # Right pane — log
      div(
        class = "sync-log-pane",
        uiOutput(ns("depot_log_ui"))
      )
    )
```

The closing `)` of the outer `div(class = "depot-ship-pane", ...)` stays. Ensure there is exactly one `tags$script(...)` helper before the chips and no leftover `uiOutput(ns("depot_receipt"))`.

- [ ] **Step 2: Write log lines during ship execution**

In the `observeEvent(input$depot_ship_btn, ...)` block, after `depot_ship_result(NULL)` (line 396), add a log reset:

```r
      depot_log(character(0))
```

Inside the `for (i in seq_along(batches))` loop (after the `courieR::ship(...)` call returns into `res`, around line 418), add per-batch log lines:

```r
          depot_log_append(sprintf("Shipped %d package(s) [%s] → %s",
                                   length(b$pkgs), b$mode,
                                   basename(dirname(dirname(b$tgt)))))
```

In the error handler (the `error = function(e) {...}` around line 425), add:

```r
        depot_log_append("[ERR] ", e$message)
```

After the loop completes and `elapsed` is computed (around line 435), add a summary line:

```r
      depot_log_append(sprintf("Done — %d package(s) in %.0fs.", total, elapsed))
```

- [ ] **Step 3: Remove the old below-table receipt outputs**

Delete the `output$depot_receipt_dt <- DT::renderDataTable({...})` block (lines 465-471) and the `output$depot_receipt <- renderUI({...})` block (lines 473-498). The receipt now renders inside `output$depot_log_ui` (Task 6). Keep the `depot_ship_result` reactiveVal and its `depot_ship_result(list(...))` assignment — the log pane reads it.

- [ ] **Step 4: Verify no orphaned references**

Run: `grep -n "depot_receipt\|context_bar\|Version A\|Version B" /home/yeli/repos/courieR/inst/app/modules/mod_depot_ship.R`
Expected: no matches.

- [ ] **Step 5: Verify the package loads**

Run: `cd /home/yeli/repos/courieR && R -q -e 'devtools::load_all(); cat("OK\n")'`
Expected: prints `OK`.

- [ ] **Step 6: Run the full test suite**

Run: `cd /home/yeli/repos/courieR && R -q -e 'devtools::test()'`
Expected: all tests pass.

- [ ] **Step 7: Commit the depot-ship reshape**

```bash
cd /home/yeli/repos/courieR
git add inst/app/modules/mod_depot_ship.R
git commit -m "feat(custom-dispatch): two-pane table+log layout, source/target labels, drop context bar"
```

---

## Task 8: Manual app verification

**Files:** none (verification only)

- [ ] **Step 1: Launch the app**

Run: `cd /home/yeli/repos/courieR && R -q -e 'shiny::runApp("inst/app", port = 7654, launch.browser = FALSE)'`
(Or install locally on Windows per project memory and open there.)

- [ ] **Step 2: Confirm the navbar shows 5 flat tabs**

Expected top-level tabs, left to right: **Bulk Dispatch · Browse · Custom Dispatch · Manifest · Maintenance**. No nested card-tab strip anywhere.

- [ ] **Step 3: Confirm Custom Dispatch layout**

On Custom Dispatch: no `A: bin → B: bin` context bar; chips read "newer in source / newer in target / not in target / not in source"; table columns read **Source** / **Target**; table is on the left, **Log panel** on the right (same proportions as Bulk Dispatch).

- [ ] **Step 4: Confirm the Browse → Custom Dispatch bridge**

On Browse, select a package and click "View '<pkg>' in Ship" → the app switches to the Custom Dispatch tab with that package pre-searched.

- [ ] **Step 5: Confirm a ship run logs progress**

Run a real Compare (Bulk Dispatch) then ship 1 package from Custom Dispatch. Expected: progress bar animates while shipping, log pane fills with "Shipped … → …" and "Done — 1 package(s) in Ns.", and a Delivery Receipt value box appears in the log pane.

- [ ] **Step 6: Confirm the badge moved**

When actionable packages exist, the count badge appears on the **Custom Dispatch** tab title (not on a now-removed Advanced tab).

---

## Self-Review Notes

- **Spec coverage:** Nav rename (T1), Advanced removal + flat panels (T1), badge move (T1/T2), mod_origin split (T3), Browse→Ship JS bridge (T3), context bar removal (T4), chip/header rename (T5), log pane (T6), two-pane layout + log writes + receipt relocation (T7). All spec sections mapped.
- **Out of scope (per spec):** real-time streaming during `ship()` (still blocking; progress bar is client-side timer only), internal status-string renames.
- **Type/name consistency:** `mod_origin_browse_ui` / `mod_origin_ship_ui` used consistently in ui.R (T1) and defined in mod_origin.R (T3); `custom_dispatch_badge` used in ui.R (T1) and server.R (T2); `navigateToCustomDispatch` defined in ui.R (T1) and called in mod_origin.R (T3); `depot_log` / `depot_log_append` / `depot_log_ui` / `depot_log_pre` consistent across T6/T7.
