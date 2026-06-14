# Report a bug or error to the courieR issue tracker

Opens a pre-filled GitHub issue form in your browser with your R
version, platform, and (optionally) an error message already populated.
Use this when you encounter a problem outside of the dashboard, or when
you want to file a feature request.

## Usage

``` r
report_issue(message = NULL, context = NULL)
```

## Arguments

- message:

  Character. A short description of the problem. If `NULL`, a generic
  template is used.

- context:

  Character. Additional context about where the error occurred (e.g.
  `"ship() with mode = 'offline'"`). Optional.

## Value

Called for its side effect (opens browser). Returns the issue URL
invisibly.

## Examples

``` r
if (interactive()) {
  report_issue("ship() fails with 'library not found'")
}
```
