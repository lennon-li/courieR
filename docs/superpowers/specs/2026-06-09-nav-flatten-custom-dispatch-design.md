# Nav Flatten + Custom Dispatch Layout

**Date:** 2026-06-09  
**Status:** Approved

## Goal

Reduce tab nesting from 3 levels to 1. Rename tabs for clarity. Mirror the Bulk Dispatch two-pane layout (table + log) in Custom Dispatch. Remove noisy labels.

---

## Navigation

**Before:**
```
page_navbar
  Dispatch | Advanced
                └── navset_card_tab
                      Depot | Manifest | Maintenance
                              └── navset_card_tab
                                    Browse | Ship
```

**After:**
```
page_navbar
  Bulk Dispatch | Browse | Custom Dispatch [n] | Manifest | Maintenance
```

- "Dispatch" → **Bulk Dispatch**
- "Advanced" wrapper removed entirely
- Browse and Ship promoted to top-level nav_panels
- Ship renamed **Custom Dispatch**
- Actionable-package badge `[n]` moves from "Advanced" tab title to "Custom Dispatch" tab title
- `navigateToDepotShip()` JS helper renamed `navigateToCustomDispatch()` and updated to click the new tab value

---

## File Changes

### `inst/app/ui.R`

1. Rename `nav_panel("Dispatch", ...)` → `nav_panel("Bulk Dispatch", ...)`
2. Replace the single `nav_panel("Advanced", ...)` block (which contained a `navset_card_tab`) with four separate `nav_panel` entries:
   - `nav_panel("Browse", mod_origin_browse_ui("env"))`
   - `nav_panel(tagList("Custom Dispatch", uiOutput("custom_dispatch_badge", inline=TRUE)), value="Custom Dispatch", mod_origin_ship_ui("env"))`
   - `nav_panel("Manifest", ...)`
   - `nav_panel("Maintenance", ...)`
3. In the inline JS, rename `navigateToDepotShip` → `navigateToCustomDispatch` and update the selector from `[data-value="Advanced"]` + `[data-value="Ship"]` to a single click on `[data-value="Custom Dispatch"]`.

### `inst/app/server.R`

- Rename `output$advanced_badge` → `output$custom_dispatch_badge` (same logic, same CSS class).

### `inst/app/modules/mod_origin.R`

Split `mod_origin_ui` into two entry-point functions. `mod_origin_server` is unchanged.

```r
# New: Browse-only UI entry point
mod_origin_browse_ui <- function(id) {
  ns <- NS(id)
  tagList(
    bslib::card(...),   # Detected Depots card
    bslib::card(...)    # Depot Manifest card
  )
}

# New: Ship-only UI entry point (thin wrapper)
mod_origin_ship_ui <- function(id) {
  ns <- NS(id)
  mod_depot_ship_ui(ns("depot_ship"))
}

# Old mod_origin_ui removed (or kept as deprecated alias if needed)
```

The Browse→Ship bridge (`browse_to_ship_pkg` reactiveVal + `bslib::nav_select`) inside `mod_origin_server` is no longer used for tab switching (the tabs are now top-level). Replace the `bslib::nav_select(ns("depot_tabs"), "Ship")` call with a `navigateToCustomDispatch()` JS trigger instead:

```r
shinyjs::runjs("navigateToCustomDispatch();")
```

### `inst/app/modules/mod_depot_ship.R`

#### 1. Remove context bar

Delete `uiOutput(ns("context_bar"))` from the UI and `output$context_bar <- renderUI(...)` from the server. The source/target paths are already visible in Bulk Dispatch; repeating them here is noise.

#### 2. Rename chip labels (A/B → source/target)

| Old label | New label |
|-----------|-----------|
| `newer in A` | `newer in source` |
| `newer in B` | `newer in target` |
| `not in B` | `not in target` |
| `not in A` | `not in source` |

The underlying status strings (`newer-in-A`, `missing-from-B`, etc.) are internal — leave them unchanged. Only the display labels change.

#### 3. Rename column headers

| Old | New |
|-----|-----|
| `Version A` | `Source` |
| `Version B` | `Target` |

#### 4. Two-pane workspace layout

Wrap the existing table zone and add a log pane using the same `.sync-workspace` CSS grid already defined in `styles.css`:

```r
mod_depot_ship_ui <- function(id) {
  ns <- NS(id)
  div(
    class = "depot-ship-pane",
    tags$script(...),           # existing JS helper
    uiOutput(ns("ship_chips")), # filter chips (no context bar above them)
    div(
      class = "sync-workspace", # reuse existing CSS: 1.5fr table | 0.85fr log
      div(
        class = "sync-comparison-pane depot-ship-table-pane",
        div(class = "depot-ship-toolbar", ...),  # search + mode + select all
        DT::dataTableOutput(ns("ship_table")),
        uiOutput(ns("plan_summary")),
        div(class = "depot-ship-footer", ...)    # Ship button
      ),
      div(
        class = "sync-log-pane",
        uiOutput(ns("depot_log_ui"))
      )
    )
  )
}
```

#### 5. Log pane server logic

Add two reactiveVals:

```r
depot_log      <- reactiveVal(character(0))
depot_ship_active <- reactiveVal(FALSE)
```

`output$depot_log_ui` mirrors `output$sync_log` in mod_sync.R:
- Title "Log panel" with subtitle
- Animated progress bar shown while `depot_ship_active()` is TRUE
- Scrolling `<pre>` with log entries (newest first, max 250 lines)

During ship execution (inside the `observeEvent(input$depot_ship_btn, ...)` block):
- Set `depot_ship_active(TRUE)` at start, `FALSE` on exit
- Trigger the JS timer: `shinyjs::runjs("if(window.courierStartTimer) window.courierStartTimer();")`
- After completion, push result lines into `depot_log` (e.g. "Shipped rlang 1.2.0 → target", error lines, elapsed time)
- Move the receipt summary into the log pane output — remove the `depot_receipt` uiOutput from below the table

Note: `ship()` is synchronous/blocking — the log pane will not stream in real-time during execution. The progress bar is client-side timer only (same as Bulk Dispatch). Real-time streaming is a separate future improvement.

#### 6. Remove `depot_receipt` below-table zone

`uiOutput(ns("depot_receipt"))` and `output$depot_receipt` are removed. Receipt info (package results table) is surfaced in the log pane post-ship instead.

### `inst/app/www/styles.css`

No new CSS required. The `.sync-workspace`, `.sync-comparison-pane`, and `.sync-log-pane` classes already provide the correct two-column grid and sticky log behavior. The existing `.depot-ship-pane` wrapper remains.

If the chips need to span full width above the grid, ensure `uiOutput(ns("ship_chips"))` sits outside the `.sync-workspace` div (it does in the proposed structure above).

---

## Out of Scope

- Real-time log streaming during `ship()` — remains a blocking call; streaming requires async refactor (separate sprint)
- Renaming internal status strings (`newer-in-A`, `missing-from-B`) — display labels only change
- Any changes to Manifest or Maintenance tab content

---

## Success Criteria

1. App loads with 5 flat top-level tabs: Bulk Dispatch, Browse, Custom Dispatch, Manifest, Maintenance
2. No nested card-tabs visible anywhere
3. Context bar (`A: bin → B: bin`) absent from Custom Dispatch
4. Chip labels and column headers say source/target, not A/B
5. Custom Dispatch shows table on left, log pane on right, same proportions as Bulk Dispatch
6. Browse → "View in Ship" button navigates to Custom Dispatch tab
7. Actionable-package badge appears on Custom Dispatch tab, not "Advanced"
8. No regressions in Bulk Dispatch behavior
