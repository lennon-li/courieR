# Design: Depot Ship Tab + Advanced Tab Streamline

**Date:** 2026-06-07
**Status:** Approved

---

## Goals

1. Streamline the Advanced tab from 5 sub-tabs to 2 by relocating Restock and Delivery Receipt into Dispatch, and removing Route.
2. Add package-level selection and action assignment inside Depot (new Ship sub-tab).
3. Make the new Ship sub-tab discoverable without disrupting the existing full-batch Dispatch workflow.

---

## Tab Structure

### Before

```
Dispatch
Advanced
  ├── Restock
  ├── Depot
  ├── Delivery Receipt
  ├── Route
  └── Manifest
```

### After

```
Dispatch
Advanced
  ├── Depot
  │     ├── Browse   (existing read-only manifest, minor additions)
  │     └── Ship     (new package selection + action UI)
  └── Manifest
```

---

## Section 1 — Tab Restructure

### Route tab → removed
The Route tab displays only the selected A and B Rscript paths, which are already visible in the Dispatch sidebar. No unique information or actions; removed entirely.

### Delivery Receipt → folded into Dispatch
After a Ship completes in Dispatch, a collapsible "Delivery Receipt" card appears below the comparison table showing N/N packages delivered. Expanded view contains the existing Results and Plan sub-tables. The card is dismissed (hidden) when a new Compare runs. The standalone Delivery Receipt Advanced sub-tab is removed.

### Restock → moved into Dispatch sidebar
A "Restock from CRAN" button is added to the Dispatch sidebar below the Ship button, under a "Maintenance" label. Enabled when an installation is selected. Triggers the same confirm modal logic as the current mod_update module. The standalone Restock Advanced sub-tab is removed.

### mod_update.R
The Restock module UI/server logic moves into mod_sync.R (or a small inline helper) since it now lives in the Dispatch sidebar. mod_update.R can be removed or kept as an unexported helper.

---

## Section 2 — Dispatch Changes

### Sidebar additions
- "Maintenance" section label below the Ship button `<hr>`
- "Restock A from CRAN" and "Restock B from CRAN" buttons (enabled/disabled based on whether install_a / install_b are set)
- Confirm modal identical to current Restock modal

### Post-ship receipt panel
- `uiOutput("delivery_receipt")` rendered below the comparison table card
- Hidden by default; shown after `observeEvent(input$confirm_sync)` completes
- Contains a `bslib::value_box` (N/N delivered) + collapsible Results/Plan DT tables
- Cleared (hidden) on next `observeEvent(input$compare)`

### Dispatch → Depot hint
- Rendered as part of `output$comparison_summary` after compare
- Condition: comparison exists and at least one package has a non-`same` status
- Markup: `<p class="depot-ship-hint">Cherry-pick packages → <a>Advanced › Depot › Ship</a></p>`
- The link calls `bslib::nav_select()` to navigate to Advanced › Depot and activate the Ship sub-tab
- Hidden when no diffs exist

---

## Section 3 — Depot Redesign

### Browse sub-tab
Existing `mod_origin.R` content, unchanged except:
- Wrapped in `bslib::nav_panel("Browse", ...)`
- "View in Ship" action button added to the package table toolbar; clicking it switches to the Ship sub-tab and pre-populates the search box with the selected package name

### Ship sub-tab

#### Zone 1 — Context bar
- Read-only display: Installation A, Installation B, direction, transfer mode — all inherited from Dispatch via reactive vals passed into the module
- If no comparison data: `"Run Compare in Dispatch first."` prompt
- If comparison data exists but direction = "full" (two-way): supported, defaults shown for both directions

#### Zone 2 — Table with filters and toolbar

**Status filter chips** (same visual style as Dispatch chips):
- same / missing-from-B / missing-from-A / newer-in-A / newer-in-B
- Clicking a chip toggles visibility of that status group in the table
- Default: all diff statuses active, `same` inactive (mirrors Dispatch chip default)

**Search box:** filters table by package name (DT server-side or client-side filter)

**Bulk action toolbar:**
- "Set selected to: [Skip | Ship as-is | Install online] → Apply" above the table
- Applies chosen action to all checked rows

**Table columns:**
- Checkbox (DT row selection)
- Package
- Version A
- Version B
- Status (colored badge)
- Action (colored badge: Skip / Ship as-is / Install online)

**Row defaults on load** (derived from Dispatch state):
- Packages in active sync direction (missing or newer on target side) → default to Dispatch transfer mode
- `same` packages → Skip
- Packages in wrong direction → Skip
- Two-way: each package defaults to whichever direction it belongs

#### Zone 3 — Plan summary + Ship
- Summary line: `N × install online · N × ship as-is · N × skip`
- Ship button: disabled until at least one row has a non-Skip action
- After ship: inline receipt banner (same pattern as Dispatch post-ship panel)
- Post-ship: re-run comparison refresh, update the context bar

---

## Section 4 — Discoverability

### Advanced tab badge
- `bslib::nav_panel("Advanced", bslib::nav_item(badge_ui), ...)` or injected via `shinyjs`
- Badge shows count of actionable packages (non-`same` status) when comparison data exists
- Clears after a Ship from either Dispatch or Depot › Ship, or when a new Compare runs
- Implemented as a `reactiveVal` shared between mod_sync and mod_origin servers via server.R

### Dispatch hint link
- Appears below chip summary bar after Compare when diffs > 0
- Styled as `.depot-ship-hint` — muted helper text, not a notification
- Navigates to Advanced › Depot › Ship tab on click

---

## Data Flow

```
server.R
  ├── routes_cache        reactiveVal  → mod_sync, mod_origin
  ├── from_r_path         reactiveVal  → mod_sync, mod_origin, mod_manifest
  ├── to_r_path           reactiveVal  → mod_sync, mod_origin, mod_manifest
  ├── comparison_rv       reactiveVal  → mod_sync, mod_origin (NEW — shared comparison)
  └── actionable_count    reactiveVal  → Advanced tab badge (NEW)
```

`comparison_rv` is populated by mod_sync after each Compare and consumed by mod_origin's Ship sub-tab to populate the package table and defaults. This avoids re-running manifest() when switching tabs.

---

## Files Affected

| File | Change |
|------|--------|
| `inst/app/ui.R` | Remove Route + Restock + Receipt nav panels; add Depot sub-tabs; Advanced badge |
| `inst/app/server.R` | Add comparison_rv, actionable_count reactiveVals; wire new module args |
| `inst/app/modules/mod_sync.R` | Add Restock sidebar buttons + logic; add post-ship receipt panel; add Depot hint |
| `inst/app/modules/mod_origin.R` | Add Browse/Ship sub-tabs; implement Ship sub-tab UI + server logic |
| `inst/app/modules/mod_update.R` | Logic folded into mod_sync.R; file removed or kept as internal helper |
| `inst/app/modules/mod_receipt.R` | Logic folded into mod_sync.R; file removed |
| `inst/app/www/styles.css` | Styles for: receipt panel, restock sidebar, depot-ship-hint, Ship sub-tab zones, action badges, plan summary bar |

---

## Out of Scope

- Per-version pinning (install package at a specific older version)
- Manifest tab changes
- CLI / non-Shiny API changes
