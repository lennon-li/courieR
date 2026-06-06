## Resubmission (0.2.3)

This is a resubmission with bug fixes, performance improvements, and UX enhancements.

### Changes since 0.2.2

* `manifest()` now excludes base and recommended packages via three guards: Priority
  field, case-insensitive library path comparison (fixes silent failures on Windows
  where path capitalisation differs), and a name list from
  `installed.packages(priority = c("base", "recommended"))`. Packages such as
  `translations` can no longer appear in a sync plan.

* `ship()` gains an optional `log_callback` argument (function of one character
  argument) for real-time progress messages from the pak subprocess. Existing callers
  are unaffected; the argument defaults to `NULL`.

* `hub()` added as a short exported alias for `open_hub()`.

* `.onAttach()` added: prints the package version and a one-line usage hint when the
  package is attached. Uses `packageStartupMessage()` so it respects
  `suppressPackageStartupMessages()`.

* `find_routes()` per-candidate subprocess timeout reduced from 5 s to 3 s.

* `shinyjs` added to Imports (was missing; required for the real-time log DOM updates
  in the Sync dashboard).

* Sync dashboard: `withProgress()` / `incProgress()` / `shiny:::flushReact()` /
  `later::run_now()` removed. Replaced with `shinyjs::runjs()` for immediate DOM
  log appends and a `reactiveVal`-driven inline progress bar.

## Test environments

* local Windows 11, R 4.6.0 and R 4.5.2
* GitHub Actions: ubuntu-latest (release, devel), windows-latest (release, devel), macos-latest (release)

## R CMD check results

0 errors | 0 warnings | 1 note

* NOTE: Imports includes packages only used in the Shiny app (`shiny`, `bslib`,
  `bsicons`, `DT`, `shinyjs`). These are intentional runtime dependencies of
  `open_hub()` / `hub()` and are checked at runtime before launching the app.

## Reverse dependencies

There are no reverse dependencies.

## Notes to CRAN

* `find_routes()` and `ship()` examples are wrapped in `\dontrun{}` because they
  require multiple R installations on the same machine, which is not guaranteed in
  CRAN check environments.
* `rig_install()` example is `\dontrun{}` because it downloads and installs an R version.
* `hub()` and `open_hub()` examples use `if (interactive())` because they launch
  a Shiny application.
* `manifest()` examples use `\donttest{}` because they spawn a subprocess.
* `manifest()` runs package scanning in a subprocess. The script is written to a temp
  file and cleaned via `on.exit()`. All tests calling `manifest()` are guarded with
  `skip_on_cran()`.
* `ship()` runs `pak::pkg_install()` under the target R executable in a subprocess.
  When `dry_run = TRUE`, no installation occurs.
* All subprocess calls have explicit timeouts. All temporary files are cleaned via
  `on.exit()`.
* The package sets no `options()` or `par()`. The `.onAttach()` startup message uses
  `packageStartupMessage()` and is suppressible.
