# Classify shipment risk based on check and test results

Classify shipment risk based on check and test results

## Usage

``` r
rate_shipment(baseline_results, post_results)
```

## Arguments

- baseline_results:

  data.table from baseline check

- post_results:

  data.table from post-shipment check

## Value

A list

## Examples

``` r
baseline <- data.table::data.table(
  severity = character(), message = character(),
  file = character(), line = character()
)
post <- data.table::data.table(
  severity = "ERROR", message = "undefined symbol",
  file = "R/foo.R", line = "10"
)
rate_shipment(baseline, post)
#> $risk
#> [1] "high"
#> 
#> $new_errors
#> [1] 1
#> 
#> $new_warnings
#> [1] 0
#> 
#> $new_notes
#> [1] 0
#> 
#> $reason
#> [1] "1 new error(s), 0 new warning(s)"
#> 
```
