# Introducing courieR: sync R packages between R versions without the reinstall pain

Every R user eventually faces the same problem: you install a new R version, and now
you have to figure out which packages to reinstall and how. If you maintain multiple
R versions in parallel — for project reproducibility, CRAN testing, or just keeping
a stable version alongside the latest — this happens constantly.

**courieR** automates it.

## What it does

courieR detects every R installation on your machine and lets you copy packages
from a source installation into a target installation — from the R console or a
point-and-click dashboard.

```r
pak::pkg_install("lennon-li/courieR")

library(courieR)
hub()   # opens the dashboard
```

That's the whole install. No configuration, no setup files.

## The dashboard

`hub()` opens a Shiny dashboard in your browser. Pick a **source** and a **target**
R installation from the dropdowns (the target is constrained to the same-or-newer R
version), click **Compare**, and you get a table showing which packages are
missing, outdated, or already in sync. Then click **Ship**:

- **Ship** — push the source's packages into the target, installing or upgrading as needed
- To mirror two same-version installs, run the transfer again with source and target swapped

The log pane shows real-time progress as each package is installed — including what
pak is doing — so you never stare at a frozen screen wondering if something went wrong.

## The CLI

Prefer scripting? The same pipeline works from the console:

```r
routes <- find_routes()

result <- ship(
  source_path = routes$rscript_path[2],   # old R
  target_path = routes$rscript_path[1],   # new R
  dry_run = TRUE,
  upgrade = TRUE
)
print(result$plan)

result <- ship(
  source_path = routes$rscript_path[2],
  target_path = routes$rscript_path[1],
  upgrade = TRUE
)
table(result$results$status)
```

## How it works

courieR uses pak under the hood. It detects each package's origin — CRAN, GitHub,
Bioconductor — and builds the right pak spec automatically. No configuration needed;
it reads the metadata from the source library.

The target R's pak runs in a subprocess under the target R executable, so packages
are built for the right R version. The source R needs nothing extra installed.

## Platform support

| Platform | Detection sources |
|---|---|
| **Windows** | HKLM/HKCU registry, Program Files, AppData, Documents, rig |
| **macOS** | System framework, user framework, Homebrew, rig |
| **Linux** | /opt/R, ~/.local/share/rig/R, conda, system PATH |

## Get it

```r
pak::pkg_install("lennon-li/courieR")
```

CRAN submission in progress. GitHub: https://github.com/lennon-li/courieR
Docs: https://lennon-li.github.io/courieR/

Feedback welcome — especially if detection misses an R installation on your setup.
