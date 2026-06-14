# Generate a pak specification for a package

Generate a pak specification for a package

## Usage

``` r
wrap(package, version = NULL, source_hint = NULL, github_ref = NULL)
```

## Arguments

- package:

  Package name

- version:

  Optional version constraint or exact version

- source_hint:

  Optional hint: "CRAN", "Bioconductor", "GitHub", "local"

- github_ref:

  Optional GitHub ref like "owner/repo@ref"

## Value

A character vector of pak specs

## Examples

``` r
wrap("dplyr")
#> [1] "dplyr"
wrap("dplyr", version = "1.1.4")
#> [1] "dplyr@1.1.4"
wrap("mypackage", source_hint = "Bioconductor")
#> [1] "bioc::mypackage"
wrap("r-lib/rlang", source_hint = "GitHub", github_ref = "r-lib/rlang")
#> [1] "r-lib/rlang"
```
