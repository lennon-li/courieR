# Detect project characteristics

Detect project characteristics

## Usage

``` r
inspect_shipment(project_path)
```

## Arguments

- project_path:

  Path to the project

## Value

A named list

## Examples

``` r
# \donttest{
  res <- inspect_shipment(tempdir())
  res$is_package
#> [1] FALSE
# }
```
