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
