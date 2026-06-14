# Ship packages between R installations

Compares the package libraries of two R installations and transfers
missing or outdated packages into the target.

## Usage

``` r
ship(
  source_path,
  target_path,
  packages = NULL,
  dry_run = FALSE,
  upgrade = FALSE,
  log_callback = NULL,
  mode = c("online", "offline", "preserve"),
  source_pkgs = NULL,
  target_pkgs = NULL,
  ...
)
```

## Arguments

- source_path:

  Full path to the `Rscript` executable of the source installation (the
  one you are copying packages *from*). Use
  [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  to discover available paths.

- target_path:

  Full path to the `Rscript` executable of the target installation (the
  one you are installing packages *into*). The target R must have `pak`
  installed for `mode = "online"` or pak fallbacks.

- packages:

  Character vector of package names to act on. If `NULL` (the default),
  all packages that are missing from or outdated in the target are
  included.

- dry_run:

  If `TRUE`, build and return the installation plan without installing
  anything. Use this to review what will happen before committing to a
  sync.

- upgrade:

  Passed to
  [`pak::pkg_install()`](https://pak.r-lib.org/reference/pkg_install.html)
  in online mode. The packages in the plan (missing or outdated in the
  target) are always installed at the latest compatible version
  regardless. If `TRUE`, pak additionally upgrades every outdated
  *dependency* of those packages in the target library; if `FALSE` (the
  default), dependencies are only changed when a version requirement
  forces it, which is much faster.

- log_callback:

  Optional function of one argument. When provided, it is called with a
  single character string for each progress message emitted during
  package transfer.

- mode:

  Transfer mode: `"online"` reinstalls via pak (default), `"offline"`
  copies package directories by file and skips packages without a valid
  source path, and `"preserve"` copies first then falls back to a pinned
  pak spec for packages that could not be copied.

- source_pkgs, target_pkgs:

  Optional pre-scanned manifests (as returned by
  [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md))
  for the source and target installations. When supplied, the
  corresponding
  [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
  subprocess scan is skipped, avoiding redundant library scans when the
  caller has already scanned both installations.

- ...:

  Reserved for future arguments.

## Value

A named list with the following elements:

- `plan`:

  `data.table` of planned actions with columns `package`, `action`
  (`"install"` or `"upgrade"`), `mode`, `version.x` (source version),
  `version.y` (target version, `NA` if the package is missing), and
  `pak_spec` (the spec passed to pak).

- `results`:

  `data.table` of per-package outcomes with columns `package`, `status`
  (`"success"`, `"skipped"`, or `"error"`), and `message`.

- `comparison`:

  The raw
  [`inventory()`](https://lennon-li.github.io/courieR/reference/inventory.md)
  comparison table.

- `dry_run`:

  `TRUE` if no packages were installed.

- `elapsed_sec`:

  Total wall-clock time in seconds.

## Safety

`ship()` can install packages into the target R library via
[`pak::pkg_install()`](https://pak.r-lib.org/reference/pkg_install.html)
running in a subprocess, or copy package directories directly for
offline/preserve transfers. Set `dry_run = TRUE` to preview the
migration plan without installing or copying anything. The source R need
not have pak installed. Subprocess calls and file copies are confined to
the target library path and R temporary directory.

## Examples

``` r
# \donttest{
  routes <- find_routes()
  if (nrow(routes) >= 2) {
    result <- ship(
      source_path = routes$rscript_path[1],
      target_path = routes$rscript_path[2],
      dry_run = TRUE
    )
    print(result$plan)
  }
#>          package version.x priority.x repository.x remotetype.x
#>           <char>    <char>     <char>       <char>       <char>
#>  1:       Rsolnp     2.0.1       <NA>         RSPM     standard
#>  2:      TH.data     1.1-5       <NA>         RSPM     standard
#>  3:     classInt    0.4-11       <NA>         RSPM     standard
#>  4:         coin     1.4-3       <NA>         RSPM     standard
#>  5:  credentials     2.0.3       <NA>         RSPM     standard
#>  6:     devtools     2.5.2       <NA>         CRAN         <NA>
#>  7:      downlit     0.4.5       <NA>         RSPM     standard
#>  8:        e1071    1.7-17       <NA>         RSPM     standard
#>  9:     ellipsis     0.3.3       <NA>         RSPM     standard
#> 10:        fansi     1.0.7       <NA>         RSPM     standard
#> 11:         gert     2.3.1       <NA>         RSPM     standard
#> 12:           gh     1.6.0       <NA>         RSPM     standard
#> 13:     gitcreds     0.1.2       <NA>         RSPM     standard
#> 14:        haven     2.5.5       <NA>         CRAN         <NA>
#> 15:         httr     1.4.8       <NA>         RSPM     standard
#> 16:        httr2     1.2.2       <NA>         RSPM     standard
#> 17:     hunspell     3.0.6       <NA>         RSPM     standard
#> 18:      libcoin    1.0-13       <NA>         RSPM     standard
#> 19:       miniUI     0.1.2       <NA>         RSPM     standard
#> 20:        mipfp     3.2.1       <NA>         RSPM     standard
#> 21:   modeltools    0.2-24       <NA>         RSPM     standard
#> 22:     multcomp    1.4-30       <NA>         RSPM     standard
#> 23:      openssl     2.4.2       <NA>         RSPM     standard
#> 24:        party    1.3-20       <NA>         RSPM     standard
#> 25:      pkgdown     2.2.0       <NA>         RSPM     standard
#> 26:       plotly    4.12.0       <NA>         CRAN         <NA>
#> 27:    polspline    1.1.25       <NA>         RSPM     standard
#> 28:      profvis     0.4.0       <NA>         RSPM     standard
#> 29:        proto     1.0.0       <NA>         RSPM     standard
#> 30:        proxy    0.4-29       <NA>         RSPM     standard
#> 31:         ragg     1.5.2       <NA>         RSPM     standard
#> 32: randomForest   4.7-1.2       <NA>         RSPM     standard
#> 33:       ranger    0.18.0       <NA>         RSPM     standard
#> 34:    rcmdcheck     1.4.0       <NA>         CRAN         <NA>
#> 35:        readr     2.2.0       <NA>         CRAN         <NA>
#> 36:       readxl     1.5.0       <NA>         CRAN         <NA>
#> 37:       rmutil    1.1.10       <NA>         RSPM     standard
#> 38:     roxygen2     8.0.0       <NA>         RSPM     standard
#> 39:    rversions     3.0.0       <NA>         RSPM     standard
#> 40:     sandwich     3.1-1       <NA>         RSPM     standard
#> 41:  sessioninfo     1.2.4       <NA>         RSPM     standard
#> 42:     spelling     2.3.2       <NA>         CRAN         <NA>
#> 43:  strucchange     1.5-4       <NA>         RSPM     standard
#> 44:     synthpop     1.9-2       <NA>         RSPM     standard
#> 45:  systemfonts     1.3.2       <NA>         RSPM     standard
#> 46:  textshaping     1.0.5       <NA>         RSPM     standard
#> 47:    truncnorm     1.0-9       <NA>         RSPM     standard
#> 48:   urlchecker     1.0.1       <NA>         RSPM     standard
#> 49:      usethis     3.2.1       <NA>         RSPM     standard
#> 50:        vroom     1.7.1       <NA>         CRAN         <NA>
#> 51:      whisker     0.4.1       <NA>         RSPM     standard
#> 52:         xml2     1.5.2       <NA>         RSPM     standard
#> 53:        xopen     1.0.1       <NA>         RSPM     standard
#> 54:          zip     3.0.0       <NA>         CRAN         <NA>
#> 55:          zoo    1.8-15       <NA>         RSPM     standard
#> 56:         Rcpp 1.1.1-1.1       <NA>         CRAN         <NA>
#> 57:           S7     0.2.2       <NA>         CRAN         <NA>
#> 58:    base64enc     0.1-6       <NA>         RSPM     standard
#> 59:        bit64     4.8.2       <NA>         RSPM     standard
#> 60:        callr     3.8.0       <NA>         CRAN         <NA>
#> 61:          cli     3.6.6       <NA>         CRAN         <NA>
#> 62:        clipr     0.8.1       <NA>         RSPM     standard
#> 63:        cpp11     0.5.5       <NA>         CRAN         <NA>
#> 64:   data.table    1.18.4       <NA>         CRAN         <NA>
#> 65:        dplyr     1.2.1       <NA>         CRAN         <NA>
#> 66:           fs     2.1.0       <NA>         RSPM     standard
#> 67:       future    1.70.0       <NA>         RSPM     standard
#> 68: future.apply    1.20.2       <NA>         RSPM     standard
#> 69:      ggplot2     4.0.3       <NA>         CRAN         <NA>
#> 70:      globals    0.19.1       <NA>         RSPM     standard
#> 71:         glue     1.8.1       <NA>         CRAN         <NA>
#> 72:        highr      0.12       <NA>         RSPM     standard
#> 73:      listenv    0.10.1       <NA>         RSPM     standard
#> 74:     magrittr     2.0.5       <NA>         CRAN         <NA>
#> 75:      mvtnorm     1.4-1       <NA>         RSPM     standard
#> 76:          pak    0.10.0       <NA>         RSPM     standard
#> 77:   parallelly    1.47.0       <NA>         RSPM     standard
#> 78:     processx     3.9.0       <NA>         CRAN         <NA>
#> 79:           ps     1.9.3       <NA>         CRAN         <NA>
#> 80:        purrr     1.2.2       <NA>         CRAN         <NA>
#> 81:        rlang     1.2.0       <NA>         CRAN         <NA>
#> 82:      tinytex      0.59       <NA>         RSPM     standard
#> 83:        vctrs     0.7.3       <NA>         CRAN         <NA>
#> 84:  viridisLite     0.4.3       <NA>         RSPM     standard
#> 85:         xfun      0.58       <NA>         RSPM     standard
#>          package version.x priority.x repository.x remotetype.x
#>           <char>    <char>     <char>       <char>       <char>
#>     remoteusername.x remoterepo.x                                    libpath.x
#>               <lgcl>       <lgcl>                                       <char>
#>  1:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#>  2:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#>  3:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#>  4:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#>  5:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#>  6:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#>  7:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#>  8:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#>  9:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 10:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 11:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 12:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 13:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 14:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 15:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 16:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 17:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 18:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 19:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 20:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 21:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 22:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 23:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 24:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 25:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 26:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 27:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 28:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 29:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 30:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 31:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 32:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 33:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 34:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 35:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 36:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 37:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 38:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 39:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 40:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 41:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 42:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 43:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 44:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 45:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 46:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 47:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 48:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 49:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 50:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 51:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 52:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 53:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 54:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 55:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 56:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 57:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 58:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 59:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 60:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 61:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 62:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 63:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 64:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 65:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 66:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 67:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 68:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 69:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 70:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 71:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 72:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 73:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 74:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 75:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 76:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 77:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 78:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 79:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 80:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 81:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 82:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 83:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 84:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#> 85:               NA           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.4
#>     remoteusername.x remoterepo.x                                    libpath.x
#>               <lgcl>       <lgcl>                                       <char>
#>      source version.y priority.y repository.y remotetype.y remoteusername.y
#>      <char>    <char>     <char>       <char>       <char>           <lgcl>
#>  1: unknown      <NA>       <NA>         <NA>         <NA>               NA
#>  2: unknown      <NA>       <NA>         <NA>         <NA>               NA
#>  3: unknown      <NA>       <NA>         <NA>         <NA>               NA
#>  4: unknown      <NA>       <NA>         <NA>         <NA>               NA
#>  5: unknown      <NA>       <NA>         <NA>         <NA>               NA
#>  6:    CRAN      <NA>       <NA>         <NA>         <NA>               NA
#>  7: unknown      <NA>       <NA>         <NA>         <NA>               NA
#>  8: unknown      <NA>       <NA>         <NA>         <NA>               NA
#>  9: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 10: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 11: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 12: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 13: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 14:    CRAN      <NA>       <NA>         <NA>         <NA>               NA
#> 15: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 16: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 17: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 18: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 19: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 20: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 21: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 22: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 23: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 24: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 25: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 26:    CRAN      <NA>       <NA>         <NA>         <NA>               NA
#> 27: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 28: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 29: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 30: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 31: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 32: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 33: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 34:    CRAN      <NA>       <NA>         <NA>         <NA>               NA
#> 35:    CRAN      <NA>       <NA>         <NA>         <NA>               NA
#> 36:    CRAN      <NA>       <NA>         <NA>         <NA>               NA
#> 37: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 38: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 39: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 40: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 41: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 42:    CRAN      <NA>       <NA>         <NA>         <NA>               NA
#> 43: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 44: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 45: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 46: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 47: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 48: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 49: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 50:    CRAN      <NA>       <NA>         <NA>         <NA>               NA
#> 51: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 52: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 53: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 54:    CRAN      <NA>       <NA>         <NA>         <NA>               NA
#> 55: unknown      <NA>       <NA>         <NA>         <NA>               NA
#> 56:    CRAN     1.1.1       <NA>         CRAN         <NA>               NA
#> 57:    CRAN     0.2.1       <NA>         CRAN         <NA>               NA
#> 58: unknown     0.1-3       <NA>         CRAN         <NA>               NA
#> 59: unknown   4.6.0-1       <NA>         CRAN         <NA>               NA
#> 60:    CRAN     3.7.6       <NA>         CRAN         <NA>               NA
#> 61:    CRAN     3.6.5       <NA>         CRAN         <NA>               NA
#> 62: unknown     0.8.0       <NA>         CRAN         <NA>               NA
#> 63:    CRAN     0.5.3       <NA>         CRAN         <NA>               NA
#> 64:    CRAN    1.18.0       <NA>         CRAN         <NA>               NA
#> 65:    CRAN     1.1.4       <NA>         CRAN         <NA>               NA
#> 66: unknown     1.6.6       <NA>         CRAN         <NA>               NA
#> 67: unknown    1.69.0       <NA>         CRAN         <NA>               NA
#> 68: unknown    1.20.1       <NA>         CRAN         <NA>               NA
#> 69:    CRAN     4.0.1       <NA>         CRAN         <NA>               NA
#> 70: unknown    0.18.0       <NA>         CRAN         <NA>               NA
#> 71:    CRAN     1.8.0       <NA>         CRAN         <NA>               NA
#> 72: unknown      0.11       <NA>         CRAN         <NA>               NA
#> 73: unknown    0.10.0       <NA>         CRAN         <NA>               NA
#> 74:    CRAN     2.0.4       <NA>         CRAN         <NA>               NA
#> 75: unknown     1.3-3       <NA>         CRAN         <NA>               NA
#> 76: unknown     0.9.5       <NA>         <NA>         <NA>               NA
#> 77: unknown    1.46.1       <NA>         CRAN         <NA>               NA
#> 78:    CRAN     3.8.6       <NA>         CRAN         <NA>               NA
#> 79:    CRAN     1.9.1       <NA>         CRAN         <NA>               NA
#> 80:    CRAN     1.2.1       <NA>         CRAN         <NA>               NA
#> 81:    CRAN     1.1.7       <NA>         CRAN         <NA>               NA
#> 82: unknown      0.58       <NA>         CRAN         <NA>               NA
#> 83:    CRAN     0.7.0       <NA>         CRAN         <NA>               NA
#> 84: unknown     0.4.2       <NA>         CRAN         <NA>               NA
#> 85: unknown      0.56       <NA>         CRAN         <NA>               NA
#>      source version.y priority.y repository.y remotetype.y remoteusername.y
#>      <char>    <char>     <char>       <char>       <char>           <lgcl>
#>     remoterepo.y                                    libpath.y target_source
#>           <lgcl>                                       <char>        <char>
#>  1:           NA                                         <NA>          <NA>
#>  2:           NA                                         <NA>          <NA>
#>  3:           NA                                         <NA>          <NA>
#>  4:           NA                                         <NA>          <NA>
#>  5:           NA                                         <NA>          <NA>
#>  6:           NA                                         <NA>          <NA>
#>  7:           NA                                         <NA>          <NA>
#>  8:           NA                                         <NA>          <NA>
#>  9:           NA                                         <NA>          <NA>
#> 10:           NA                                         <NA>          <NA>
#> 11:           NA                                         <NA>          <NA>
#> 12:           NA                                         <NA>          <NA>
#> 13:           NA                                         <NA>          <NA>
#> 14:           NA                                         <NA>          <NA>
#> 15:           NA                                         <NA>          <NA>
#> 16:           NA                                         <NA>          <NA>
#> 17:           NA                                         <NA>          <NA>
#> 18:           NA                                         <NA>          <NA>
#> 19:           NA                                         <NA>          <NA>
#> 20:           NA                                         <NA>          <NA>
#> 21:           NA                                         <NA>          <NA>
#> 22:           NA                                         <NA>          <NA>
#> 23:           NA                                         <NA>          <NA>
#> 24:           NA                                         <NA>          <NA>
#> 25:           NA                                         <NA>          <NA>
#> 26:           NA                                         <NA>          <NA>
#> 27:           NA                                         <NA>          <NA>
#> 28:           NA                                         <NA>          <NA>
#> 29:           NA                                         <NA>          <NA>
#> 30:           NA                                         <NA>          <NA>
#> 31:           NA                                         <NA>          <NA>
#> 32:           NA                                         <NA>          <NA>
#> 33:           NA                                         <NA>          <NA>
#> 34:           NA                                         <NA>          <NA>
#> 35:           NA                                         <NA>          <NA>
#> 36:           NA                                         <NA>          <NA>
#> 37:           NA                                         <NA>          <NA>
#> 38:           NA                                         <NA>          <NA>
#> 39:           NA                                         <NA>          <NA>
#> 40:           NA                                         <NA>          <NA>
#> 41:           NA                                         <NA>          <NA>
#> 42:           NA                                         <NA>          <NA>
#> 43:           NA                                         <NA>          <NA>
#> 44:           NA                                         <NA>          <NA>
#> 45:           NA                                         <NA>          <NA>
#> 46:           NA                                         <NA>          <NA>
#> 47:           NA                                         <NA>          <NA>
#> 48:           NA                                         <NA>          <NA>
#> 49:           NA                                         <NA>          <NA>
#> 50:           NA                                         <NA>          <NA>
#> 51:           NA                                         <NA>          <NA>
#> 52:           NA                                         <NA>          <NA>
#> 53:           NA                                         <NA>          <NA>
#> 54:           NA                                         <NA>          <NA>
#> 55:           NA                                         <NA>          <NA>
#> 56:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 57:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 58:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 59:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 60:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 61:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 62:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 63:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 64:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 65:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 66:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 67:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 68:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 69:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 70:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 71:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 72:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 73:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 74:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 75:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 76:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5       unknown
#> 77:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 78:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 79:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 80:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 81:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 82:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 83:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 84:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#> 85:           NA /home/yeli/R/x86_64-pc-linux-gnu-library/4.5          CRAN
#>     remoterepo.y                                    libpath.y target_source
#>           <lgcl>                                       <char>        <char>
#>       status  action     pak_spec   mode
#>       <char>  <char>       <char> <char>
#>  1:  missing install       Rsolnp online
#>  2:  missing install      TH.data online
#>  3:  missing install     classInt online
#>  4:  missing install         coin online
#>  5:  missing install  credentials online
#>  6:  missing install     devtools online
#>  7:  missing install      downlit online
#>  8:  missing install        e1071 online
#>  9:  missing install     ellipsis online
#> 10:  missing install        fansi online
#> 11:  missing install         gert online
#> 12:  missing install           gh online
#> 13:  missing install     gitcreds online
#> 14:  missing install        haven online
#> 15:  missing install         httr online
#> 16:  missing install        httr2 online
#> 17:  missing install     hunspell online
#> 18:  missing install      libcoin online
#> 19:  missing install       miniUI online
#> 20:  missing install        mipfp online
#> 21:  missing install   modeltools online
#> 22:  missing install     multcomp online
#> 23:  missing install      openssl online
#> 24:  missing install        party online
#> 25:  missing install      pkgdown online
#> 26:  missing install       plotly online
#> 27:  missing install    polspline online
#> 28:  missing install      profvis online
#> 29:  missing install        proto online
#> 30:  missing install        proxy online
#> 31:  missing install         ragg online
#> 32:  missing install randomForest online
#> 33:  missing install       ranger online
#> 34:  missing install    rcmdcheck online
#> 35:  missing install        readr online
#> 36:  missing install       readxl online
#> 37:  missing install       rmutil online
#> 38:  missing install     roxygen2 online
#> 39:  missing install    rversions online
#> 40:  missing install     sandwich online
#> 41:  missing install  sessioninfo online
#> 42:  missing install     spelling online
#> 43:  missing install  strucchange online
#> 44:  missing install     synthpop online
#> 45:  missing install  systemfonts online
#> 46:  missing install  textshaping online
#> 47:  missing install    truncnorm online
#> 48:  missing install   urlchecker online
#> 49:  missing install      usethis online
#> 50:  missing install        vroom online
#> 51:  missing install      whisker online
#> 52:  missing install         xml2 online
#> 53:  missing install        xopen online
#> 54:  missing install          zip online
#> 55:  missing install          zoo online
#> 56: outdated upgrade         Rcpp online
#> 57: outdated upgrade           S7 online
#> 58: outdated upgrade    base64enc online
#> 59: outdated upgrade        bit64 online
#> 60: outdated upgrade        callr online
#> 61: outdated upgrade          cli online
#> 62: outdated upgrade        clipr online
#> 63: outdated upgrade        cpp11 online
#> 64: outdated upgrade   data.table online
#> 65: outdated upgrade        dplyr online
#> 66: outdated upgrade           fs online
#> 67: outdated upgrade       future online
#> 68: outdated upgrade future.apply online
#> 69: outdated upgrade      ggplot2 online
#> 70: outdated upgrade      globals online
#> 71: outdated upgrade         glue online
#> 72: outdated upgrade        highr online
#> 73: outdated upgrade      listenv online
#> 74: outdated upgrade     magrittr online
#> 75: outdated upgrade      mvtnorm online
#> 76: outdated upgrade          pak online
#> 77: outdated upgrade   parallelly online
#> 78: outdated upgrade     processx online
#> 79: outdated upgrade           ps online
#> 80: outdated upgrade        purrr online
#> 81: outdated upgrade        rlang online
#> 82: outdated upgrade      tinytex online
#> 83: outdated upgrade        vctrs online
#> 84: outdated upgrade  viridisLite online
#> 85: outdated upgrade         xfun online
#>       status  action     pak_spec   mode
#>       <char>  <char>       <char> <char>
# }
```
