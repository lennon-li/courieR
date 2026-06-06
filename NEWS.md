# courieR 0.2.3

## New features

* `hub()` — short alias for `open_hub()`. Run `hub()` to launch the dashboard with less typing.
* `library(courieR)` now prints the version number and a reminder to run `hub()` or see `?ship`.
* `ship()` gains a `log_callback` argument for real-time progress messages from the pak subprocess, including a notice when first-time metadata loading may take 1–2 minutes.

## Bug fixes

* `manifest()` now reliably excludes base and recommended packages on Windows. The previous path comparison was case-sensitive and could let packages like `translations` slip through into a sync plan, causing a pak error. The filter now uses case-insensitive path comparison and a name-based guard via `installed.packages(priority = c("base", "recommended"))`.

## Performance & UX

* `find_routes()` per-candidate subprocess timeout reduced from 5 s to 3 s, shortening detection time when multiple R versions are installed.
* Sync dashboard: replaced the floating `withProgress()` modal with an inline Bootstrap progress bar inside the log pane. Log lines now append to the DOM immediately, removing the need for `shiny:::flushReact()`.
* Sync dashboard: detection phase shows a Bootstrap info alert while scanning and records "Detection complete: found N installation(s)." in the sync log.

# courieR 0.2.2

* CRAN resubmission addressing reviewer feedback.

# courieR 0.2.1

* Fixed correctness bugs identified during CRAN review.
* Added centralised error reporting in the Shiny module.

# courieR 0.2.0

* CRAN readiness: hardened documentation, CRAN-safe examples, and CI workflow.
* `ship()` gains a `@section Safety:` block documenting subprocess and library write behavior.
* `manifest()` now uses `deparse()` for library path quoting, fixing edge cases with special characters.
* `manifest()` CSV fallback parsing now handles multi-line CSV output correctly.
* Added `cran-comments.md` and `.github/workflows/R-CMD-check.yaml`.
* DESCRIPTION title simplified; version bumped.

# courieR 0.1.0

* Initial release.
* `find_routes()` detects R installations on Windows, macOS, and Linux,
  including user-local installs.
* `manifest()` scans installed packages from any R installation via subprocess.
* `inventory()` compares two package libraries and reports missing, outdated,
  and newer packages.
* `ship()` migrates packages from one R installation to another using pak.
* `open_hub()` launches a Shiny dashboard for point-and-click migration.
