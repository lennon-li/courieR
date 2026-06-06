# Run an R command in the background and log output

Run an R command in the background and log output

## Usage

``` r
dispatch(
  project_path,
  expr,
  phase,
  label,
  rscript_path = NULL,
  timeout_sec = 600L
)
```

## Arguments

- project_path:

  Path to the project

- expr:

  Expression to run (as a quoted expression or function)

- phase:

  Character: "baseline" or "post_migration"

- label:

  Character: "document", "test", or "check"

- rscript_path:

  Optional path to Rscript

- timeout_sec:

  Timeout in seconds

## Value

A list with process info

## Examples

``` r
# \donttest{
  tmp <- tempdir()
  job <- dispatch(tmp, "message('hello')", "baseline", "document")
  Sys.sleep(1)
  job$process$is_alive()
#> [1] FALSE
# }
```
