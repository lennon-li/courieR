# Copy packages by file system

Copies package directories from their source `libpath` into a target
library directory. Packages with no usable source path are skipped;
missing source directories are reported as errors.

## Usage

``` r
copy_packages(plan, target_lib, log_callback = NULL)
```

## Arguments

- plan:

  data.table with columns `package`, `libpath`, `compiled`.

- target_lib:

  Character. Path to the target library root.

- log_callback:

  Function or NULL. Called with a single string per event.

## Value

data.table with columns `package`, `status` (`"success"`, `"skipped"`,
or `"error"`), and `message`.
