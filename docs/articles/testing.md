# Testing Guidelines and Platform Status

courieR is transparent about how it is tested. This document describes
the test suite, how to run it on your machine (or as an automated
agent), and the current verification status across platforms.

The package is fully AI-implemented and human-directed. Both human and
agent testers are listed in the status table below.

------------------------------------------------------------------------

## Test suite overview

Tests live in `tests/testthat/` and are organised into three layers:

| Layer                | Files                                                                                                         | What it covers                                                                                                                      |
|----------------------|---------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------|
| **Unit**             | `test-inventory.R`, `test-manifest.R`, `test-ship.R`, `test-copy-packages.R`, `test-estimate.R`, and ~12 more | Pure R logic — comparison, plan building, log parsing, route filtering, rate calibration                                            |
| **Integration**      | `test-find_routes.R`, `test-migrate.R`, `test-wrap.R`                                                         | Spawns real R subprocesses; needs at least one R installation; guarded with `skip_on_cran()`                                        |
| **End-to-end (E2E)** | `test-e2e-ship.R`, `test-app-refresh.R`                                                                       | Drives the full Shiny dashboard in a headless Chrome browser; requires two R installations, a Chrome binary, and `COURIER_E2E=true` |

------------------------------------------------------------------------

## Running tests

### 1. Unit + integration tests (standard)

``` r
# From an R session in the package root
devtools::test()

# Or from the shell
R CMD check --no-manual .
```

All unit tests and CRAN-safe integration tests run without any
environment variables. Tests that spawn subprocesses or modify libraries
are guarded with `skip_on_cran()` and will run locally but not on CRAN.

### 2. E2E browser tests

The E2E tests drive the full dashboard UI with a real Chrome browser
through `shinytest2` and `chromote`. They require:

- Two real R installations (source and target must differ in version or
  path)
- Chrome or Chromium installed
- `shinytest2` and `chromote` R packages
- The **working-tree** courieR installed first (`R CMD INSTALL .`)

``` bash
# 1. Install working-tree version (required — app subprocess does library(courieR))
R CMD INSTALL .

# 2. Set environment variables
export COURIER_E2E=true
export COURIER_E2E_SRC=/path/to/source/Rscript   # e.g. /opt/R/4.4.3/bin/Rscript
export COURIER_E2E_TGT=/path/to/target/Rscript   # e.g. /opt/R/4.5.2/bin/Rscript
export COURIER_E2E_TGT_LIB=/path/to/target/library  # writable target library dir

# 3. Run
Rscript -e "testthat::test_file('tests/testthat/test-e2e-ship.R')"
```

The E2E test:

1.  Opens the dashboard in a 1500×950 headless browser
2.  Picks source and target in **Bulk Dispatch**, clicks Compare,
    previews the plan
3.  Switches to **Custom Dispatch**, searches for a test package
    (`broman`), selects offline mode, ships it
4.  Verifies independently (via
    [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
    in a clean subprocess) that the package was installed into the
    target library with a valid layout and is loadable from target R

### 3. Manual Shiny UI checklist

Run [`hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md)
and work through the checklist below. The E2E test covers the same paths
automatically, but manual testing catches visual regressions and UX
issues that browser automation misses.

#### Bulk Dispatch

- All R installations appear in the source/target dropdowns
- Selecting source constrains target to same-or-newer R versions only
- **Compare** populates the summary chips (identical / newer in source /
  not in target / etc.)
- The comparison table defaults to showing only **not in target**
  packages
- Clicking a chip toggles that status on/off in the table
- Package with an unknown source shows the **Source** cell in red
- **Ship** opens a confirmation dialog with a time estimate
- During ship: the hero panel counts delivered packages live and shows
  elapsed time
- During ship: the log pane updates with each package installed
- After ship: the table refreshes automatically and the shipped packages
  disappear from the “not in target” view

#### Custom Dispatch

- Source/target header shows R version, install path, and library path
- Filter chips are colour-coded: orange = source-side, teal =
  target-side
- Table defaults to **not in target** after Compare
- **Repo** column shows the package source (CRAN, Bioconductor, GitHub,
  unknown)
- Packages with unknown Repo show in red
- Selecting individual rows and clicking **Ship** installs only those
  packages
- During ship: hero panel and log update live
- After ship: table refreshes, shipped rows disappear or change status

#### Error reporter

- Trigger an error (e.g. point source and target at the same
  installation)
- The error modal appears with the error message
- Clicking **Send Report** opens a pre-filled GitHub issue in the
  browser
- Nothing is submitted automatically — you control the final click

#### CLI

``` r
library(courieR)
# Startup message shows version, hub(), ?ship, and the vignette link

report_issue("test error message")
# Should open a pre-filled GitHub issue in the browser

find_routes()
# Should find all R installations on the machine

vignette("get-started", package = "courieR")
# Should open the HTML user guide
```

------------------------------------------------------------------------

## Platform test status

Last updated: 2026-06-13.

| Platform                                     | Tester                     | Unit tests | Integration | E2E browser | Manual UI  |
|----------------------------------------------|----------------------------|:----------:|:-----------:|:-----------:|:----------:|
| **Windows 11** (OneDrive + Defender)         | Human — Lennon Li          |     ✅     |     ✅      |     ⬜      |     ✅     |
| **Linux** — WSL2 Ubuntu 24.04, R 4.6.0       | Agent — Claude Code (Ming) |     ✅     |     ✅      |     ✅      | ✅ partial |
| **macOS** — Mac mini, Apple Silicon, R 4.6.0 | Agent — Claude Code        |     ✅     |     ✅      |     ⬜      |     ⬜     |

**Legend:** ✅ pass  ·  ❌ fail  ·  ⚠️ pass with caveats  ·  ⬜ not yet
run

### Windows notes

- Probe timeouts were the trigger for raising
  [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  timeout from 3 s to 30 s. Cold-started R on OneDrive-synced drives
  regularly exceeded 3 s, causing installations to flicker in and out
  between scans.
- E2E browser tests require Chrome and `chromote`. These have not been
  run on Windows; `skip_if_not_installed("chromote")` protects the test
  suite.
- `R CMD check --no-manual` passes (inconsolata.sty is absent;
  `--no-manual` skips the PDF reference manual).

### Linux notes

- Tested on WSL2 Ubuntu 24.04 with R 4.6.0 (`/usr/bin/R`). Per-version
  libraries live under `~/R/x86_64-pc-linux-gnu-library/<version>/`.
- E2E test verified the `.copy_plan()` nesting bug fix end-to-end:
  package installed with a valid layout and loadable from target R.
- `R CMD check --as-cran --no-manual` produces 0 errors, 0 warnings, 0
  notes.

### macOS notes

**Results — 2026-06-13, Mac mini (Apple Silicon), R 4.6.0**

[`devtools::test()`](https://devtools.r-lib.org/reference/test.html):
FAIL 0 \| WARN 0 \| SKIP 16 \| PASS 180

`devtools::check(manual = FALSE, vignettes = FALSE)`: 0 errors \| 0
warnings \| 1 note

The 1 note is the `:::` call to `.build_issue_url()` inside
`mod_error_reporter.R`. This is intentional — the function is
package-internal and called only from the embedded Shiny app, not from
user code.

**macOS-specific quirks discovered**

1.  **`/var` → `/private/var` symlink.**
    [`withr::local_tempdir()`](https://withr.r-lib.org/reference/with_tempfile.html)
    returns paths under `/var/folders/...`, but
    [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
    normalises paths via
    [`fs::path_real()`](https://fs.r-lib.org/reference/path_math.html),
    resolving them to `/private/var/folders/...`. The test
    `"find_routes detects installs whose probe takes longer than 3s"`
    was failing because `fake %in% res$rscript_path` compared the
    unresolved path against the resolved one. Fixed by wrapping `fake`
    in
    [`fs::path_real()`](https://fs.r-lib.org/reference/path_math.html)
    in the test assertion.

2.  **CRAN framework `R_HOME` overwrite.** The official CRAN macOS
    framework wrapper scripts (`Resources/bin/R`) hardcode `R_HOME_DIR`
    to the symlink `/Library/Frameworks/R.framework/Resources`, which
    always points to the *current* active version. Running any
    version-specific wrapper therefore redirects `R_HOME` to whichever
    version is set as `Current`. Multi-version integration tests must
    use `rig`-managed binaries or the `exec/R` binary directly; the
    standard framework wrappers are unreliable for version isolation.
    The test suite skips multi-install integration tests automatically
    when only one distinct library is detected.

**For future macOS agent runs**

Follow the steps below in order.

**Environment setup**

``` bash
# Check what R installations are present
ls /Library/Frameworks/R.framework/Versions/
ls ~/Library/Frameworks/R.framework/Versions/   # user-local installs
ls /opt/homebrew/bin/R* 2>/dev/null             # Homebrew
~/.local/share/rig/bin/rig list 2>/dev/null     # rig-managed

# Verify at least two R installations exist. If only one is present,
# install a second via rig:
curl -Ls https://rig.r-lib.org/macos.sh | bash
rig install 4.4                                  # example second version
```

**Install Chrome if not present (needed for E2E)**

``` bash
# Check
which google-chrome || which chromium || ls /Applications/Google\ Chrome.app
```

**Run unit + integration tests**

``` r
# In the package root
devtools::test()
```

Expected: 0 failures. Tests that require two R installations skip
automatically if only one is found.

**Run E2E tests**

``` bash
R CMD INSTALL .

export COURIER_E2E=true
# Set to actual paths from `rig list` output
export COURIER_E2E_SRC=/Library/Frameworks/R.framework/Versions/4.4/Resources/bin/Rscript
export COURIER_E2E_TGT=/Library/Frameworks/R.framework/Versions/4.5/Resources/bin/Rscript
export COURIER_E2E_TGT_LIB=~/Library/R/x86_64/4.5/library   # adjust arch/version

Rscript -e "testthat::test_file('tests/testthat/test-e2e-ship.R')"
```

**Run manual checklist**

``` r
library(courieR)
hub()
```

Work through the manual checklist above. Pay particular attention to
[`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
detecting Homebrew and framework R separately — macOS has the most
detection sources of any platform.

**Report results**

Update this table in a PR or open an issue with the `testing` label.
Include:

- macOS version and chip (Intel / Apple Silicon)
- R version(s) tested
- Which tests passed, skipped, or failed
- Any macOS-specific behaviour differences

------------------------------------------------------------------------

## Adding tests

- Unit tests go in `tests/testthat/test-<topic>.R`
- Use `skip_on_cran()` for anything that spawns a subprocess or modifies
  a library
- E2E tests go in `test-e2e-ship.R` (or a new `test-e2e-<feature>.R`)
  and must check `Sys.getenv("COURIER_E2E") == "true"` before running
- `R CMD check --no-manual` must stay at 0 errors / 0 warnings before
  merging
