# courieR

<!-- badges: start -->
[![R-CMD-check](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/lennon-li/courieR/actions/workflows/pkgdown.yaml/badge.svg)](https://lennon-li.github.io/courieR/)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

courieR syncs installed R packages between R versions on the same machine — migrate from old to new, keep multiple versions in parity, or selectively copy packages in either direction. No manual reinstalling, no lost libraries.

## Installation

Install from GitHub (CRAN submission in progress):

```r
pak::pkg_install("lennon-li/courieR")
```

## Quickstart

```r
library(courieR)
hub()   # launches the Shiny dashboard
```

The dashboard detects all R installations on your machine, displays them in a header bar, and lets you compare and sync packages between any two.

## How It Works

courieR detects every R installation on your system, scans their package libraries, and lets you push packages between them — one-way or bidirectionally — using [pak](https://pak.r-lib.org/) under the hood.

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
| `find_routes()` | Detect all R installations on the system |
| `manifest()` | List packages installed in an R version |
| `inventory()` | Compare two package libraries |
| `ship()` | Copy packages from one R to another (CLI) |

## Dashboard — Sync Tab

The **Sync** tab is the main workflow:

1. The header bar shows all detected installations (highlighted in the A/B accent colours once selected)
2. Select two R installations from the dropdowns in the sidebar
3. Click **Compare** — a summary strip shows counts of identical, missing, and version-mismatched packages
4. Click one of three sync buttons:
   - **Copy A → B** — installs or upgrades packages from A into B
   - **Copy B → A** — installs or upgrades packages from B into A
   - **Two-Way Sync** — brings both installations to parity in both directions

The comparison table lists unmatched and outdated packages first, ahead of packages
that already match. Before a sync starts, the confirmation dialog shows an
approximate time range based on the number of packages. During sync, the dashboard
shows progress details and a log of the direction, package list, completion state,
and any failures. When sync finishes, courieR rescans both selected installations
and refreshes the comparison automatically.

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
