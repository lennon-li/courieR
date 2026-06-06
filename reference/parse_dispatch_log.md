# Parse test log

Parse test log

## Usage

``` r
parse_dispatch_log(log_path)
```

## Arguments

- log_path:

  Path to the log file

## Value

data.table

## Examples

``` r
tmp <- tempfile(fileext = ".log")
writeLines(c(
  "-- Failure (test-foo.R:1): addition works ----",
  "Expected 3, got 4."
), tmp)
parse_dispatch_log(tmp)
#>          file           test  status            message
#>        <char>         <char>  <char>             <char>
#> 1: test-foo.R addition works failure Expected 3, got 4.
file.remove(tmp)
#> [1] TRUE
```
