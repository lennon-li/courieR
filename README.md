# courieR

<!-- badges: start -->
[![R-CMD-check](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/lennon-li/courieR/actions/workflows/pkgdown.yaml/badge.svg)](https://lennon-li.github.io/courieR/)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
![AI-implemented](https://img.shields.io/badge/AI--implemented-Claude%20Code-7C3AED)
<!-- badges: end -->

courieR syncs installed R packages between R versions on the same machine — migrate from old to new, or selectively copy packages from a source installation into a target installation. No manual reinstalling, no lost libraries.

> This package is fully AI-implemented — designed, coded, and documented by
> [Claude Code](https://claude.ai/code) — with the author directing
> requirements, reviewing every decision, and owning the outcome. A
> proof-of-concept for human–AI co-authorship in open-source R.

## Installation

Install from CRAN:

```r
install.packages("courieR")
```

Or install the development version from GitHub:

```r
pak::pkg_install("lennon-li/courieR")
```

## Quickstart

```r
library(courieR)
hub()                          # point-and-click dashboard

migrate("4.5.2", "4.6.0")     # one-line CLI migration
```

The dashboard detects all R installations on your machine, displays them in a header bar, and lets you compare and sync packages between any two.

## How It Works

courieR detects every R installation on your system, scans their package libraries, and lets you push packages from a source installation into a target installation — using [pak](https://pak.r-lib.org/) under the hood.

```
R 4.4.1  ──▶  compare()  ──▶  missing / outdated packages found
                          ──▶  ship() installs or upgrades into target R
```

### Installation Detection

`find_routes()` searches multiple sources per platform so it finds installs regardless of whether admin rights were used:

| Platform | Sources searched |
|---|---|
| **Windows** | HKLM registry (admin installs), HKCU registry (non-admin installs), `%ProgramFiles%\R`, `%LOCALAPPDATA%\Programs\R`, `%USERPROFILE%\Documents\R`, rig-managed versions |
| **macOS** | System R framework (`/Library/Frameworks`), user framework (`~/Library/Frameworks`), Homebrew (`/opt/homebrew`, `/usr/local`), rig-managed versions |
| **Linux** | `/opt/R` (rig system), `~/.local/share/rig/R` (rig user), conda environments, custom paths |

## Key Functions

| Function | What it does |
|---|---|
| `hub()` | Launch the Shiny dashboard |
| `migrate(from, to)` | One-call CLI migration between two R versions |
| `find_routes()` | Detect all R installations on the system |
| `manifest()` | List packages installed in an R version |
| `inventory()` | Compare two package libraries |
| `ship()` | Full-control migration (custom paths, callbacks) |

## Dashboard — Bulk Dispatch

The dashboard has five flat tabs — **Bulk Dispatch**, **Browse**, **Custom
Dispatch**, **Manifest**, and **Maintenance**. **Bulk Dispatch** is the main
workflow:

1. The header bar shows all detected installations (highlighted in the source/target accent colours once selected)
2. Select a **source** and a **target** R installation from the dropdowns in the sidebar. The target list is constrained to the same-or-newer R version than the source, since an older R can't reliably hold packages built for a newer one.
3. Click **Compare** — a summary strip shows counts of identical, missing, and version-mismatched packages
4. Click **Ship** — installs or upgrades the source's packages into the target. To mirror two same-version installs, run the transfer again with source and target swapped.

The comparison table lists unmatched and outdated packages first, ahead of packages
that already match. Before a sync starts, the confirmation dialog shows an
approximate time range based on the number of packages. During sync, the dashboard
shows progress details and a log of the package list, completion state,
and any failures. When sync finishes, courieR rescans both selected installations
and refreshes the comparison automatically.

The remaining tabs cover narrower workflows: **Browse** inspects any single
detected installation's package list, **Custom Dispatch** lets you cherry-pick
individual packages to ship (with a side-by-side **Source**/**Target** table and
its own log panel), **Manifest** reports an installation's full inventory, and
**Maintenance** restocks an installation from CRAN.

## CLI Usage

Prefer scripting? Use `ship()` directly:

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

# for real (upgrade = TRUE ensures outdated packages are also updated)
result <- ship(
  source_path = routes$rscript_path[1],
  target_path = routes$rscript_path[2],
  upgrade = TRUE
)
```

## Requirements

- R >= 4.1
- Works on Windows, macOS, and Linux
- No packages required on the source R installation
- The target R installation needs `pak` available so it can install packages into
  its own library
