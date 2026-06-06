# Ship packages between R installations

Compares the package libraries of two R installations and installs
missing or outdated packages into the target using
[`pak::pkg_install()`](https://pak.r-lib.org/reference/pkg_install.html)
running under the target R executable.

## Usage

``` r
ship(
  source_path,
  target_path,
  packages = NULL,
  dry_run = FALSE,
  upgrade = FALSE,
  log_callback = NULL,
  ...
)
```

## Arguments

- source_path:

  Full path to the `Rscript` executable of the source installation (the
  one you are copying packages *from*). Use
  [`find_routes`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  to discover available paths.

- target_path:

  Full path to the `Rscript` executable of the target installation (the
  one you are installing packages *into*). The target R must have `pak`
  installed.

- packages:

  Character vector of package names to act on. If `NULL` (the default),
  all packages that are missing from or outdated in the target are
  included.

- dry_run:

  If `TRUE`, build and return the installation plan without installing
  anything. Use this to review what will happen before committing to a
  sync.

- upgrade:

  If `TRUE`, packages already present in the target but at an older
  version than the source are upgraded. If `FALSE` (the default), only
  packages missing from the target are installed.

- log_callback:

  Optional function of one argument. When provided, it is called with a
  single character string for each progress message emitted during the
  pak subprocess. Useful for surfacing progress in a UI.

- ...:

  Reserved for future arguments.

## Value

A named list with the following elements:

- `plan`:

  `data.table` of planned actions with columns `package`, `action`
  (`"install"` or `"upgrade"`), `version.x` (source version),
  `version.y` (target version, `NA` if missing), and `pak_spec`.

- `results`:

  `data.table` of per-package outcomes with columns `package`, `status`
  (`"success"` or `"error"`), and `message`.

- `comparison`:

  The raw
  [`inventory`](https://lennon-li.github.io/courieR/reference/inventory.md)
  comparison table.

- `dry_run`:

  `TRUE` if no packages were installed.

- `elapsed_sec`:

  Total wall-clock time in seconds.

## Safety

`ship()` installs packages into the target R library via
[`pak::pkg_install()`](https://pak.r-lib.org/reference/pkg_install.html)
running in a subprocess. Set `dry_run = TRUE` to preview the migration
plan without installing anything. When `dry_run = FALSE` (the default),
pak runs under the target R executable so packages are installed for the
destination R version. The source R need not have pak installed. All
subprocess calls are confined to the target library path; no files are
written outside the target library or the R temporary directory.

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
# }
```
