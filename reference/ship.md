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
# }
```
