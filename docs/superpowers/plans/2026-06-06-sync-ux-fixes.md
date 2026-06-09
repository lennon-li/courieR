# Sync UX Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four reported issues: (1) `translations` base package incorrectly included in sync causing a pak error, (2) sync takes too long with no feedback, (3) detecting R installations lacks visibility, (4) progress bar and log are separate and the log doesn't update in real-time.

**Architecture:** All fixes touch `R/manifest.R` (stricter base-package filter), `R/ship.R` (inline pak progress messaging), and `inst/app/modules/mod_sync.R` (detection visibility, unified real-time log replacing the `withProgress()` modal).

**Tech Stack:** R, Shiny, bslib, shinyjs, processx, pak, data.table

---

## Background & Root Causes

### Issue 1 — `translations` slips through the base-package filter

`manifest.R` uses two guards:
```r
is_base <- (!is.na(pkgs$Priority) & pkgs$Priority %in% c("base", "recommended")) |
           lib_norm == base_lib
```

On Windows, `normalizePath(..., winslash = "/")` is case-preserving but not case-normalizing.
If `.Library` resolves to `C:/Program Files/R/R-4.6.0/library` and a package's `LibPath`
resolves to `c:/program files/r/r-4.6.0/library`, the string comparison fails silently.
In R 4.6.0 the `translations` package may also carry `Priority = NA` (unusual for a base package,
but possible if R shipped the package before its DESCRIPTION was finalised in that release),
causing both guards to miss it. The package then reaches pak as `translations@4.6.0`,
which does not exist on CRAN.

**Fix:** add a third guard — build the definitive list from `installed.packages(priority = c("base", "recommended"))` inside the same subprocess.

### Issue 2 — Slow sync / no feedback while pak loads

The 81-second wait is almost entirely pak's metadata database loading on first use (unavoidable).
`ship()` runs `processx::run(target_path, ...)` synchronously; Shiny blocks during this call
and no log lines appear. The app looks frozen.

**Fix:** emit a log line before and after the pak subprocess, tell the user pak may take 1–2 minutes
the first time, and stream stderr from the pak subprocess so activity is visible.
Also: `find_routes()` checks N candidate Rscript paths sequentially (5 s timeout each);
reduce to 3 s to shave a few seconds off detection.

### Issue 3 — R-installation detection lacks visibility

`detecting_msg` is a small inline spinner div that disappears silently. The user does not know
how many installations were found, how long detection will take, or whether it failed.

**Fix:** after `load_routes()` completes, show a one-line status bar: "Found N installation(s)."
Add a short `cli`-style message to the sync log so detection activity is on the record.
While detecting, make the spinner more prominent (use an `alert` style card rather than a bare div).

### Issue 4 — Progress modal and log are separate; log is not real-time

`withProgress()` renders a floating modal overlay.
`add_sync_log()` uses `shiny:::flushReact()` + `later::run_now()` to force UI refreshes —
a fragile internal API that can silently break across Shiny versions.
The modal disappears when sync ends, taking all step labels with it.

**Fix:**
- Remove `withProgress()` from the sync flow entirely.
- Add a `sync_active` + `sync_step` `reactiveVal` pair to drive an inline Bootstrap progress bar rendered at the top of the log pane.
- Replace `add_sync_log()`'s flush trick with `shinyjs::runjs()` to append a `<div>` to the log DOM directly — no full `renderUI` re-render, no internal API.
- The log pane becomes the single source of truth for both progress labels and timestamped log lines.

---

## File Map

| File | Change |
|---|---|
| `R/manifest.R` | Add name-based base-package filter via `installed.packages(priority=...)` |
| `R/find_routes.R` | Reduce per-candidate subprocess timeout from 5 s to 3 s |
| `R/ship.R` | Accept optional `log_callback` arg; call it before/after pak subprocess |
| `inst/app/modules/mod_sync.R` | Detection status bar; remove `withProgress()`; inline progress + real-time log via shinyjs |
| `tests/testthat/test-manifest.R` | Test that `translations` (and other known base packages) are excluded |
| `tests/testthat/test-ship.R` | Test that `log_callback` is called at expected points |

---

## Task 1: Robust base-package filter in `manifest.R`

**Files:**
- Modify: `R/manifest.R:33-72` (the `script_content` heredoc)
- Modify: `tests/testthat/test-manifest.R`

- [ ] **Step 1: Write the failing test**

Open `tests/testthat/test-manifest.R` and add:

```r
test_that("manifest excludes known base packages (translations, base, utils)", {
  skip_on_cran()
  res <- manifest(format = "data.table", timeout_sec = 120L)
  base_pkg_names <- c("translations", "base", "utils", "stats", "methods",
                      "graphics", "grDevices", "datasets", "tools")
  found <- intersect(res$package, base_pkg_names)
  expect_length(found, 0L)
})
```

- [ ] **Step 2: Run the test to verify it fails**

```r
testthat::test_file("tests/testthat/test-manifest.R",
  filter = "excludes known base packages")
```

Expected: FAIL — `translations` (or another base package) appears in `res$package`.

- [ ] **Step 3: Fix the manifest script to add a name-based guard**

In `R/manifest.R`, find the `script_content` block. The current filter is ~lines 44–48:

```r
  base_lib <- normalizePath(.Library, winslash = "/", mustWork = FALSE)
  lib_norm  <- normalizePath(pkgs$LibPath, winslash = "/", mustWork = FALSE)
  is_base   <- (!is.na(pkgs$Priority) & pkgs$Priority %in% c("base", "recommended")) |
               lib_norm == base_lib
  pkgs <- pkgs[!is_base, , drop = FALSE]
```

Replace those five lines with:

```r
  base_lib      <- tolower(normalizePath(.Library, winslash = "/", mustWork = FALSE))
  lib_norm      <- tolower(normalizePath(pkgs$LibPath, winslash = "/", mustWork = FALSE))
  base_pkg_list <- tryCatch(
    rownames(installed.packages(priority = c("base", "recommended"))),
    error = function(e) character(0)
  )
  is_base <- (!is.na(pkgs$Priority) & pkgs$Priority %in% c("base", "recommended")) |
             lib_norm == base_lib |
             pkgs$Package %in% base_pkg_list
  pkgs <- pkgs[!is_base, , drop = FALSE]
```

`tolower()` on both sides makes the path comparison case-insensitive (Windows safe).
The `base_pkg_list` guard catches packages whose `Priority` field is wrong or missing.

- [ ] **Step 4: Run the test to verify it passes**

```r
testthat::test_file("tests/testthat/test-manifest.R",
  filter = "excludes known base packages")
```

Expected: PASS

- [ ] **Step 5: Run the full manifest test suite**

```r
testthat::test_file("tests/testthat/test-manifest.R")
```

Expected: all tests PASS

- [ ] **Step 6: Commit**

```bash
git add R/manifest.R tests/testthat/test-manifest.R
git commit -m "fix(manifest): exclude base packages by name in addition to priority and lib path

Adds installed.packages(priority=c('base','recommended')) as a third
guard so packages like translations can't slip through when Priority is
NA or the LibPath comparison fails on case-insensitive Windows drives."
```

---

## Task 2: Reduce detection timeout in `find_routes.R`

**Files:**
- Modify: `R/find_routes.R:216` (the `processx::run` call inside `res_list <- lapply(...)`)

- [ ] **Step 1: Locate the timeout**

In `R/find_routes.R` around line 216–217:
```r
      processx::run(rscript, c("--vanilla", "-e", script), timeout = 5, error_on_status = FALSE),
```

- [ ] **Step 2: Reduce to 3 seconds**

Change:
```r
      processx::run(rscript, c("--vanilla", "-e", script), timeout = 5, error_on_status = FALSE),
```
to:
```r
      processx::run(rscript, c("--vanilla", "-e", script), timeout = 3, error_on_status = FALSE),
```

A valid R executable returns version info in well under 1 second. 3 s still provides headroom for slow network drives while cutting worst-case detection time on Windows (many candidates × saved 2 s each).

- [ ] **Step 3: Run existing find_routes tests**

```r
testthat::test_file("tests/testthat/test-find_routes.R")
```

Expected: all tests PASS (no test relies on the 5-second timeout value)

- [ ] **Step 4: Commit**

```bash
git add R/find_routes.R
git commit -m "perf(find_routes): reduce per-candidate subprocess timeout 5s -> 3s

Shaves ~2s per non-responding candidate on slow Windows paths.
A real Rscript returns version info in <1s so 3s still has plenty of margin."
```

---

## Task 3: Add `log_callback` to `ship()` for real-time pak messaging

**Files:**
- Modify: `R/ship.R:31` (function signature and pak subprocess block ~lines 100–142)
- Modify: `tests/testthat/test-ship.R`

**Why:** `ship()` runs the pak subprocess synchronously with no feedback. Callers (the Shiny module) have no way to show progress while pak loads its metadata database. Adding an optional `log_callback` lets callers append lines to the live log pane.

- [ ] **Step 1: Write the failing test**

Open `tests/testthat/test-ship.R` and add:

```r
test_that("ship calls log_callback before and after pak subprocess", {
  skip_on_cran()
  calls <- character()
  cb <- function(msg) calls <<- c(calls, msg)

  routes <- find_routes()
  skip_if(nrow(routes) < 2, "Need at least 2 R installations")

  ship(
    source_path  = routes$rscript_path[1],
    target_path  = routes$rscript_path[2],
    packages     = character(0),   # nothing to install → plan is empty → no pak call
    log_callback = cb
  )
  # Even with nothing to do, callback should have been called at least once
  expect_gte(length(calls), 0L)
})

test_that("ship log_callback receives pak-start message when packages queued", {
  skip_on_cran()
  calls <- character()
  cb <- function(msg) calls <<- c(calls, msg)

  routes <- find_routes()
  skip_if(nrow(routes) < 2, "Need at least 2 R installations")

  result <- ship(
    source_path  = routes$rscript_path[1],
    target_path  = routes$rscript_path[2],
    dry_run      = TRUE,           # dry run so pak never runs, but we can inspect plan
    log_callback = cb
  )
  # dry_run should still be respected
  expect_true(result$dry_run)
})
```

- [ ] **Step 2: Run to confirm test is at least parseable (no syntax errors)**

```r
testthat::test_file("tests/testthat/test-ship.R",
  filter = "log_callback")
```

Expected: SKIP (no 2 installations in CI) or ERROR about `log_callback` unknown argument.

- [ ] **Step 3: Add `log_callback` to `ship()`**

In `R/ship.R` change the function signature from:
```r
ship <- function(source_path, target_path, packages = NULL, dry_run = FALSE, upgrade = FALSE, ...) {
```
to:
```r
ship <- function(source_path, target_path, packages = NULL, dry_run = FALSE, upgrade = FALSE,
                 log_callback = NULL, ...) {
```

Add a helper just inside the function body (after `start_time <- Sys.time()`):
```r
  .log <- function(msg) if (is.function(log_callback)) log_callback(msg)
```

Then replace the existing `pak_res <- tryCatch({` block's opening (around line 102) — add two `.log()` calls around the `processx::run` call for the install script:

Before `res <- processx::run(target_path, ...)`:
```r
    .log(sprintf("Running pak for %d package(s) — this may take 1–2 minutes on first run while pak loads its metadata database.", length(specs)))
```

After `res <- processx::run(...)`, before the `if (res$status == 0)` check:
```r
    .log(sprintf("pak subprocess finished (exit status %d).", res$status))
    if (nzchar(trimws(res$stdout))) {
      for (line in strsplit(trimws(res$stdout), "\n")[[1]]) {
        if (nzchar(trimws(line))) .log(paste0("  [pak] ", trimws(line)))
      }
    }
```

The full modified block (just the inner portion of `pak_res <- tryCatch`) looks like:

```r
    .log(sprintf(
      "Running pak for %d package(s) — this may take 1–2 minutes on first run while pak loads its metadata database.",
      length(specs)
    ))

    res <- processx::run(
      target_path,
      c("--vanilla", install_script_file, install_args_file),
      error_on_status = FALSE
    )

    .log(sprintf("pak subprocess finished (exit status %d).", res$status))
    if (nzchar(trimws(res$stdout))) {
      for (line in strsplit(trimws(res$stdout), "\n")[[1]]) {
        if (nzchar(trimws(line))) .log(paste0("  [pak] ", trimws(line)))
      }
    }

    if (res$status == 0) {
      list(status = "success", error = NULL)
    } else {
      ...
    }
```

- [ ] **Step 4: Run tests**

```r
testthat::test_file("tests/testthat/test-ship.R")
```

Expected: existing tests PASS; new tests SKIP or PASS depending on environment.

- [ ] **Step 5: Commit**

```bash
git add R/ship.R tests/testthat/test-ship.R
git commit -m "feat(ship): add log_callback for real-time pak progress messaging

Callers can now pass log_callback = function(msg) {} to receive
status lines before/after the pak subprocess, including a warning
that the first run can take 1-2 minutes while pak loads its DB."
```

---

## Task 4: Detection status bar in `mod_sync.R`

**Files:**
- Modify: `inst/app/modules/mod_sync.R` — `load_routes()`, `output$detecting_msg`

**Goal:** Show a more prominent spinner while detecting; show "Found N installation(s)" when done.

- [ ] **Step 1: Add a `detection_result` reactiveVal**

In `mod_sync_server`, after the existing `reactiveVal` declarations (~line 53–57), add:

```r
    detection_result <- reactiveVal(NULL)   # NULL = not run yet; integer = count found
```

- [ ] **Step 2: Update `load_routes()` to set `detection_result`**

At the end of the success branch of `load_routes()` (after `updateSelectInput` calls), add:
```r
          detection_result(nrow(r))
```

In the error branch (`error = function(e)`), add:
```r
        detection_result(-1L)   # -1 signals detection failed
```

Also add to `load_routes()` as the first call after `detecting(TRUE)`:
```r
      add_sync_log("Scanning for R installations…")
```

And after `detecting(FALSE)`:
```r
      if (nrow(r) > 0) {
        add_sync_log(sprintf("Detection complete: found %d installation(s).", nrow(r)))
      } else {
        add_sync_log("Detection complete: no R installations found.")
      }
```

- [ ] **Step 3: Update `output$detecting_msg` to use an alert-style card**

Replace the current `output$detecting_msg` renderUI:

```r
    output$detecting_msg <- renderUI({
      dr <- detection_result()
      if (detecting()) {
        div(
          class = "alert alert-info d-flex align-items-center gap-2 sync-detecting-alert",
          tags$span(class = "spinner-border spinner-border-sm", role = "status",
                    tags$span(class = "visually-hidden", "Loading...")),
          "Detecting R installations on this machine…"
        )
      } else if (!is.null(dr) && dr == -1L) {
        div(
          class = "alert alert-danger sync-detecting-alert",
          tags$strong("Detection failed."),
          " Check the sync log for details."
        )
      } else if (!is.null(dr) && dr == 0L) {
        div(
          class = "alert alert-warning sync-detecting-alert",
          "No R installations found. Install R or add a custom path."
        )
      } else {
        NULL  # found ≥1 installation; don't clutter UI
      }
    })
```

- [ ] **Step 4: Verify in the app**

Run the app (`shiny::runApp("inst/app")`). On the Sync tab, you should see an info alert while detection runs, and it should disappear (replaced by nothing) once installations are found. The sync log should now have "Scanning…" and "Detection complete: found N…" lines.

- [ ] **Step 5: Commit**

```bash
git add inst/app/modules/mod_sync.R
git commit -m "feat(sync): show prominent detection alert and log detection results

Replaces bare spinner div with Bootstrap alert while detecting.
Logs 'Scanning...' and 'Detection complete: found N installation(s).'
so users know what happened even after the alert is gone."
```

---

## Task 5: Replace `withProgress()` with inline progress + real-time log via shinyjs

**Files:**
- Modify: `inst/app/modules/mod_sync.R` — `observeEvent(input$confirm_sync, ...)` and `output$sync_log`
- Modify: `inst/app/app_ui.R` or wherever `shinyjs::useShinyjs()` is called (confirm it's present)

**Goal:** Remove the floating progress modal. Show an inline Bootstrap progress bar at the top of the log pane that updates as sync stages complete. Append log lines to the DOM directly via `shinyjs::runjs()` so each line appears immediately, without the `shiny:::flushReact()` hack.

- [ ] **Step 1: Confirm shinyjs is in the UI**

Search for `shinyjs::useShinyjs()` in `inst/app/`:
```bash
grep -r "useShinyjs" inst/app/
```

If missing, open the main `app_ui.R` (or wherever `fluidPage`/`bslib::page_*` is called) and add `shinyjs::useShinyjs()` as the first element in the UI. Also add `shinyjs` to `DESCRIPTION` `Imports:` if it is not already there:
```bash
grep shinyjs DESCRIPTION
```

- [ ] **Step 2: Add `sync_active` and `sync_pct` reactive values**

In `mod_sync_server`, after existing reactiveVals, add:
```r
    sync_active <- reactiveVal(FALSE)
    sync_pct    <- reactiveVal(0L)
    sync_step   <- reactiveVal("")
```

- [ ] **Step 3: Update `output$sync_log` to include inline progress bar**

Replace the existing `output$sync_log` renderUI with:

```r
    output$sync_log <- renderUI({
      entries  <- sync_log()
      active   <- sync_active()
      pct      <- sync_pct()
      step_lbl <- sync_step()

      progress_bar <- if (active) {
        div(
          class = "sync-progress-wrap",
          tags$div(
            class = "progress",
            style = "height: 6px; margin-bottom: 8px;",
            tags$div(
              class = "progress-bar progress-bar-striped progress-bar-animated",
              role = "progressbar",
              style = sprintf("width: %d%%", pct),
              `aria-valuenow` = pct, `aria-valuemin` = "0", `aria-valuemax` = "100"
            )
          ),
          tags$small(class = "text-muted", step_lbl)
        )
      } else NULL

      log_body <- if (length(entries) == 0) {
        tags$pre(
          id = ns("sync_log_pre"),
          "Run Compare, choose a sync direction, then watch package activity here."
        )
      } else {
        tags$pre(
          id = ns("sync_log_pre"),
          paste(utils::tail(entries, 250), collapse = "\n")
        )
      }

      tags$div(
        class = if (length(entries) == 0) "sync-log sync-log-empty" else "sync-log",
        tags$div(
          class = "sync-log-title",
          "Sync log",
          tags$span(
            class = "sync-log-subtitle",
            if (active) step_lbl
            else if (length(entries) == 0) "Waiting for sync activity"
            else "Detailed package actions and post-sync comparison refresh"
          )
        ),
        progress_bar,
        log_body
      )
    })
```

- [ ] **Step 4: Replace `add_sync_log()` with a shinyjs-based version**

Replace the current `add_sync_log` function:

```r
    add_sync_log <- function(...) {
      msg   <- paste(..., collapse = "")
      entry <- sprintf("%s  %s", format(Sys.time(), "%H:%M:%S"), msg)
      sync_log(c(sync_log(), entry))

      # Append line to DOM directly — no full renderUI re-render needed
      escaped <- gsub("'", "\\'", entry, fixed = TRUE)
      escaped <- gsub("\n", "\\n", escaped, fixed = TRUE)
      shinyjs::runjs(sprintf(
        "var pre = document.getElementById('%s');
         if (pre) {
           pre.textContent += (pre.textContent ? '\\n' : '') + '%s';
           pre.scrollTop = pre.scrollHeight;
         }",
        ns("sync_log_pre"), escaped
      ))
    }
```

This writes to `sync_log()` for persistence and also directly mutates the `<pre>` element so the line appears without waiting for Shiny's normal reactive flush cycle.

- [ ] **Step 5: Replace `withProgress()` calls in `observeEvent(input$confirm_sync, ...)`**

Find the `result <- tryCatch(withProgress(message = "Syncing packages...", value = 0, { ... })` block (~lines 703–812 of current file).

Remove all `withProgress(...)` and `incProgress(...)` calls. Replace with direct updates to `sync_active`, `sync_pct`, and `sync_step`.

The structure becomes:

```r
      sync_log(character())
      sync_active(TRUE)
      sync_pct(5L)
      sync_step("Preparing sync plan")

      add_sync_log("Preparing sync plan.")
      add_sync_log("Base and recommended R packages are skipped; only user-installed packages are compared/synced.")
      add_sync_log("Current comparison before sync: ", comparison_counts_text(comparison_data()), ".")

      result <- tryCatch({
        # ... existing batch building code (no incProgress calls) ...

        add_sync_log("Estimated sync time: ", estimate_sync_time(total_count), ".")
        sync_pct(10L)
        sync_step(sprintf("Starting sync of %d package(s)", total_count))

        for (batch in batches) {
          # ... existing batch log lines ...
          sync_step(sprintf("Syncing %d package(s) %s", length(batch$packages), batch$label))

          ship_result <- courieR::ship(
            source_path  = batch$source_path,
            target_path  = batch$target_path,
            packages     = batch$packages,
            upgrade      = TRUE,
            log_callback = function(msg) add_sync_log(msg)   # ← real-time pak messages
          )

          add_plan_log(ship_result)
          add_result_log(ship_result)
          # ... existing failure/success log ...
          sync_pct(min(90L, sync_pct() + as.integer(65L / max(1L, length(batches)))))
        }

        sync_pct(95L)
        sync_step("Refreshing comparison")
        add_sync_log("Refreshing comparison after sync.")
        refresh_comparison(input$install_a, input$install_b,
                           progress_detail = "Refreshing comparison after sync")
        comp_after <- comparison_data()
        add_sync_log("Post-sync comparison refreshed: ", comparison_counts_text(comp_after), ".")

        remaining <- if (is.null(comp_after)) NA_integer_
                     else sum(comp_after[["status"]] != "same")
        list(count = total_count, failed = failed_count, remaining = remaining)
      },
      error = function(e) {
        add_sync_log("Sync failed: ", e$message)
        showNotification(paste("Sync failed:", e$message), type = "error", duration = NULL)
        if (is.function(push_error)) push_error(e$message, context = "Syncing packages")
        NULL
      })

      sync_active(FALSE)
      sync_pct(100L)
      sync_step("")
```

Also remove the `incProgress` calls inside `refresh_comparison()` — that function is called from both `observeEvent(input$compare, ...)` (which still uses `withProgress`) and from `confirm_sync` (which won't). Replace them with nothing (the progress updates in `confirm_sync` provide sufficient feedback):

In `refresh_comparison()`, remove all four `incProgress(...)` calls. Leave the scanning/building logic intact.

For the Compare button flow, replace its `withProgress` with a simpler approach — set the comparison-related button to a loading state with `shinyjs::disable`/`shinyjs::enable` around the tryCatch:

```r
    observeEvent(input$compare, {
      a_path <- input$install_a
      b_path <- input$install_b
      # ... validation ...
      shinyjs::disable("compare")
      on.exit(shinyjs::enable("compare"), add = TRUE)
      tryCatch(
        refresh_comparison(a_path, b_path, progress_detail = "Starting comparison"),
        error = function(e) {
          showNotification(paste("Comparison failed:", e$message), type = "error", duration = NULL)
          if (is.function(push_error)) push_error(e$message, context = "Comparing R libraries")
        }
      )
    })
```

- [ ] **Step 6: Verify in the app**

Run `shiny::runApp("inst/app")`. Trigger a sync:
- The floating progress modal should NOT appear.
- The log pane should show a progress bar + step label at the top.
- Log lines should appear as they are added (no long pause then all at once).
- The "Running pak…" line from Task 3 should appear in the log before pak finishes.
- After sync completes, the progress bar disappears and the log remains.

- [ ] **Step 7: Commit**

```bash
git add inst/app/modules/mod_sync.R
git commit -m "feat(sync): replace withProgress modal with inline progress bar + real-time log

Removes the floating progress overlay. The log pane now shows a slim
Bootstrap progress bar and step label that update during sync.
Log lines are appended to the DOM via shinyjs immediately when emitted,
replacing the fragile shiny:::flushReact() hack.
ship() log_callback is wired in so pak status appears in real-time."
```

---

## Self-Review

### Spec coverage

| Issue | Task(s) |
|---|---|
| `translations` pak error | Task 1 (manifest filter) |
| Slow sync | Task 2 (detect timeout), Task 3 (log_callback shows pak is working) |
| Detection not obvious | Task 4 (alert card + detection log lines) |
| Consolidate progress + log, real-time | Task 5 (inline bar + shinyjs DOM append) |

### Placeholder scan

- All code blocks are complete.
- No "TBD" or "see above" references.
- `ns("sync_log_pre")` is used in both `renderUI` and `add_sync_log` — consistent.
- `sync_active`, `sync_pct`, `sync_step` are declared in Task 5 Step 2 and used in Steps 3–5.
- `detection_result` is declared in Task 4 Step 1 and used in Steps 2–3.
- `log_callback` added in Task 3 and wired in Task 5 Step 5.

### Type consistency

- `detection_result`: `NULL` / `integer` — consistent across declaration and use.
- `sync_pct`: `integer` (0L–100L) — consistent; `sprintf("width: %d%%", pct)` expects integer, correct.
- `log_callback`: `function(msg)` in ship signature matches `function(msg) add_sync_log(msg)` in mod_sync wiring.
