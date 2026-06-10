# Changelog

## courieR (development version)

### Dashboard UX

- Flattened the dashboard navigation from three nested tab levels to a
  single row of five top-level tabs: **Bulk Dispatch**, **Browse**,
  **Custom Dispatch**, **Manifest**, and **Maintenance**. The former
  **Advanced** wrapper tab is gone.
- Renamed **Dispatch** → **Bulk Dispatch**, and the former **Ship**
  sub-tab is now the top-level **Custom Dispatch** tab.
- **Custom Dispatch** now uses a two-pane layout — the package table on
  the left and a live log panel (with a delivery receipt) on the right —
  mirroring Bulk Dispatch. Its comparison columns are labelled
  **Source** / **Target** (was *Version A* / *Version B*), its filter
  chips read “newer in source / newer in target / not in target / not in
  source”, and the redundant `A → B` context bar was removed.

## courieR 0.3.0

### Bug fixes

- [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
  no longer leaks the parent R session’s library/home environment into
  the target R subprocess. Previously `processx` inherited `R_LIBS_USER`
  (and `R_HOME`) from the R running courieR, so every probed
  installation reported the parent’s library — making distinct R
  versions appear to share one library and compare as 100% identical.
  The subprocess now strips `R_LIBS_USER`, `R_LIBS`, `R_LIBS_SITE`, and
  `R_HOME` while still reading the target R’s own
  `.Renviron`/`.Rprofile`.
- Dashboard: fixed “Operation not allowed without an active reactive
  context” on startup, caused by reading a `reactiveVal` outside a
  reactive consumer in the sync log helper (now wrapped in `isolate()`).

### Dashboard UX

- Renamed the core actions to match courieR’s shipping vocabulary:
  **Scout** (detect installations), **Inventory** (compare libraries),
  and **Ship** (transfer packages). The main tab is now **Dispatch**,
  and the Advanced tabs are **Restock**, **Depot**, **Delivery
  Receipt**, **Route**, and **Manifest**.
- Detection is no longer automatic on startup; click **Scout** to scan.
  A `Scout → Inventory → Ship` workflow note appears in the control
  panel, and the result is shared across tabs.
- The logo twinkles while the app is busy (tied to Shiny’s busy/idle
  events).
- Comparison table: per-column filters (search boxes for
  package/versions, a dropdown for status), pagination grouped compactly
  below the table, and the global search box removed. The log panel sits
  beside the comparison, spanning its full height.
- Transfer mode options shortened (Online reinstall / Offline copy /
  Preserve version) with a live description of the selected mode.
- [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  is called once per scan and shared across modules instead of being
  re-run by each, reducing startup/detection time.

## courieR 0.2.3

### New features

- [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md) and
  [`migrate()`](https://lennon-li.github.io/courieR/reference/migrate.md)
  gain a `mode` argument:
  - `"online"` (default) — reinstall packages via pak from
    CRAN/GitHub/Bioconductor.
  - `"offline"` — copy package directories by file; packages with no
    valid source path are skipped and reported.
  - `"preserve"` — copy first to keep exact versions; fall back to a
    pinned pak spec (`pkg@version`) for packages that cannot be copied.
    The dashboard Sync tab exposes the same three options as a dropdown.
- `migrate(from, to)` — one-call CLI migration. Pass version strings
  (`"4.5.2"`, `"4.6.0"`) or full Rscript paths; courieR resolves the
  installations and runs
  [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)
  automatically.
- [`hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md) —
  short alias for
  [`open_hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md).
  Run
  [`hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md)
  to launch the dashboard with less typing.
- [`library(courieR)`](https://lennon-li.github.io/courieR/) now prints
  the version number and a reminder to run
  [`hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md)
  or see
  [`?ship`](https://lennon-li.github.io/courieR/reference/ship.md).
- [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)
  gains a `log_callback` argument for real-time progress messages from
  the pak subprocess, including a notice when first-time metadata
  loading may take 1–2 minutes.

### Bug fixes

- [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
  now reliably excludes base and recommended packages on Windows. The
  previous path comparison was case-sensitive and could let packages
  like `translations` slip through into a sync plan, causing a pak
  error. The filter now uses case-insensitive path comparison and a
  name-based guard via
  `installed.packages(priority = c("base", "recommended"))`.

### Performance & UX

- [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  per-candidate subprocess timeout reduced from 5 s to 3 s, shortening
  detection time when multiple R versions are installed.
- Sync dashboard: replaced the floating `withProgress()` modal with an
  inline Bootstrap progress bar inside the log pane. Log lines now
  append to the DOM immediately, removing the need for
  `shiny:::flushReact()`.
- Sync dashboard: detection phase shows a Bootstrap info alert while
  scanning and records “Detection complete: found N installation(s).” in
  the sync log.

## courieR 0.2.2

CRAN release: 2026-06-04

- CRAN resubmission addressing reviewer feedback.

## courieR 0.2.1

- Fixed correctness bugs identified during CRAN review.
- Added centralised error reporting in the Shiny module.

## courieR 0.2.0

CRAN release: 2026-05-30

- CRAN readiness: hardened documentation, CRAN-safe examples, and CI
  workflow.
- [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)
  gains a `@section Safety:` block documenting subprocess and library
  write behavior.
- [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
  now uses [`deparse()`](https://rdrr.io/r/base/deparse.html) for
  library path quoting, fixing edge cases with special characters.
- [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
  CSV fallback parsing now handles multi-line CSV output correctly.
- Added `cran-comments.md` and `.github/workflows/R-CMD-check.yaml`.
- DESCRIPTION title simplified; version bumped.

## courieR 0.1.0

- Initial release.
- [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  detects R installations on Windows, macOS, and Linux, including
  user-local installs.
- [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
  scans installed packages from any R installation via subprocess.
- [`inventory()`](https://lennon-li.github.io/courieR/reference/inventory.md)
  compares two package libraries and reports missing, outdated, and
  newer packages.
- [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)
  migrates packages from one R installation to another using pak.
- [`open_hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md)
  launches a Shiny dashboard for point-and-click migration.
