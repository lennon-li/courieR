# courieR 0.1.0

* Initial release.
* `find_routes()` detects R installations on Windows, macOS, and Linux,
  including user-local installs.
* `manifest()` scans installed packages from any R installation via subprocess.
* `inventory()` compares two package libraries and reports missing, outdated,
  and newer packages.
* `ship()` migrates packages from one R installation to another using pak.
* `open_hub()` launches a Shiny dashboard for point-and-click migration.
