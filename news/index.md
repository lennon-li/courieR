# Changelog

## courieR 0.3.1

CRAN release: 2026-06-14

### Bug fixes

- Fixed a second cause of shipped packages never showing up as
  installed, on the *copy* path (offline/preserve modes and online
  mode’s local/private packages). A manifest’s `libpath` is the library
  directory shared by every package, but `.copy_plan()` passed it
  through as if it were the per-package source, so each “copy”
  recursively cloned the entire source library into `target/<pkg>/` —
  leaving no valid package where R looks and reporting a silent success.
  The package name is now joined onto the library path, which also
  restores the cross-major compiled-package warning (its `libs/` check
  was always false before). Covered by a `.copy_plan` + `copy_packages`
  regression test and an opt-in browser end-to-end test
  (`COURIER_E2E=true`).
- R installation detection no longer drops installs intermittently on
  slow machines.
  [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  probed each candidate with a hard 3 s timeout and silently discarded
  any that exceeded it, so a cold R start (antivirus, OneDrive-synced
  installs) made versions flicker in and out between runs. The default
  probe timeout is now 30 s, configurable via
  `options(courier.probe_timeout = )`, and a probe that does time out is
  reported with a warning instead of vanishing; the `rig list` timeout
  was also raised from 5 s to 15 s.
- Fixed shipped packages never showing up as installed:
  [`find_target_lib()`](https://lennon-li.github.io/courieR/reference/find_target_lib.md)
  and the pak install subprocess inherited the parent R session’s
  `R_LIBS_USER`, so
  [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)
  installed into the *parent’s* library while Compare scanned the real
  target. All subprocesses that launch another R now share one
  environment-stripping helper (`child_r_env()`), and the install
  destination is guaranteed to be a library that
  [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
  scans.
- Library scans that time out are no longer cached as “empty library”
  for the rest of the session; timeouts are reported loudly in the log
  and the scan timeout was raised from 30 s to 5 min for slow machines.
- The “both installations share one library” warning no longer fires
  vacuously when both scans returned no packages.

### Routing

- Online mode now means online: every package resolvable from CRAN /
  Bioconductor / GitHub is reinstalled via pak (binaries preferred).
  Only local/private packages with no online source are copied from the
  source library. (Previously pure-R CRAN packages were file-copied even
  in online mode, which is much slower than pak on synced/network
  libraries.)

### Performance

- One manifest scan per library per session, shared across all tabs: a
  ship right after Compare reuses the Compare scans and spawns no scan
  subprocesses; the post-ship refresh rescans only the shipped-into
  library.

### Dashboard UX

- **Bulk Dispatch** now shows a live hero panel during shipping
  (matching Custom Dispatch): packages delivered so far, the current
  package being installed, elapsed time, and the estimated total. The
  detailed log in the R console is also mirrored in the dashboard log
  pane.
- Both **Bulk Dispatch** and **Custom Dispatch** tables now default to
  showing only packages missing from the target after Compare, instead
  of all diff statuses. The filter chip bar lets you toggle other
  statuses.
- **Custom Dispatch** filter chips are now colour-coded — orange for
  source-side differences (newer in source, not in target), teal for
  target-side differences — matching Bulk Dispatch.
- **Custom Dispatch** comparison table gains a **Repo** column showing
  where the package comes from (CRAN, Bioconductor, GitHub, etc.).
  Packages with an unknown source are shown in red in both tables.
- [`report_issue()`](https://lennon-li.github.io/courieR/reference/report_issue.md)
  — new exported function. Call it from the console after any error to
  open a pre-filled GitHub issue form in your browser with your R
  version, platform, courieR version, and the error message already
  populated. The dashboard’s error modal gains a **Send Report** button
  that does the same in one click.
- Custom Dispatch shows a live green hero panel while shipping: packages
  delivered so far, the package currently being copied/installed,
  elapsed time, and the estimated total.
- Time estimates (plan summary, ship confirmation, preview invoice) now
  come from per-machine calibrated rates persisted across sessions —
  every completed ship updates them — instead of fixed constants that
  were off by 100x on synced/network drives.
- Custom Dispatch source/target header now shows the R version, install
  location, and library path of both installations (was the bare
  executable path).
- After a Custom Dispatch shipment the comparison tables refresh
  automatically and the depot log says so; the refresh is logged when it
  completes.
- [`library(courieR)`](https://lennon-li.github.io/courieR/) startup
  message now includes a link to the user guide vignette
  ([`vignette("get-started", package = "courieR")`](https://lennon-li.github.io/courieR/articles/get-started.md)).

## courieR 0.3.0

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

### Performance

- Shipping no longer upgrades the entire dependency tree of each
  selected package: the dashboard now calls
  [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md) with
  `upgrade = FALSE`. Selected packages still install or upgrade to the
  latest compatible version, but their already-installed dependencies
  are left alone unless a version requirement forces a change. This
  removes the main cause of multi-minute single-package shipments.
- Custom Dispatch now scans each library at most once per Ship click and
  passes the scans to
  [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)
  (`source_pkgs`/`target_pkgs`), instead of re-scanning both libraries
  for every batch.

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
