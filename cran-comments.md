## Resubmission (0.2.2)

This is a resubmission addressing feedback from the CRAN MKL supplementary check
and fixing correctness issues found during review.

### Changes since 0.2.1

* Added `skip_on_cran()` to the remaining `manifest()` test in `test-manifest.R`
  that still spawned a subprocess on CRAN (`manifest handles empty library gracefully`).
  This completes the CRAN-side guarding of all tests that execute `manifest()`.

### Changes since 0.2.0

* Added `skip_on_cran()` to all tests in `test-manifest.R` that call `manifest()`.
  These tests spawn a subprocess to scan R libraries, which is too slow and
  environment-dependent for CRAN check machines (caused 3 test failures on the
  MKL Fedora supplementary check).

* Fixed 8 correctness bugs in the core API (inspect_shipment, manifest, wrap, ship,
  find_routes, inventory) found during pre-release code review.

* Moved Shiny-related packages (shiny, bslib, bsicons, DT) from Imports to Suggests.
  The core CLI workflow (find_routes, manifest, inventory, ship) has no Shiny
  dependency. open_hub() checks at runtime and emits a clear install message if
  dashboard packages are missing.

* Added in-app error reporter: unhandled errors in the Shiny dashboard surface a
  modal with a pre-filled GitHub issue link so users can report bugs.

* Expanded the vignette with a full CLI workflow walkthrough.

## Test environments

* local Windows 11, R 4.5.0
* GitHub Actions: ubuntu-latest (release, devel), windows-latest (release, devel), macos-latest (release)

## R CMD check results

0 errors | 0 warnings | 0 notes

## Reverse dependencies

There are no reverse dependencies.

## Notes to CRAN

* `find_routes()` and `ship()` examples are wrapped in `\dontrun{}` because they
  require multiple R installations on the same machine, which is not guaranteed in
  CRAN check environments.
* `rig_install()` example is `\dontrun{}` because it would download and install an R version.
* `dispatch()` and `open_hub()` examples use `\dontrun{}` because they launch
  background processes or Shiny applications.
* `rig_list()` and `manifest()` examples use `\donttest{}` because they may rely on
  external tools (rig) or subprocess calls that are safe but slow.
* `manifest()` runs package scanning in a subprocess. The subprocess script is
  assembled and written to a temp file which is cleaned via `on.exit()`.
* Tests that execute `manifest()` are skipped on CRAN because subprocess stdout/stderr
  handling can be environment-dependent on supplementary check machines.
* `ship()` uses `pak::pkg_install()` from the current R session to install into the
  target library. This is intentional: the source R need not have pak installed.
  When `dry_run = TRUE`, no installation occurs.
* All subprocess calls have timeouts. All temporary files are cleaned via `on.exit()`.
* The package does not change `options()` or `par()`. No startup messages are emitted
  at package load.
