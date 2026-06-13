# Migrate packages between two R installations in one call

Convenience wrapper around
[`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
and [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md).
Matches installations by version string (e.g. `"4.5.2"`) or full Rscript
path, then runs the migration. Use
[`ship()`](https://lennon-li.github.io/courieR/reference/ship.md)
directly if you need fine-grained control.

## Usage

``` r
migrate(from, to, dry_run = FALSE, upgrade = TRUE, mode = "online", ...)
```

## Arguments

- from:

  Version string or Rscript path of the source installation (packages
  are copied *from* here).

- to:

  Version string or Rscript path of the target installation (packages
  are installed *into* here).

- dry_run:

  If `TRUE`, return the plan without installing anything. Default
  `FALSE`.

- upgrade:

  If `TRUE`, packages already in the target but at an older version are
  upgraded as well. Default `TRUE`.

- mode:

  Transfer mode passed to
  [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md):
  `"online"` (default - reinstall via pak), `"offline"` (file-copy only,
  skip packages without a valid source path), or `"preserve"` (copy for
  exact version, fall back to a pinned pak spec on failure).

- ...:

  Additional arguments passed to
  [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md).

## Value

The same named list returned by
[`ship()`](https://lennon-li.github.io/courieR/reference/ship.md):
`plan`, `results`, `comparison`, `dry_run`, `elapsed_sec`.

## Examples

``` r
if (FALSE) { # \dontrun{
  # dry run first
  migrate("4.5.2", "4.6.0", dry_run = TRUE)

  # for real
  result <- migrate("4.5.2", "4.6.0")
  table(result$results$status)
} # }
```
