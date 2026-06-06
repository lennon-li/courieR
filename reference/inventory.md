# Compare two package libraries

Takes two package manifests (from
[`manifest`](https://lennon-li.github.io/courieR/reference/manifest.md))
and classifies every source package as missing, outdated, newer, or the
same relative to the target.

## Usage

``` r
inventory(source_pkgs, target_pkgs)
```

## Arguments

- source_pkgs:

  `data.table` or `data.frame` from
  [`manifest`](https://lennon-li.github.io/courieR/reference/manifest.md),
  representing the installation you are copying packages *from*.

- target_pkgs:

  `data.table` or `data.frame` from
  [`manifest`](https://lennon-li.github.io/courieR/reference/manifest.md),
  representing the installation you are copying packages *into*.

## Value

A named list with the following elements:

- `missing`:

  Packages in source that are absent from target.

- `outdated`:

  Packages where the source version is newer than the target version.

- `newer`:

  Packages where the target already has a newer version than the source.

- `same`:

  Packages at identical versions in both installations.

- `comparison`:

  Full merged `data.table` of all source packages with a `status` column
  (`"missing"`, `"outdated"`, `"newer"`, or `"same"`).

- `summary`:

  One-row `data.frame` with counts: `missing`, `outdated`, `newer`,
  `same`, `total_source`.

Each data.table includes columns `package`, `version.x` (source
version), `version.y` (target version), and `source`.

## Examples

``` r
src <- data.table::data.table(
  package  = c("dplyr", "ggplot2"),
  version  = c("1.1.4", "3.5.1"),
  priority = NA_character_
)
tgt <- data.table::data.table(
  package = "dplyr",
  version = "1.0.0"
)
inventory(src, tgt)
#> $comparison
#> Key: <package>
#>    package version.x priority.x source version.y priority.y target_source
#>     <char>    <char>     <char> <char>    <char>     <char>        <char>
#> 1:   dplyr     1.1.4       <NA>   <NA>     1.0.0       <NA>          <NA>
#> 2: ggplot2     3.5.1       <NA>   <NA>      <NA>       <NA>          <NA>
#>      status
#>      <char>
#> 1: outdated
#> 2:  missing
#> 
#> $missing
#>    package version.x priority.x source version.y priority.y target_source
#>     <char>    <char>     <char> <char>    <char>     <char>        <char>
#> 1: ggplot2     3.5.1       <NA>   <NA>      <NA>       <NA>          <NA>
#>     status
#>     <char>
#> 1: missing
#> 
#> $outdated
#>    package version.x priority.x source version.y priority.y target_source
#>     <char>    <char>     <char> <char>    <char>     <char>        <char>
#> 1:   dplyr     1.1.4       <NA>   <NA>     1.0.0       <NA>          <NA>
#>      status
#>      <char>
#> 1: outdated
#> 
#> $newer
#> Empty data.table (0 rows and 8 cols): package,version.x,priority.x,source,version.y,priority.y...
#> 
#> $same
#> Empty data.table (0 rows and 8 cols): package,version.x,priority.x,source,version.y,priority.y...
#> 
#> $summary
#>   missing outdated newer same total_source
#> 1       1        1     0    0            2
#> 
```
