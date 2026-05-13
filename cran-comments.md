## Test environments
* local Windows 11, R 4.5.0
* GitHub Actions: ubuntu-latest (release, devel), windows-latest (release, devel), macos-latest (release)

## R CMD check results
0 errors | 0 warnings | 2 notes

* checking for future file timestamps ... NOTE
  unable to verify current time
  (Windows environment issue, not a package problem)

* checking top-level files ... NOTE
  Non-standard file/directory found at top level: 'cran-comments.md'
  (standard for CRAN submissions)

## Reverse dependencies
There are no reverse dependencies.

## Notes to CRAN
This is the first submission of the package (version 0.2.0).

- `find_routes()` and `ship()` examples are wrapped in `\dontrun{}` because they require multiple R installations on the same machine, which is not guaranteed in CRAN check environments.
- `rig_install()` example is `\dontrun{}` because it would download and install an R version.
- `dispatch()` and `open_hub()` examples use `\dontrun{}` because they launch background processes or Shiny applications.
- `rig_list()` and `manifest()` examples use `\donttest{}` because they may rely on external tools (rig) or subprocess calls that are safe but slow.
- `manifest()` runs package scanning in a subprocess. The subprocess script is assembled and written to a temp file which is cleaned via `on.exit()`.
- `ship()` uses `pak::pkg_install()` from the current R session to install into the target library. This is intentional: the source R need not have pak installed. When `dry_run = TRUE`, no installation occurs.
- All subprocess calls have timeouts. All temporary files are cleaned via `on.exit()`.
- The package does not change `options()` or `par()`. No startup messages are emitted at package load.
