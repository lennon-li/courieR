# Package index

## Dashboard

Launch the interactive Shiny dashboard.

- [`open_hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md)
  [`hub()`](https://lennon-li.github.io/courieR/reference/open_hub.md) :
  Launch the courieR dashboard

## Core workflow

The CLI pipeline: discover → scan → compare → migrate. Use
[`migrate()`](https://lennon-li.github.io/courieR/reference/migrate.md)
for the one-call path or
[`ship()`](https://lennon-li.github.io/courieR/reference/ship.md) for
full control.

- [`migrate()`](https://lennon-li.github.io/courieR/reference/migrate.md)
  : Migrate packages between two R installations in one call
- [`find_routes()`](https://lennon-li.github.io/courieR/reference/find_routes.md)
  : Detect R installations on the system
- [`manifest()`](https://lennon-li.github.io/courieR/reference/manifest.md)
  : List packages installed in a library
- [`inventory()`](https://lennon-li.github.io/courieR/reference/inventory.md)
  : Compare two package libraries
- [`ship()`](https://lennon-li.github.io/courieR/reference/ship.md) :
  Ship packages between R installations

## Utilities

Lower-level helpers used internally or for advanced scripting.

- [`wrap()`](https://lennon-li.github.io/courieR/reference/wrap.md) :
  Generate a pak specification for a package
- [`rig_available()`](https://lennon-li.github.io/courieR/reference/rig_available.md)
  : Check if rig is available
- [`rig_install()`](https://lennon-li.github.io/courieR/reference/rig_install.md)
  : Install R via rig
- [`rig_list()`](https://lennon-li.github.io/courieR/reference/rig_list.md)
  : List rig installations

## Internal

Not intended for direct use.

- [`courieR`](https://lennon-li.github.io/courieR/reference/courieR-package.md)
  [`courieR-package`](https://lennon-li.github.io/courieR/reference/courieR-package.md)
  : courieR: Migrate Installed R Packages Between R Versions
- [`dispatch()`](https://lennon-li.github.io/courieR/reference/dispatch.md)
  : Run an R command in the background and log output
- [`inspect_shipment()`](https://lennon-li.github.io/courieR/reference/inspect_shipment.md)
  : Detect project characteristics
- [`open_depot()`](https://lennon-li.github.io/courieR/reference/open_depot.md)
  : Ensure the courier depot directory structure exists
- [`parse_dispatch_log()`](https://lennon-li.github.io/courieR/reference/parse_dispatch_log.md)
  : Parse test log
- [`parse_inspection_log()`](https://lennon-li.github.io/courieR/reference/parse_inspection_log.md)
  : Parse R CMD check log
- [`rate_shipment()`](https://lennon-li.github.io/courieR/reference/rate_shipment.md)
  : Classify shipment risk based on check and test results
- [`take_inventory()`](https://lennon-li.github.io/courieR/reference/take_inventory.md)
  : Scan project dependencies
