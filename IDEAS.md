# Ideas

## Package governance and policy-aware migration

Extend `courieR` beyond R-version package migration into a lightweight package-library governance tool.

Core positioning:

> `courieR` helps R teams migrate and rebuild package libraries safely by inventorying installed packages, comparing them against an organizational policy, and generating reproducible, reviewable migration plans.

This should not be framed as a full replacement for Posit Package Manager. A better niche is local package inventory, audit, policy checking, and governed migration.

Possible features:

- Scan installed package libraries and record package name, version, source, repository, license, library path, dependencies, compilation status, and R build version.
- Generate a package inventory report for security, IT, or CIO review.
- Support a simple policy file, for example YAML or JSON, defining allowed repositories, blocked packages, approved versions, license rules, and review-required packages.
- Compare an existing R library against an approved package list or policy file.
- Flag packages from GitHub, local source installs, unknown repositories, risky licenses, compiled code, or unapproved sources.
- Create a governed migration plan that only migrates packages allowed by policy.
- Support a dry-run mode that explains what will be installed, skipped, blocked, or upgraded before making changes.
- Export audit reports as HTML, JSON, CSV, or XLSX.
- Integrate with `renv.lock`, `pak`, and optionally Posit Package Manager repositories as package sources.

Possible future functions:

```r
scan_library()
audit_library()
check_policy()
migration_plan()
migrate_approved()
security_report()
```

Important boundary:

`courieR` should not claim to detect malware, guarantee package safety, or prevent all data leakage. The realistic role is to make package state visible, compare it against human-defined policy, and make migrations reproducible and reviewable.
