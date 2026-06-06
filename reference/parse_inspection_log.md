# Parse R CMD check log

Parse R CMD check log

## Usage

``` r
parse_inspection_log(log_path)
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
  "* checking examples ... WARNING",
  "  An example result is marked with \\donttest."
), tmp)
parse_inspection_log(tmp)
#>    severity                                        message   file   line
#>      <char>                                         <char> <char> <char>
#> 1:  WARNING   An example result is marked with \\donttest.              
#>                                                                          raw_block
#>                                                                             <char>
#> 1: * checking examples ... WARNING\n  An example result is marked with \\donttest.
file.remove(tmp)
#> [1] TRUE
```
