# Launch the courieR dashboard

Opens the Shiny dashboard in your browser. The dashboard detects all R
installations on the machine and lets you compare and sync packages
between any two of them without writing any code.

## Usage

``` r
open_hub(project_path = NULL, port = NULL, launch.browser = TRUE)

hub(project_path = NULL, port = NULL, launch.browser = TRUE)
```

## Arguments

- project_path:

  Reserved; currently unused.

- port:

  Port to run the Shiny app on. `NULL` picks a random available port.

- launch.browser:

  Whether to open the system browser automatically. Default `TRUE`.

## Value

Called for its side effect of launching a Shiny application.

## Details

`hub()` is a short alias for `open_hub()`.

## Examples

``` r
if (interactive()) {
  hub()        # short form
  open_hub()   # same thing
}
```
