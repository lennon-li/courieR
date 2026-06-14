# Detect R installations on the system

Scans the current machine for every R installation it can find, across
multiple sources per platform, and returns a tidy data frame of results.

## Usage

``` r
find_routes(search_paths = NULL)
```

## Arguments

- search_paths:

  An optional character vector of additional paths to search. Each
  element may be a directory containing `bin/Rscript` (or
  `bin/x64/Rscript.exe` on Windows), or a direct path to an `Rscript`
  executable.

## Value

A data frame with one row per unique R installation and the following
columns:

- version:

  Character. R version string, e.g. `"4.4.1"`.

- rscript_path:

  Character. Absolute path to the `Rscript` executable.

- home:

  Character. The installation directory
  ([`R.home()`](https://rdrr.io/r/base/Rhome.html)), i.e. where this R
  is installed. Normalized lexically for comparison.

- library:

  Character. The installation's primary library location
  (`.libPaths()[1]` under a vanilla session) - where
  [`install.packages()`](https://rdrr.io/r/utils/install.packages.html)
  writes by default. This is the effective package store; two installs
  that share a `library` hold the same packages. Normalized lexically
  for comparison. `NA` if it could not be determined.

- is_current:

  Logical. `TRUE` for the R session running courieR.

## Details

Detection sources by platform:

**Windows**

- HKLM registry (`SOFTWARE\R-core\R`) - standard admin installs via the
  CRAN Windows installer.

- HKCU registry (`SOFTWARE\R-core\R`) - non-admin installs that register
  under the current user hive only.

- `%ProgramFiles%\R` - directory scan for admin installs not in the
  registry.

- `%LOCALAPPDATA%\Programs\R` - rig-managed and other user-local
  installs.

- `%USERPROFILE%\Documents\R` - installs placed in the user's Documents
  folder.

- rig (`rig list`) - any additional versions managed by rig that were
  not found by path scanning.

**macOS**

- `/Library/Frameworks/R.framework/Versions` - system-wide CRAN
  installer.

- `~/Library/Frameworks/R.framework/Versions` - user-local framework
  installs (no admin required).

- Homebrew: `/opt/homebrew/opt/r` (Apple Silicon) and `/usr/local/opt/r`
  (Intel).

- rig (`rig list`) - rig-managed versions.

**Linux**

- `/opt/R` - rig system-wide installs.

- `~/.local/share/rig/R` - rig user-local installs.

- conda environments (active `$CONDA_PREFIX`).

- System `Rscript` on `$PATH`.

Symlinks are resolved via
[`fs::path_real()`](https://fs.r-lib.org/reference/path_math.html) so
that duplicate entries from different detection sources pointing to the
same executable are collapsed.

Each candidate is probed in a short subprocess. The probe timeout
defaults to 30 seconds and can be adjusted via
`options(courier.probe_timeout = )`; installations whose probe times out
are skipped with a warning rather than silently dropped.

## Examples

``` r
# \donttest{
routes <- find_routes()
routes[, c("version", "rscript_path", "is_current")]
#>   version             rscript_path is_current
#> 1   4.4.3 /opt/R/4.4.3/bin/Rscript      FALSE
#> 2   4.5.2 /opt/R/4.5.2/bin/Rscript      FALSE
#> 3   4.5.3 /opt/R/4.5.3/bin/Rscript      FALSE
#> 4   4.6.0   /usr/lib/R/bin/Rscript       TRUE

# include a non-standard install
routes <- find_routes(search_paths = "/opt/custom-r/bin/Rscript")
# }
```
