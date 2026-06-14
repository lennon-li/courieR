# List packages installed in a library

Runs a subprocess under the given R executable and returns all
user-installed packages. Base and recommended packages are excluded
automatically.

## Usage

``` r
manifest(
  rscript_path = NULL,
  lib_path = NULL,
  format = c("data.table", "data.frame"),
  timeout_sec = 30L
)
```

## Arguments

- rscript_path:

  Full path to an `Rscript` executable. Defaults to the current R
  session. Use
  [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  to get paths for other installations.

- lib_path:

  Library path to query within the target R. Defaults to the first
  element of [`.libPaths()`](https://rdrr.io/r/base/libPaths.html) in
  that R installation.

- format:

  `"data.table"` (default) or `"data.frame"`.

- timeout_sec:

  Maximum seconds to wait for the subprocess. Increase this on slow
  machines or network-mounted drives. Default `30`.

## Value

A `data.table` (or `data.frame`) with one row per user-installed package
and columns: `package`, `version`, `source` (`"CRAN"`, `"GitHub"`,
`"Bioconductor"`, or `"unknown"`), `remotetype`, `remoteusername`,
`remoterepo`, `libpath`. Base and recommended packages are never
included in the output.

## Examples

``` r
# \donttest{
  pkgs <- manifest()
  head(pkgs)
#>        package  version priority repository remotetype remoteusername
#>         <char>   <char>   <lgcl>     <char>     <lgcl>         <lgcl>
#> 1: AsioHeaders 1.30.2-1       NA       CRAN         NA             NA
#> 2:          BH 1.90.0-1       NA       CRAN         NA             NA
#> 3:          DT   0.34.0       NA       RSPM         NA             NA
#> 4:       Deriv    4.2.0       NA       CRAN         NA             NA
#> 5:     Formula    1.2-5       NA       CRAN         NA             NA
#> 6:       Hmisc    5.2-5       NA       CRAN         NA             NA
#>    remoterepo              libpath  source
#>        <lgcl>               <char>  <char>
#> 1:         NA /home/yeli/R/library    CRAN
#> 2:         NA /home/yeli/R/library    CRAN
#> 3:         NA /home/yeli/R/library unknown
#> 4:         NA /home/yeli/R/library    CRAN
#> 5:         NA /home/yeli/R/library    CRAN
#> 6:         NA /home/yeli/R/library    CRAN
# }
```
