# Resolve the primary target library for an R installation

Resolve the primary target library for an R installation

## Usage

``` r
find_target_lib(target_path)
```

## Arguments

- target_path:

  Full path to target `Rscript`.

## Value

Character scalar path to `.libPaths()[1L]` in the target R.
