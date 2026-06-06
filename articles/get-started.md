# Getting Started with courieR

courieR syncs installed R packages between R versions on the same
machine. You can migrate from an old version to a new one, keep two
versions in parity, or selectively push packages in either direction —
all from the R console or from a point-and-click dashboard.

## Installation

Install courieR from GitHub (CRAN submission in progress):

``` r

pak::pkg_install("lennon-li/courieR")
```

All dependencies — including the dashboard packages — are installed
automatically.

## Step 1 — Discover Your R Installations

[`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
scans the system and returns a data frame of every R version it can
find:

``` r

library(courieR)

routes <- find_routes()
routes
#>   version                                          rscript_path is_current
#> 1   4.4.2        C:/Program Files/R/R-4.4.2/bin/x64/Rscript.exe       TRUE
#> 2   4.3.1  C:/Users/you/AppData/Local/Programs/R/R-4.3.1/bin/...      FALSE
#> 3   4.1.3            C:/Users/you/Documents/R/R-4.1.3/bin/...      FALSE
```

`is_current = TRUE` marks the R session you are running right now.

### Platform detection

| Platform | Locations checked |
|----|----|
| Windows | HKLM/HKCU registry, `%ProgramFiles%\R`, `%LOCALAPPDATA%\Programs\R`, `%USERPROFILE%\Documents\R`, rig |
| macOS | `/Library/Frameworks/R.framework`, `~/Library/Frameworks/R.framework`, Homebrew (`/opt/homebrew`, `/usr/local`), rig |
| Linux | `/opt/R` (rig system), `~/.local/share/rig/R` (rig user), conda envs, system `Rscript` on `$PATH` |

To include a non-standard path, pass it explicitly:

``` r

routes <- find_routes(search_paths = "/opt/custom-r/bin/Rscript")
```

------------------------------------------------------------------------

## CLI Workflow

The four core functions form a pipeline:

    find_routes()  →  manifest()  →  inventory()  →  ship()
       discover        scan            compare         migrate

### Step 2 — Scan a library with `manifest()`

[`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
runs a subprocess under a given Rscript and returns every installed
package with its version and source:

``` r

# scan the first (newest) R
src_pkgs <- manifest(rscript_path = routes$rscript_path[1])
head(src_pkgs[, c("package", "version", "source")])
#>     package version source
#> 1     broom   1.0.7   CRAN
#> 2    callr   3.7.6   CRAN
#> 3   courieR   0.2.0 GitHub
#> 4   ggplot2   3.5.1   CRAN
#> 5      glue   1.8.0   CRAN
#> 6   stringr   1.5.1   CRAN
```

Calling
[`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
with no arguments scans the library of the current R session:

``` r

my_pkgs <- manifest()
nrow(my_pkgs)
#> [1] 312
```

Base and recommended packages are excluded automatically — the returned
data contains only user-installed packages.

### Step 3 — Compare two libraries with `inventory()`

[`inventory()`](https://lennon-li.github.io/courieR/reference/inventory.md)
takes two manifests and returns a classified diff:

``` r

src_pkgs <- manifest(rscript_path = routes$rscript_path[2])  # old R
tgt_pkgs <- manifest(rscript_path = routes$rscript_path[1])  # new R

comp <- inventory(src_pkgs, tgt_pkgs)
```

The result is a list with three elements:

``` r

# packages in source but missing from target
nrow(comp$missing)
#> [1] 47

# packages where source has a newer version
nrow(comp$outdated)
#> [1] 12

# packages at the same version in both
nrow(comp$same)
#> [1] 201
```

Inspect what needs to move:

``` r

comp$missing[, c("package", "version", "source")]
#>       package version  source
#>  1:    bookdown   0.39    CRAN
#>  2:  brms   2.21.0    CRAN
#>  3:   officer   0.6.6    CRAN
#>  ...

comp$outdated[, c("package", "version.x", "version.y", "source")]
#>    package version.x version.y source
#> 1:  ggplot2     3.5.1     3.4.4   CRAN
#> 2:   tibble     3.2.1     3.2.0   CRAN
```

### Step 4 — Migrate with `ship()`

[`ship()`](https://lennon-li.github.io/courieR/reference/ship.md) takes
a source and target Rscript path, computes the plan internally, and runs
it:

``` r

result <- ship(
  source_path = routes$rscript_path[2],   # old R — package source
  target_path = routes$rscript_path[1]    # new R — install destination
)
```

#### Always dry-run first

``` r

result <- ship(
  source_path = routes$rscript_path[2],
  target_path = routes$rscript_path[1],
  dry_run = TRUE
)

# review the plan before anything is installed
print(result$plan)
#>         package action  pak_spec
#>  1:    bookdown install bookdown
#>  2:        brms install     brms
#>  3:     ggplot2 upgrade  ggplot2
#>  ...
```

#### Include version upgrades

By default,
[`ship()`](https://lennon-li.github.io/courieR/reference/ship.md) only
installs missing packages. Pass `upgrade = TRUE` to also update packages
that are present but at an older version (mirrors what the Sync tab
does):

``` r

result <- ship(
  source_path = routes$rscript_path[2],
  target_path = routes$rscript_path[1],
  upgrade = TRUE
)
```

#### Check results

``` r

# per-package outcomes
result$results
#>     package  status                       message
#>  1: bookdown success                     Installed
#>  2:     brms success                     Installed
#>  3:    rJava   error  installation of rJava failed...

# count by outcome
table(result$results$status)
#>   error success
#>       1      58

# failed packages only
result$results[result$results$status == "error", ]
```

#### Migrate GitHub and Bioconductor packages

[`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)
detects source-specific packages automatically. CRAN packages are
reinstalled from CRAN; GitHub packages become `"owner/repo"` pak specs;
Bioconductor packages use `"bioc::pkg"` specs. No extra configuration
needed.

``` r

# mixed-source example — all handled automatically
result$plan[, c("package", "source", "pak_spec")]
#>    package   source        pak_spec
#> 1:  ggplot2     CRAN         ggplot2
#> 2:  courieR   GitHub  lennon-li/courieR
#> 3:    DESeq2  Bioconductor  bioc::DESeq2
```

------------------------------------------------------------------------

## Common Recipes

### One-way migration (old R → new R)

``` r

library(courieR)

routes  <- find_routes()
old_r   <- routes$rscript_path[!routes$is_current][1]
new_r   <- routes$rscript_path[routes$is_current]

# dry run
ship(source_path = old_r, target_path = new_r, dry_run = TRUE, upgrade = TRUE)

# for real
result <- ship(source_path = old_r, target_path = new_r, upgrade = TRUE)
result$summary
```

### Two-way sync (keep two R versions in parity)

``` r

r_a <- routes$rscript_path[1]
r_b <- routes$rscript_path[2]

# push everything A has to B
ship(source_path = r_a, target_path = r_b, upgrade = TRUE)

# push everything B has to A
ship(source_path = r_b, target_path = r_a, upgrade = TRUE)
```

### Inspect before migrating

``` r

src  <- manifest(rscript_path = old_r)
tgt  <- manifest(rscript_path = new_r)
comp <- inventory(src, tgt)

# only migrate CRAN packages — skip GitHub/unknown sources
cran_missing <- comp$missing[comp$missing$source == "CRAN", ]
cat(nrow(cran_missing), "CRAN packages to install\n")
```

### Save a manifest to disk

``` r

pkgs <- manifest(rscript_path = routes$rscript_path[1])
write.csv(pkgs[, c("package", "version", "source")], "my_packages.csv", row.names = FALSE)
```

Restore from a saved manifest on a new machine:

``` r

saved <- read.csv("my_packages.csv", stringsAsFactors = FALSE)
# pak installs from a character vector of package names
pak::pkg_install(saved$package)
```

------------------------------------------------------------------------

## Dashboard

[`hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md)
launches a Shiny dashboard that wraps the same pipeline:

``` r

library(courieR)
hub()
```

**Workflow:**

1.  The dashboard scans all R installations on the machine automatically
    — no configuration needed.
2.  Select two installations from the sidebar dropdowns (labelled A and
    B).
3.  Click **Compare** — a summary strip shows counts of identical,
    missing, and version-mismatched packages. The table lists
    differences first.
4.  Click a sync button:
    - **Copy A → B** — installs or upgrades packages from A into B
    - **Copy B → A** — installs or upgrades packages from B into A
    - **Two-Way Sync** — brings both installations to parity in both
      directions
5.  A confirmation dialog shows the package count and an estimated time.
    Confirm to start.
6.  The log pane shows real-time progress: each package, its pak spec,
    success or failure, and a post-sync comparison refresh.

The first sync on a machine can take 1–2 minutes while pak builds its
metadata cache. Subsequent syncs are faster.

The Advanced tab exposes
[`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
output and lets you inspect any detected R installation’s full package
list.

------------------------------------------------------------------------

## Tips

- [`hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md)
  is a short alias for
  [`hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md) —
  both launch the dashboard
- courieR skips base and recommended packages automatically — only
  user-installed packages are compared and migrated
- [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md) uses
  `pak` under the hood, which resolves dependencies automatically
- The source R installation does not need any extra packages; only the
  target R needs `pak` installed, because installation runs under the
  target R process
- GitHub packages require the source repository to be public, or a
  `GITHUB_PAT` to be set in the environment
- If a package fails, check `result$results` — the `message` column has
  the pak error
- Use `dry_run = TRUE` before any large migration to review the plan
  without installing anything
- On Linux without rig,
  [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  may only detect the R on `$PATH`; pass additional paths via
  `search_paths` if needed
