# courieR

**Migrate R packages between R versions — no reinstalling.**

courieR detects every R installation on your machine and syncs packages
between them — from the console or a point-and-click dashboard.

## Install

``` r
install.packages("courieR")
library(courieR)

hub()                      # open the dashboard
migrate("4.5", "4.6")     # one-liner CLI migration
```

## Dashboard

Select a source and target R installation, click **Compare** to see
what’s missing or outdated, then click **Ship**. Progress streams live
in the log pane — no frozen screens.

![Bulk Dispatch: select source/target, compare,
ship](reference/figures/bulk_dispatch.gif)

Bulk Dispatch: select source/target, compare, ship

## How it works

|                       |                                                                                                                                                                                         |
|-----------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 🔍 **Auto-detect**    | Finds R installs from the registry, Homebrew, rig, conda — no paths to configure                                                                                                        |
| 📦 **pak-powered**    | Resolves CRAN, GitHub, and Bioconductor packages from source metadata                                                                                                                   |
| 🖥 **Dashboard + CLI** | [`hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md) for point-and-click, [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md) for scripting — same engine |

Works on **Windows · macOS · Linux**. No packages required on the source
R installation.

## Learn more

- [Get
  Started](https://lennon-li.github.io/courieR/articles/get-started.md)
  — full walkthrough with screenshots
- [Reference](https://lennon-li.github.io/courieR/reference/index.md) —
  all functions
