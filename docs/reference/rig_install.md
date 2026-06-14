# Install R via rig

Install R via rig

## Usage

``` r
rig_install(version, wait = TRUE)
```

## Arguments

- version:

  R version

- wait:

  Logical

## Value

The result of
[`processx::run()`](http://processx.r-lib.org/reference/run.md).

## Examples

``` r
if (interactive() && rig_available()) {
  rig_install("4.5.0", wait = FALSE)
}
```
