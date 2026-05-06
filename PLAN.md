# packport — Implementation Plan

## Context

**Why packport?** Two related but currently unsolved migration problems in R:
1. You upgrade R from 4.3 → 4.4 and need to reinstall all your packages in the new library.
2. You're developing an R package and need to safely upgrade one dependency (e.g., ggplot2 2.x → 3.x) without breaking everything else.

packport = "port your packages." It serves both use cases via a shared programmatic API and an interactive Shiny dashboard. The core functions are usable without Shiny. The dashboard is the human-in-the-loop layer for the second use case.

**Philosophy:** Diagnose first. Show evidence. Let the human decide. Keep an audit trail. No destructive actions without explicit approval.

---

## The Bootstrap Model — Run packport from the OLD R

**packport is always installed and run from the existing (old) R installation.** This eliminates the chicken-and-egg dependency problem entirely.

### Why this works

The user's old R already has a full library of packages. packport is installed there like any other package:

```r
# In old R — install packport once
install.packages("pak")
pak::pak("packport")  # or install.packages("packport") when on CRAN
```

packport then reaches OUT to the new R installation via `processx`, querying the new R's (empty or partial) library without needing packport to be installed there. It installs packages INTO the new R's library directory using pak with an explicit `lib =` argument.

### User workflow for R version migration

```r
# In old R (e.g. R 4.3):
library(packport)

# Option A — programmatic
installs <- detect_r_installations()      # finds R 4.3 and R 4.4
migrate_packages(
  source_path = installs$rscript_path[installs$version == "4.3.3"],
  target_path = installs$rscript_path[installs$version == "4.4.0"]
)

# Option B — Shiny dashboard
launch_app()
```

### What runs where

| Action | Runs in | Mechanism |
|---|---|---|
| `detect_r_installations()` | Old R (host) | filesystem scan + short processx probe |
| `list_packages(old_rscript)` | Old R via processx | subprocess calling old Rscript |
| `list_packages(new_rscript)` | Old R via processx | subprocess calling new Rscript |
| `migrate_packages()` orchestration | Old R (host) | direct function calls |
| pak install into new R lib | Old R via callr | callr::r() with explicit `lib =` target path |
| Baseline/post diagnostics (Shiny) | Old R via callr | callr::r_bg() background subprocess |

### Consequence for list_packages() design

When `list_packages(rscript_path = old_rscript)` is called from within the old R session, it runs a subprocess of ITSELF. The subprocess is identical to the host session, so jsonlite is guaranteed to be available in that subprocess. The JSON fallback to CSV is only needed when pointing at the NEW (empty) R — in that case, the new R may not have jsonlite. The fallback remains important but applies specifically to the target R, not the source.

### No standalone script needed

Because packport runs from the old R (which has a full library), no standalone zero-dependency bootstrap script is required. The README installation instructions are simply:

```
1. In your current R, install packport.
2. Install a new R version (manually or via rig).
3. Run packport::launch_app() or packport::migrate_packages().
```

---

## A. Package Directory Structure

```
packport/
├── DESCRIPTION
├── NAMESPACE                          # roxygen2 generated
├── LICENSE / LICENSE.md
├── README.md
├── NEWS.md
├── .Rbuildignore
├── .gitignore
│
├── R/
│   ├── detect_r_installations.R
│   ├── list_packages.R                # cross-R subprocess (processx)
│   ├── compare_libraries.R
│   ├── migrate_packages.R             # pak orchestration
│   ├── detect_install_source.R        # pak spec resolver (internal)
│   ├── detect_project_type.R
│   ├── scan_dependencies.R            # DESCRIPTION + renv.lock
│   ├── run_r_command.R                # callr background runner
│   ├── parse_check_log.R
│   ├── parse_test_log.R
│   ├── classify_migration_risk.R
│   ├── ensure_migration_dir.R
│   ├── rig.R                          # optional rig wrappers
│   ├── launch_app.R
│   └── utils.R
│
├── inst/
│   └── app/
│       ├── app.R
│       ├── ui.R
│       ├── server.R
│       ├── modules/
│       │   ├── mod_project_select.R
│       │   ├── mod_environment.R
│       │   ├── mod_dependency_select.R
│       │   ├── mod_diagnostics.R      # used for both Tab 4 and Tab 5
│       │   ├── mod_results.R
│       │   └── mod_report.R
│       └── www/
│           └── styles.css
│   └── report_template.Rmd
│
├── tests/
│   ├── testthat.R
│   ├── testthat/
│   │   ├── helper-fixtures.R
│   │   ├── fixtures/                  # log file fixtures for parsers
│   │   ├── test-detect_r_installations.R
│   │   ├── test-list_packages.R
│   │   ├── test-compare_libraries.R
│   │   ├── test-migrate_packages.R
│   │   ├── test-detect_project_type.R
│   │   ├── test-scan_dependencies.R
│   │   ├── test-run_r_command.R
│   │   ├── test-parse_check_log.R
│   │   ├── test-parse_test_log.R
│   │   ├── test-classify_migration_risk.R
│   │   ├── test-ensure_migration_dir.R
│   │   └── test-rig.R
│   └── fixtures/
│       └── toyMigrationPkg/           # minimal test package
│           ├── DESCRIPTION
│           ├── NAMESPACE
│           ├── R/hello.R
│           └── tests/testthat/test-hello.R
│
├── man/                               # roxygen2 generated
└── vignettes/
    ├── getting-started.Rmd
    └── dependency-migration.Rmd
```

**Key layout decisions:**
- `inst/app/` is the canonical Shiny app location; `launch_app()` uses `system.file("app", package = "packport")`.
- `tests/fixtures/toyMigrationPkg/` is outside `tests/testthat/` so testthat does not auto-discover the fixture's own tests.
- All R/ files are one-function-per-file matching the function name.

---

## B. Core Function Signatures

### `detect_r_installations(search_paths = NULL)`
```r
detect_r_installations(search_paths = NULL)
# Returns data.frame: version, major, minor, rscript_path, lib_paths (list-col), is_current
```
- **Windows**: `utils::readRegistry("SOFTWARE\\R-core\\R")` + walk `C:/Program Files/R/`
- **macOS**: glob `/Library/Frameworks/R.framework/Versions/*/Resources/bin/Rscript`
- **Linux**: glob `/opt/R/*/bin/Rscript`, `/usr/lib/R`, plus rig paths
- For each candidate: `processx::run(rscript, c("--vanilla", "-e", "cat(R.version$major...)"), timeout = 5)` to confirm and extract version
- `is_current` detected by comparing `fs::path_real(rscript_path)` to current session's Rscript

### `list_packages(rscript_path = NULL, lib_path = NULL, format = c("data.table", "data.frame"), timeout_sec = 30L)`
```r
# Returns data.table: package, version, priority, lib_path, source
```
Cross-R subprocess strategy — see Section C.

### `compare_libraries(source_pkgs, target_pkgs)`
```r
# Returns list:
#   $missing   — in source, absent from target (excludes base/recommended)
#   $outdated  — source version > target version
#   $newer     — target version > source version
#   $same      — identical versions
#   $summary   — single-row data.frame with counts
```
Uses `data.table::merge()` + `numeric_version()` comparisons.

### `migrate_packages(source_path, target_path, packages = NULL, dry_run = FALSE, upgrade = FALSE, ...)`
```r
# Returns list:
#   $comparison — output of compare_libraries()
#   $plan       — data.table: package, action, pak_spec
#   $results    — data.table: package, status, message
#   $dry_run    — logical echo
#   $elapsed_sec — numeric
```
Orchestrator: calls `list_packages()` on source, `compare_libraries()`, then installs via pak into target lib. Sets `attr(result, "partial") = TRUE` on partial failures.

### `detect_project_type(project_path)`
```r
# Returns named list:
#   is_package, has_description, has_renv, has_git, has_tests,
#   has_shiny, has_quarto, r_files, test_files, app_files, project_path
```
Uses `fs::dir_exists()`, `fs::dir_ls()`. For `is_package`: attempts `desc::desc()` and checks `Package` field is non-empty, wrapped in `tryCatch()`.

### `scan_dependencies(project_path)`
```r
# Returns data.table:
#   package, source (Imports/Depends/Suggests/renv.lock),
#   constraint, installed_version, lockfile_version, target_version (NA), status
```
- DESCRIPTION: parsed with `desc::desc()`, extracts Depends/Imports/Suggests/LinkingTo
- renv.lock: parsed with `jsonlite::read_json()`, field `packages[[pkg]]$Version`
- `installed_version`: from `utils::installed.packages()` in current session

### `run_r_command(project_path, expr, phase, label, rscript_path = NULL, timeout_sec = 600L)`
```r
# Returns named list:
#   phase, label, status ("success"/"error"/"timeout"),
#   exit_code, stdout_path, stderr_path,
#   start_time, end_time, duration_sec
```
Uses `callr::r_bg()`. Shiny server stores the process handle in `reactiveVal`; `invalidateLater(1000)` polls `proc$is_alive()`. Logs saved to `.migration-dashboard/logs/<phase>/<label>_{stdout,stderr}.txt`.

### `parse_check_log(log_path)`
```r
# Returns data.table: severity, message, file, line, raw_block
```
Reads with `readLines()`. Splits on `^\\*` or block headers. Classifies ERROR/WARNING/NOTE by line header. Extracts `file.R:line` refs via regex.

### `parse_test_log(log_path)`
```r
# Returns data.table: file, test, status (PASS/FAIL/ERROR/SKIP/WARN), message
```
Auto-detects format: JUnit XML (parsed with `xml2::read_xml()`) vs testthat v3 human-readable text.

### `classify_migration_risk(baseline_results, post_results)`
```r
# Returns list:
#   $risk ("high"/"medium"/"low"/"unknown")
#   $rationale — character vector
#   $new_errors, $new_warnings, $resolved, $test_delta — data.tables
```
Rules: NULL results → "unknown"; new ERROR or test regression → "high"; new WARNING → "medium"; notes/improvement only → "low".

### `ensure_migration_dir(project_path)`
```r
# Creates .migration-dashboard/{logs/baseline,logs/post_migration,reports,cache,artifacts}
# Idempotent (fs::dir_create, recurse = TRUE)
# Writes .migration-dashboard/.gitignore containing "*"
# Returns invisibly the .migration-dashboard/ path
```

### `launch_app(project_path = NULL, port = NULL, launch.browser = TRUE)`
```r
app_dir <- system.file("app", package = "packport")
shiny::shinyOptions(packport_project_path = project_path)
shiny::runApp(app_dir, port = port, launch.browser = launch.browser)
```

### Rig wrappers (R/rig.R)
```r
rig_available()           # Sys.which("rig") > 0
rig_list()                # processx::run("rig", "list") → data.frame
rig_install(version, wait = TRUE)  # processx::run("rig", c("install", version), timeout = 600)
```
All degrade gracefully when rig is absent.

---

## C. Cross-R Subprocess Strategy (list_packages)

**The problem:** `installed.packages()` in the running R session cannot query a different R binary's libraries.

**Solution:** Write a temp R script, execute it with the target Rscript via `processx::run()`, parse stdout as JSON.

```r
# Script written to tempfile, deleted on.exit()
script <- '
suppressPackageStartupMessages({
  pkgs <- as.data.frame(
    installed.packages(lib.loc = <lib_path>,
                       fields = c("Package","Version","Priority","Repository","RemoteType")),
    stringsAsFactors = FALSE
  )
  pkgs$source <- ifelse(!is.na(pkgs$Repository) & grepl("CRAN", pkgs$Repository), "CRAN",
    ifelse(!is.na(pkgs$RemoteType) & pkgs$RemoteType == "github", "GitHub",
    ifelse(!is.na(pkgs$RemoteType) & pkgs$RemoteType == "bioc", "Bioconductor", "unknown")))
  names(pkgs) <- tolower(names(pkgs))
  cat(jsonlite::toJSON(pkgs, auto_unbox = TRUE, na = "null"))
})
'
result <- processx::run(
  command = rscript_path,
  args    = c("--vanilla", tmp_script),
  timeout = timeout_sec,
  error_on_status = FALSE,
  windows_verbatim_args = FALSE  # let processx handle quoting
)
```

**Error handling hierarchy:**
1. Rscript not found → `tryCatch()` catches ENOENT → `cli::cli_abort(class = "packport_rscript_not_found")`
2. Timeout → `result$timeout == TRUE` → return NULL with `attr(..., "timed_out") = TRUE`
3. Non-zero exit → `cli::cli_warn()` stderr content → throw `"packport_subprocess_error"`
4. JSON parse failure → save raw stdout to cache, throw `"packport_json_parse_error"`
5. jsonlite missing in target R → detect "no package called 'jsonlite'" in stderr → fall back to base-R CSV script

**Windows path note:** Always pass `rscript_path` as `command =` argument, never paste into a shell string. `processx` handles argument quoting correctly.

---

## D. pak Multi-Source Install Integration

Internal `detect_install_source(package, version = NULL, source_hint = NULL, github_ref = NULL)`:

| Condition | pak spec |
|---|---|
| source_hint = "local", version is a path | `"local::/abs/path"` |
| source_hint = "Bioconductor" | `"bioc::package"` |
| source_hint = "GitHub" + ref | `"owner/repo@ref"` |
| version = NULL | `"package"` (CRAN latest) |
| version = exact semver | `"package@1.2.3"` |
| version has `>= X` | `"package"` (pak resolves latest satisfying) |

**Why callr for pak installation into target lib:**
`pak::pkg_install(specs, lib = target_lib)` installs into any writable path. We use the host R's pak but pass `lib =` pointing to the target R's library. This avoids needing pak installed in the target R.

```r
callr::r(
  func = function(specs, lib) pak::pkg_install(specs, lib = lib, ask = FALSE),
  args = list(specs = specs, lib = target_lib)
)
```

CRAN availability cache: stored in `.migration-dashboard/cache/available_packages.rds` with 1-hour TTL to avoid repeated `available.packages()` calls.

---

## E. Shiny + bslib UI Layout

**Top-level:** `bslib::page_navbar()` with persistent sidebar + 7 nav panels.

**Sidebar (all tabs):** project path display, current migration target, status badge summary.

**Status badge helper:**
```r
status_badge <- function(label, status) {
  # status: not_run | running | passed | failed | warning | complete
  # Renders as Bootstrap badge with bsicons icon
}
```

**Tab 1 — Project (`mod_project_select`):**
- textInput for project path + Browse button (shinyFiles)
- "Scan Project" button → `detect_project_type()`
- value_box tiles: is_package / has_renv / has_git / has_tests
- DT tables: R files, test files, app files

**Tab 2 — Environment (`mod_environment`):**
- value_box: R version, renv status, # DESCRIPTION deps
- DT: detected R installations (`detect_r_installations()`)
- DT: dependency table (`scan_dependencies()`) with color-coded status column
- "Initialize renv" button (shown if renv absent)

**Tab 3 — Target (`mod_dependency_select`):**
- selectizeInput: choose package from scan_dependencies() output
- textInput: target version
- radioButtons: CRAN / Bioconductor / GitHub / local
- Conditional inputs: GitHub owner/ref, local fileInput
- Live preview of resolved pak spec
- "Confirm Target" button → stores in shared `reactiveVal`

**Tab 4 — Baseline (`mod_diagnostics`, phase = "baseline"):**
- `bslib::input_task_button()` for document / test / check (auto-disables while running)
- callr::r_bg() → handle stored in reactiveVal → invalidateLater(1000) polls is_alive()
- verbatimTextOutput: live log tail (auto-refreshes)
- DT: parsed diagnostics after completion
- Status badge row

**Tab 5 — Migrate (`mod_diagnostics`, phase = "post_migration"):**
- Same diagnostic buttons as Tab 4
- PLUS: confirmation checkbox + "Install Target Package" (danger button)
- Install button disabled until: checkbox checked AND baseline completed
- Pre-install modal: shows what will be installed + renv warning if inactive
- Post-install: reruns document/test/check with same polling mechanism

**Tab 6 — Results (`mod_results`):**
- Full-width value_box: risk level (color: danger=high, warning=medium, success=low)
- Comparison DT: check output (baseline vs post, severity)
- Comparison DT: test results (file, test, baseline_status → post_status)
- Dependency changes table
- Rationale bullet list

**Tab 7 — Report (`mod_report`):**
- Format selector (HTML / Markdown)
- Section checkboxes
- downloadButton → rmarkdown::render() of `inst/report_template.Rmd`
- Output: `.migration-dashboard/reports/<timestamp>_report.html`

---

## F. DESCRIPTION

```
Package: packport
Type: Package
Title: Cross-Platform R Package Migration Workbench
Version: 0.1.0
License: MIT + file LICENSE
Encoding: UTF-8
Roxygen: list(markdown = TRUE)
RoxygenNote: 7.3.2
Config/testthat/edition: 3
Imports:
    processx (>= 3.8.0),
    callr (>= 3.7.0),
    pak (>= 0.7.0),
    jsonlite (>= 1.8.0),
    desc (>= 1.4.0),
    fs (>= 1.6.0),
    cli (>= 3.6.0),
    data.table (>= 1.14.0),
    shiny (>= 1.8.0),
    bslib (>= 0.7.0),
    bsicons (>= 0.1.2),
    DT (>= 0.31),
    renv (>= 1.0.0),
    stringr (>= 1.5.0),
    yaml (>= 2.3.0),
    xml2 (>= 1.3.0),
    rmarkdown (>= 2.26)
Suggests:
    testthat (>= 3.0.0),
    withr (>= 3.0.0),
    mockery (>= 0.4.4),
    devtools (>= 2.4.0),
    shinyFiles (>= 0.9.3),
    BiocManager (>= 1.30.0)
```

**Note:** `devtools` is in Suggests, not Imports — packport constructs the expression string and runs it via `run_r_command()` in a subprocess. The host process never calls devtools functions directly.

---

## G. Edge Cases and Error Handling

| Scenario | Detection | Handling |
|---|---|---|
| Rscript not found | processx throws ENOENT | `cli_abort(class = "packport_rscript_not_found")` |
| Subprocess timeout | `result$timeout == TRUE` | Return NULL with `attr(..., "timed_out")`, emit `cli_warn()` |
| JSON parse failure | `tryCatch(jsonlite::fromJSON(...))` | Save raw stdout, try CSV fallback, throw `"packport_json_parse_error"` |
| jsonlite missing in target R | stderr: "no package called 'jsonlite'" | Fall back to base-R CSV script |
| Library permission error | pak throws "Permission denied" | `cli_warn()` + suggest `R_LIBS_USER`; mark `status = "permission_denied"` |
| Partial install | Any pak failure in batch | `attr(result, "partial") = TRUE`; per-package status in results DT; warn to use renv snapshot for rollback |
| Package incompatible with target R | pak error mentioning R version constraint | `status = "incompatible_r_version"` in results |
| renv not initialized | `fs::file_exists(renv.lock)` fails | `lockfile_version = NA` for all rows; amber badge in UI; offer "Initialize renv" button |
| devtools not installed | `requireNamespace("devtools")` fails | `cli_abort(class = "packport_missing_dependency")` with install instructions |
| Malformed DESCRIPTION | `desc::desc()` throws | `tryCatch()` → `is_package = FALSE`, `has_description = TRUE` |
| DESCRIPTION without Package: field | `desc::desc_get("Package")` returns "" | `is_package = FALSE` |
| Project has both DESCRIPTION and app.R | Both conditions TRUE | `is_package = TRUE` AND `has_shiny = TRUE` (not mutually exclusive) |
| Windows path with spaces | processx path quoting | Always use `command =` arg, never paste into shell string |
| Temp dir with spaces | tempfile() edge case | Use `fs::path_temp()`, validate with a path existence check |

---

## H. Testing Approach

### Shared fixtures (`helper-fixtures.R`)
- `make_toy_project()` — `withr::local_tempdir()` + copy toyMigrationPkg
- `mock_processx_result(stdout, stderr, status, timeout)` — builds a processx-shaped result list
- `fake_rscript_path()` — path to a tiny shell/batch script that echoes canned JSON

### Test files and focus

| File | Strategy | Key scenarios |
|---|---|---|
| `test-detect_r_installations.R` | mockery::stub() processx::run() | Per-platform output parsing; is_current detection; empty results |
| `test-list_packages.R` | Stub processx::run() with canned JSON | Correct columns; timeout → NULL; non-zero exit → error; JSON failure; CSV fallback |
| `test-compare_libraries.R` | In-memory data.tables | Missing/outdated/newer/same classification; base package exclusion; counts sum correctly |
| `test-migrate_packages.R` | Stub list_packages + callr | dry_run returns plan only; packages= filter; partial failure attr |
| `test-detect_project_type.R` | withr::local_tempdir() | Empty dir; valid package; has_shiny + is_package; malformed DESCRIPTION |
| `test-scan_dependencies.R` | Temp dir with hand-crafted DESCRIPTION + renv.lock | Imports/renv.lock rows; both-source packages; missing renv.lock; missing installed package |
| `test-run_r_command.R` | Stub callr::r_bg() with mock proc object | Log dirs created; return list slots; timeout status; file paths correct |
| `test-parse_check_log.R` | Fixture text log files | ERROR/WARNING/NOTE parsed; file:line extraction; zero diagnostics |
| `test-parse_test_log.R` | Fixture text + JUnit XML | All statuses; multi-suite XML; empty log |
| `test-classify_migration_risk.R` | In-memory data.tables | NULL → unknown; new ERROR → high; new WARNING → medium; test regression → high |
| `test-ensure_migration_dir.R` | withr::local_tempdir() | All 5 subdirs created; idempotent; .gitignore written |
| `test-rig.R` | Stub Sys.which() | Not on PATH → empty; "rig list" output parsing; non-zero exit propagates |

**Integration test** (tagged `skip_on_cran()`): Full pipeline on toyMigrationPkg — detect, scan, run test step, parse log, classify risk.

---

## I. Build Order (12 Steps)

```
Step 1:  DESCRIPTION + NAMESPACE stub + .Rbuildignore + utils.R skeleton
         → devtools::check() passes on empty package

Step 2:  ensure_migration_dir() + utils.R internals (path helpers, status_result constructor)
         → test-ensure_migration_dir.R

Step 3:  detect_r_installations() + rig.R
         → test-detect_r_installations.R, test-rig.R
         → manual smoke test: packport::detect_r_installations() on dev machine

Step 4:  list_packages() — subprocess script, JSON/CSV logic, all error classes
         → test-list_packages.R (fully mocked)
         → smoke test: list_packages() against current Rscript

Step 5:  compare_libraries() + detect_install_source()
         → test-compare_libraries.R (in-memory, no mocking needed)

Step 6:  migrate_packages()
         → test-migrate_packages.R
         → R-version migration half of packport is now CLI-functional

Step 7:  detect_project_type() + scan_dependencies()
         → test-detect_project_type.R, test-scan_dependencies.R

Step 8:  run_r_command() + parse_check_log() + parse_test_log() + fixture log files
         → test-run_r_command.R, test-parse_check_log.R, test-parse_test_log.R

Step 9:  classify_migration_risk()
         → test-classify_migration_risk.R
         → Full non-Shiny API now complete. Run devtools::check() — 0 errors.

Step 10: Shiny skeleton: app.R, ui.R, server.R, 6 module stubs
         → launch_app() opens blank Shiny app

Step 11: Fill modules Tab 1 → Tab 7 in dependency order
         (project_select → environment → dependency_select → diagnostics → results → report)
         → Manual walkthrough on toyMigrationPkg

Step 12: Integration test + toyMigrationPkg fixture + vignettes + devtools::check() clean
         → Tag v0.1.0
```

---

## J. Function Dependency Graph

```
utils.R
  └── ensure_migration_dir.R
        └── run_r_command.R
              ├── parse_check_log.R
              ├── parse_test_log.R
              └── classify_migration_risk.R

rig.R ──────────────────────┐
                             ├── detect_r_installations.R
list_packages.R ─────────┐  │
                          ├──┼── compare_libraries.R
detect_install_source.R ─┘  │       └── migrate_packages.R
                             │
detect_project_type.R ───┐  │
                          └──┘
scan_dependencies.R ─────┘

[All R/ functions] ──► inst/app/modules/ ──► launch_app.R
```

---

## K. Critical Files

- `R/list_packages.R` — most technically complex; cross-R JSON protocol that everything else depends on
- `R/run_r_command.R` — defines the structured result shape all Shiny diagnostic tabs consume
- `inst/app/modules/mod_diagnostics.R` — most stateful Shiny module; callr polling + human approval gate
- `DESCRIPTION` — dependency graph; mistakes cascade to every user's install
- `R/detect_install_source.R` — pak spec correctness determines whether migration installs the right thing

---

## L. Verification / Acceptance Criteria

MVP is complete when all of the following pass:

1. `packport::detect_r_installations()` returns at least one row on Windows, macOS, and Linux
2. `packport::list_packages()` returns correct packages when pointed at the current Rscript
3. `packport::compare_libraries(a, b)` correctly classifies known missing/outdated/same packages
4. `packport::migrate_packages(dry_run = TRUE)` returns a plan without installing anything
5. `packport::detect_project_type(toyMigrationPkg)` returns `is_package = TRUE, has_tests = TRUE`
6. `packport::scan_dependencies(toyMigrationPkg)` returns correct Imports rows
7. `devtools::test()` passes all unit tests (fully mocked, no real subprocess calls needed)
8. `packport::launch_app()` opens the Shiny app without error
9. In the UI: select toyMigrationPkg path → Scan → see project type cards populated
10. In the UI: run Baseline Check → log saved to `.migration-dashboard/logs/baseline/`
11. In the UI: confirm + install → install button requires checkbox before enabling
12. In the UI: Results tab shows risk assessment after both baseline and post runs
13. In the UI: Generate Report → HTML file created in `.migration-dashboard/reports/`
14. `devtools::check()` returns 0 errors, 0 warnings

---

## M. Out of Scope (v0.1.0)

Do not build: AI error explanation, automatic code patching, Git diff viewer, PR creation, multi-dependency migration, system dependency detection, Docker isolation, Bioconductor system deps, package NEWS summarization, streaming log output.

Leave architecture open for these by keeping the result shapes extensible (named lists, not positional).
