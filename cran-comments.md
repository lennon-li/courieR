## R CMD check results

0 errors | 0 warnings | 0 notes

Checked locally with `R CMD check --as-cran` under R 4.6.0 on Ubuntu 24.04
(x86_64).

## Changes in 0.3.1

Bug fixes and dashboard UX improvements.

**Bug fixes**

* `.copy_plan()` now appends `<library>/<package>` as the copy source.
  Previously it passed the bare library directory, so each copy cloned the
  entire source library into `target/<pkg>/` — packages appeared delivered
  but could not be loaded. Affects offline/preserve modes and the copy path
  in online mode.

* `find_routes()` probe timeout raised from 3 s to 30 s (default),
  configurable via `options(courier.probe_timeout = )`. R cold-starts on
  Windows machines with OneDrive/Defender active regularly exceed 3 s,
  causing intermittent detection failures. Timed-out probes now warn instead
  of silently dropping the installation.

* Subprocess environment isolation: `find_routes()`, `manifest()`, and the
  pak install subprocess now strip the parent session's `R_LIBS_USER` and
  `R_LIBS_SITE` so each candidate R reports its own library path, not the
  parent's.

* Library scan timeouts are no longer cached as an empty library for the
  rest of the session; they are reported loudly in the log and the timeout
  was raised from 30 s to 5 min for slow machines.

**New features**

* `report_issue()` — opens a pre-filled GitHub issue form in the browser
  with R version, platform, and error message already populated. The
  dashboard error modal gains a matching **Send Report** button.

* Bulk Dispatch now shows a live hero panel during shipping (package count,
  current package, elapsed time, estimate), matching Custom Dispatch.

* Both tables default to showing only packages missing from the target after
  Compare. Custom Dispatch filter chips are now colour-coded to match Bulk
  Dispatch. A **Repo** column is added to the Custom Dispatch table;
  packages with an unknown source are shown in red in both tables.

## Notes to CRAN

* `find_routes()`, `ship()`, and `manifest()` examples are wrapped in
  `\donttest{}` because they probe for multiple R installations on the same
  machine and spawn subprocesses.
* `hub()`, `open_hub()`, and `rig_install()` examples run only
  `if (interactive())`; the latter downloads and installs an R version.
* Tests that spawn subprocesses or install packages are guarded with
  `skip_on_cran()`.
* The package sets no global `options()` or `par()`. The `.onAttach()`
  startup message uses `packageStartupMessage()`.
