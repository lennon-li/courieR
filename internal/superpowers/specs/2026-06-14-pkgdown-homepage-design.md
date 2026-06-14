# pkgdown Homepage Redesign — Design Spec

**Date:** 2026-06-14  
**Status:** Approved

## Goal

Make the courieR pkgdown homepage compelling for first-time visitors arriving from CRAN or a Posit Community announcement. Direction: dashboard-forward — lead with the Shiny app in motion, code secondary.

## Approach

Create `pkgdown/index.md` to override the README on the pkgdown site only. The GitHub README stays as-is. This gives us full control over the homepage without splitting maintenance of a shared document.

Also fix stray root `.md` files (IDEAS.md, PLAN.md, etc.) appearing as rendered HTML pages in the pkgdown site by excluding them via `_pkgdown.yml`.

## Content Order

1. **Tagline** — one-sentence value prop + one sentence elaboration
   - "Migrate R packages between R versions — no reinstalling."
   - "courieR detects every R installation on your machine and syncs packages between them — from the console or a point-and-click dashboard."

2. **Install + quickstart snippet** — two code paths, minimal
   ```r
   install.packages("courieR")
   library(courieR)
   hub()               # open dashboard
   migrate("4.5", "4.6")  # one-liner CLI
   ```

3. **`bulk_dispatch.gif`** — full width, shows: select source/target → Compare → Ship workflow

4. **Feature strip** — 3 cards side-by-side
   - 🔍 Auto-detect — finds installs from registry, Homebrew, rig, conda
   - 📦 pak-powered — resolves CRAN, GitHub, Bioconductor from source metadata
   - 🖥 Dashboard + CLI — same engine, two interfaces

5. **Platform footnote** — one line: "Works on Windows · macOS · Linux — no config needed"

## Files Changed

| File | Action |
|------|--------|
| `pkgdown/index.md` | Create — new homepage content |
| `_pkgdown.yml` | Add `exclude` list for stray root .md files; add v0.3.1 to news releases |

## Out of Scope

- Hex sticker (separate effort)
- Custom dispatch GIF on homepage (keep it in the get-started vignette only)
- Posit Community post (separate effort)
- Changes to README.md
