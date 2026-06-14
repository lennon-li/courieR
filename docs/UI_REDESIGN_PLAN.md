# courieR Shiny UI Redesign Plan

## Conceptual shift

The current 7-tab UI is a **package-developer workflow** (scan project →
run devtools::check → run devtools::test → compare results). The new
2-tab UI is an **end-user package migration tool** (pick old R → pick
new R → select packages → deliver). This is a substantial conceptual
rewrite, not just a layout change. Several modules become irrelevant;
the core reactive contract changes.

------------------------------------------------------------------------

## File-by-file changes

**Files to rewrite completely:**

| File                | Change                                                                               |
|---------------------|--------------------------------------------------------------------------------------|
| `inst/app/ui.R`     | Replace `page_navbar` (7 panels + sidebar) with `page_navbar` (2 panels, no sidebar) |
| `inst/app/server.R` | Replace 4 reactiveVals with new contract; rewire all module calls                    |

**Files to create (new modules):**

| File                             | Purpose                                                                           |
|----------------------------------|-----------------------------------------------------------------------------------|
| `inst/app/modules/mod_migrate.R` | New Tab 1 — From/To dropdowns, package checklist, Deliver button, progress output |

**Files to retain, relocated to Advanced tab:**

| File                              | New location in Advanced  | Changes needed                                                                                                            |
|-----------------------------------|---------------------------|---------------------------------------------------------------------------------------------------------------------------|
| `inst/app/modules/mod_origin.R`   | “Details” subtab          | Minor: remove value_box current R version (not relevant for destination-only install)                                     |
| `inst/app/modules/mod_receipt.R`  | “Delivery Receipt” subtab | Moderate: `baseline_results` / `post_results` contract changes; compare pre/post package lists, not devtools check output |
| `inst/app/modules/mod_manifest.R` | “Manifest” subtab         | Minor: keep as-is; see rmarkdown note in dependency audit                                                                 |

**Files to delete (functionality absorbed or dropped):**

| File                                     | Reason                                                                                                                                                         |
|------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `inst/app/modules/mod_shipment_select.R` | Project-path scan is irrelevant to end-user migration flow                                                                                                     |
| `inst/app/modules/mod_cargo_select.R`    | Single-package pak spec builder; replaced by multi-package checklist in mod_migrate                                                                            |
| `inst/app/modules/mod_dispatch.R`        | devtools::document/test/check workflow is for package developers; end-user flow uses [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md) instead |

------------------------------------------------------------------------

## Tab mapping (old 7 → new 2)

| Old tab              | Old module                | New location                                                                                                                                 |
|----------------------|---------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| 1\. Shipment         | `mod_shipment_select`     | **Dropped** — project path scanning not needed; “From R” dropdown replaces it                                                                |
| 2\. Origin           | `mod_origin`              | **Advanced → “Details” subtab** — R install list and package inventory                                                                       |
| 3\. Destination      | `mod_cargo_select`        | **Migrate Tab** — From/To dropdowns absorb R install selection; package checklist replaces single-package selector                           |
| 4\. Pickup           | `mod_dispatch` (baseline) | **Dropped** — devtools baseline run not part of end-user flow                                                                                |
| 5\. Deliver          | `mod_dispatch` (migrate)  | **Migrate Tab** — Deliver button triggers [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md); `mod_dispatch` logic not reused |
| 6\. Delivery Receipt | `mod_receipt`             | **Advanced → “Delivery Receipt” subtab** — adapted to show per-package migration results                                                     |
| 7\. Manifest         | `mod_manifest`            | **Advanced → “Manifest” subtab** — kept as-is                                                                                                |

Nothing is lost. All 7 functional areas map to the new structure.

------------------------------------------------------------------------

## New ui.R (skeleton)

``` r
ui <- bslib::page_navbar(
  title = "courieR",
  theme = bslib::bs_theme(version = 5, preset = "shiny"),

  bslib::nav_panel(
    "Migrate",
    mod_migrate_ui("migrate")
  ),

  bslib::nav_panel(
    "Advanced",
    bslib::navset_card_tab(
      bslib::nav_panel("Packages",         mod_origin_ui("env")),
      bslib::nav_panel("Delivery Receipt", mod_receipt_ui("results")),
      bslib::nav_panel("Details",          uiOutput("details_panel")),
      bslib::nav_panel("Manifest",         mod_manifest_ui("report"))
    )
  )
)
```

------------------------------------------------------------------------

## New server.R reactive contract

**Remove:**

``` r
project_path      # project-level path — irrelevant
baseline_results  # devtools check baseline — irrelevant
post_results      # devtools check post — irrelevant
sidebar outputs   # sidebar removed
```

**Add:**

``` r
from_r_path    <- reactiveVal(NULL)   # path to origin Rscript
to_r_path      <- reactiveVal(NULL)   # path to destination Rscript
selected_pkgs  <- reactiveVal(NULL)   # character vector of selected package names
migration_log  <- reactiveVal(list()) # per-package migration results
```

**New module wiring:**

``` r
mod_migrate_server("migrate",
  from_r_path, to_r_path, selected_pkgs, migration_log)

mod_origin_server("env",
  from_r_path)                        # show packages from origin R

mod_receipt_server("results",
  migration_log)                      # show post-ship() per-package results

mod_manifest_server("report",
  from_r_path, to_r_path, migration_log)
```

------------------------------------------------------------------------

## New mod_migrate.R design

**UI elements:**

``` r
# From dropdown — find_routes() output
selectInput(ns("from_r"), "From (origin R installation)", choices = NULL)

# To dropdown — find_routes() output
selectInput(ns("to_r"),   "To (destination R installation)", choices = NULL)

# Package checklist — populated after "From" is selected
# uses installed.packages() called via callr on the from_r Rscript
# ALL checked by default
checkboxGroupInput(ns("pkgs"), "Packages to migrate", choices = NULL, selected = NULL)

# Deliver button
actionButton(ns("deliver"), "Deliver", class = "btn-success btn-lg")

# Progress output
verbatimTextOutput(ns("progress"))
```

**Server logic:** 1. On load: call
[`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
→ populate both dropdowns 2. On `from_r` change: call
[`installed.packages()`](https://rdrr.io/r/utils/installed.packages.html)
via [`callr::r()`](https://callr.r-lib.org/reference/r.html) on that
Rscript → populate checklist with all selected 3. On `deliver`: call
`ship(from = from_r_path(), to = to_r_path(), packages = selected_pkgs())`
→ stream output → write results to `migration_log`

> **Action for Codex before implementing:** Verify current
> [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)
> signature accepts `from`, `to`, and `packages` args.

------------------------------------------------------------------------

## Dependency audit

**Current Imports (17 packages):**

| Package      | Used where                                                                                                                                                         | Keep / Move                                                                                                                                                                                                                        |
|--------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `processx`   | [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md), [`dispatch()`](https://lennon-li.github.io/courieR/reference/dispatch.md) subprocess management | **Keep** — core to migration                                                                                                                                                                                                       |
| `callr`      | subprocess R calls                                                                                                                                                 | **Keep** — needed to query [`installed.packages()`](https://rdrr.io/r/utils/installed.packages.html) on foreign R                                                                                                                  |
| `pak`        | package installation                                                                                                                                               | **Keep** — core to migration                                                                                                                                                                                                       |
| `jsonlite`   | result serialization                                                                                                                                               | **Keep** — used in CLI internals                                                                                                                                                                                                   |
| `desc`       | DESCRIPTION file parsing                                                                                                                                           | **Move to Suggests** — only needed for package-project inspection, not plain R install migration                                                                                                                                   |
| `fs`         | file system ops                                                                                                                                                    | **Keep** — path handling throughout                                                                                                                                                                                                |
| `cli`        | CLI output formatting                                                                                                                                              | **Keep** — CLI functions remain                                                                                                                                                                                                    |
| `data.table` | tabular data                                                                                                                                                       | **Keep** — used throughout                                                                                                                                                                                                         |
| `shiny`      | UI                                                                                                                                                                 | **Keep**                                                                                                                                                                                                                           |
| `bslib`      | UI                                                                                                                                                                 | **Keep**                                                                                                                                                                                                                           |
| `bsicons`    | icons                                                                                                                                                              | **Keep** — lightweight                                                                                                                                                                                                             |
| `DT`         | data tables                                                                                                                                                        | **Keep** — package checklist needs it                                                                                                                                                                                              |
| `renv`       | renv lock file detection                                                                                                                                           | **Move to Suggests** — only needed for [`inspect_shipment()`](https://lennon-li.github.io/courieR/reference/inspect_shipment.md) renv check; not in migration path                                                                 |
| `stringr`    | string operations                                                                                                                                                  | **Keep** — replaceable with base R but not worth the risk                                                                                                                                                                          |
| `yaml`       | YAML parsing                                                                                                                                                       | **Move to Suggests** — likely only used by renv/manifest path                                                                                                                                                                      |
| `xml2`       | XML parsing                                                                                                                                                        | **Investigate** — unclear usage; likely R CMD check output parsing in [`parse_inspection_log()`](https://lennon-li.github.io/courieR/reference/parse_inspection_log.md); if so, move to Suggests (only used in old developer path) |
| `rmarkdown`  | manifest report rendering                                                                                                                                          | **Move to Suggests** — heavy dep; manifest download is an Advanced-tab feature; disable gracefully if not installed                                                                                                                |

**Summary:**

| Category            | Count | Packages                                                                       |
|---------------------|-------|--------------------------------------------------------------------------------|
| Current Imports     | 17    | —                                                                              |
| Recommended Imports | 11    | processx, callr, pak, jsonlite, fs, cli, data.table, shiny, bslib, bsicons, DT |
| Move to Suggests    | 4–5   | desc, renv, yaml, rmarkdown (+ xml2 pending investigation)                     |
| Net reduction       | −6    | —                                                                              |

> **Action for Codex:** Before moving `xml2`, grep `R/` for `xml2::`
> calls to confirm what it parses.

------------------------------------------------------------------------

## Wiring risks

**1. `mod_receipt` contract change (high risk)** Current: takes
`baseline_results` + `post_results` (both
`list(check=data.table, test=data.table)` from devtools parsing). New:
takes `migration_log` (per-package install results from
[`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)).
Internal comparison logic needs full rewrite. UI output can stay similar
(before/after table) but data source is completely different.

**2. `mod_origin` argument change (medium risk)** Current
`mod_origin_server` takes `project_path` and calls
`inspect_shipment(path)` + `take_inventory(path)`. New signature takes
`from_r_path` and calls
[`installed.packages()`](https://rdrr.io/r/utils/installed.packages.html)
on that R. The “Detected R Installations” table is fine (still calls
[`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md));
the “Dependencies” table changes source.

**3. `mod_manifest` signature change (low risk)** Currently takes only
`project_path`. New signature needs `from_r_path`, `to_r_path`,
`migration_log`. The Rmd template will need updating.

**4. `mod_dispatch` removal (low risk to tests)** `mod_dispatch` is
tested indirectly only via `parse_inspection_log` and
`parse_dispatch_log` tests. Those parsing functions stay in the package
(used by CLI). Tests will not break.

**5. Duplicate
[`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
calls (low risk)** Called in both Migrate tab and Advanced Details tab.
Lift to a top-level `routes <- reactive({ find_routes() })` in server.R
and pass down to both modules.

**6. Module namespace collisions (none expected)** All modules use
`NS(id)` correctly. The two `mod_dispatch_server` instances being
removed eliminates the only namespace collision risk.

------------------------------------------------------------------------

## UI framework recommendation

**Keep bslib.** Reasons: - Already in Imports, already used throughout -
`page_navbar` is exactly the right primitive for a 2-tab layout -
[`bslib::navset_card_tab`](https://rstudio.github.io/bslib/reference/navset.html)
handles Advanced subtabs cleanly without extra dependencies - Bootstrap
5, modern look, value_box/card components already in use -
`shinydashboard` would add a heavy dependency and an older aesthetic
with no benefit - Plain shiny would require custom CSS to match current
polish

No framework change needed.

------------------------------------------------------------------------

## Advanced tab subtab structure

Use
[`bslib::navset_card_tab`](https://rstudio.github.io/bslib/reference/navset.html)
with 4 subtabs (not collapsible panels — simpler, more reliable for
Codex to implement):

1.  **Packages** — full package inventory from origin R (from
    `mod_origin`)
2.  **Delivery Receipt** — per-package migration outcome table (adapted
    `mod_receipt`)
3.  **Details** — origin + destination R installation info
4.  **Manifest** — download report (`mod_manifest`)

------------------------------------------------------------------------

## Test impact

- 99 existing tests: none test Shiny modules directly. No test files
  import, source, or call any module function.
- `test-parse_dispatch_log.R` and `test-parse_inspection_log.R` test
  parsing functions that remain in the package — unaffected.
- [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md),
  [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md),
  [`take_inventory()`](https://lennon-li.github.io/courieR/reference/take_inventory.md)
  are the functions the new UI calls most — their tests remain valid.
- UI restructure introduces zero test regressions.

------------------------------------------------------------------------

## Codex implementation order

    1. Grep R/ for xml2:: usage → confirm whether xml2 moves to Suggests
    2. Verify ship() signature (accepts from, to, packages args)
    3. Rewrite inst/app/ui.R (skeleton above, ~15 lines)
    4. Rewrite inst/app/server.R (new reactive contract, ~20 lines)
    5. Write inst/app/modules/mod_migrate.R (new module, ~80 lines)
    6. Adapt mod_origin.R: change argument from project_path to from_r_path
    7. Adapt mod_receipt.R: change data contract to migration_log
    8. Adapt mod_manifest.R: add from_r_path, to_r_path, migration_log params
    9. Delete mod_shipment_select.R, mod_cargo_select.R, mod_dispatch.R
    10. Update DESCRIPTION Imports/Suggests per audit above
    11. Run existing 99 tests — should all pass unchanged
    12. Manual smoke test: launch open_hub(), confirm From/To populate, Deliver fires
