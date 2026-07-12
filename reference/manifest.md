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
#>    package version priority repository remotetype remoteusername remoterepo
#>     <char>  <char>   <lgcl>     <lgcl>     <lgcl>         <lgcl>     <lgcl>
#> 1:     pak  0.10.0       NA         NA         NA             NA         NA
#>                            libpath  source
#>                             <char>  <char>
#> 1: /opt/R/4.6.1/lib/R/site-library unknown
# }
```
