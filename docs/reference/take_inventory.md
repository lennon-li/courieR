# Scan project dependencies

Scan project dependencies

## Usage

``` r
take_inventory(project_path)
```

## Arguments

- project_path:

  Path to the project

## Value

A data.table

## Examples

``` r
# \donttest{
  take_inventory(tempdir())
#> Empty data.table (0 rows and 7 cols): package,source,constraint,installed_version,lockfile_version,target_version...
# }
```
