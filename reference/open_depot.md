# Ensure the courier depot directory structure exists

Creates `.courier-depot/` and its subdirectories in the project path.
Writes a `.gitignore` to prevent tracking of logs and artifacts.

## Usage

``` r
open_depot(project_path)
```

## Arguments

- project_path:

  Path to the R project

## Value

Invisibly returns the path to the `.courier-depot` directory.

## Examples

``` r
# \donttest{
  depot <- open_depot(tempdir())
# }
```
