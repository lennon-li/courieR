## R CMD check results

0 errors | 0 warnings | 0 notes

Checked locally with `R CMD check --as-cran` under R 4.6.0 on Ubuntu 24.04
(x86_64).

## Changes in 0.3.0

This is an update release. Key changes:

* Dashboard navigation overhauled: three nested tab levels flattened to a
  single row of five top-level tabs, with Source/Target terminology replacing
  the former A/B labels.

* Performance: `ship()` no longer upgrades the entire dependency tree of each
  selected package by default, library scans are reused across transfer
  batches, and pure-R packages are copied directly instead of reinstalled.

* Bug fix: `manifest()` no longer leaks the parent R session's `R_LIBS_USER`
  and `R_HOME` into the target R subprocess. Previously, every probed
  installation reported the parent library, making distinct R versions appear
  to share one library.

* Bug fix: unresolvable local packages are excluded from the pak install
  batch, so they can no longer fail an entire sync.

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
