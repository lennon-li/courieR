# courieR

<!-- badges: start -->
[![R-CMD-check](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

courieR migrates your installed R packages from one R version to another on the same machine — no manual reinstalling, no lost libraries.

## Installation

Install from GitHub (CRAN submission pending):

```r
# install.packages("remotes")
remotes::install_github("lennon-li/courieR")
```

## Quickstart

```r
library(courieR)
open_hub()   # launches the Shiny dashboard
```

The dashboard detects all R installations on your machine, lets you pick a source and destination, and delivers your packages in one click.

## How It Works

courieR runs on your **new** R installation. It reaches back to your old R, reads its package library, compares it against the new one, and installs everything that's missing or outdated — using [pak](https://pak.r-lib.org/) under the hood for fast, reliable installs.

```
Old R (source)  -->  courieR scans manifest()
                -->  inventory() finds gaps
                -->  ship() delivers to New R
```

## Key Functions

| Function | What it does |
|---|---|
| `open_hub()` | Launch the Shiny migration dashboard |
| `find_routes()` | Detect all R installations on the system |
| `manifest()` | List packages installed in an R version |
| `inventory()` | Compare two package libraries |
| `ship()` | Migrate packages from one R to another (CLI) |

## CLI Usage

Prefer scripting over the dashboard? Use `ship()` directly:

```r
library(courieR)

routes <- find_routes()
print(routes[, c("version", "rscript_path")])

# dry run first
result <- ship(
  source_path = routes$rscript_path[1],
  target_path = routes$rscript_path[2],
  dry_run = TRUE
)
print(result$plan)

# for real
result <- ship(
  source_path = routes$rscript_path[1],
  target_path = routes$rscript_path[2]
)
```

## Requirements

- R >= 4.1
- Works on Windows, macOS, and Linux
- No packages required on the old (source) R installation
