# courieR

<!-- badges: start -->
[![R-CMD-check](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml)
[![CRAN status](https://www.r-pkg.org/badges/version/courieR)](https://CRAN.R-project.org/package=courieR)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

**Migrate R packages between R versions — no reinstalling.**

courieR detects every R installation on your machine and syncs packages between
them — from the console or a point-and-click dashboard.

## Install

```r
install.packages("courieR")
library(courieR)

hub()                      # open the dashboard
migrate("4.5", "4.6")     # one-liner CLI migration
```

## Dashboard

Select a source and target R installation, click **Compare** to see what's
missing or outdated, then click **Ship**. Progress streams live in the log
pane — no frozen screens.

![Bulk Dispatch: select source/target, compare, ship](man/figures/bulk_dispatch.gif)

## How it works

| | |
|---|---|
| 🔍 **Auto-detect** | Finds R installs from the registry, Homebrew, rig, conda — no paths to configure |
| 📦 **pak-powered** | Resolves CRAN, GitHub, and Bioconductor packages from source metadata |
| 🖥 **Dashboard + CLI** | `hub()` for point-and-click, `ship()` for scripting — same engine |

Works on **Windows · macOS · Linux**. No packages required on the source R installation.

## Learn more

- [Get Started](articles/get-started.html) — full walkthrough with screenshots
- [Reference](reference/index.html) — all functions
