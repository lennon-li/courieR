# pkgdown Homepage Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the default README-based pkgdown homepage with a dashboard-forward landing page that leads with the Bulk Dispatch GIF, a clear tagline, install snippet, and feature strip.

**Architecture:** Create `pkgdown/index.md` (pkgdown-only override of README) and `man/figures/` (standard pkgdown image dir). Move stray root .md files to `internal/` so pkgdown doesn't render them as pages. Update `_pkgdown.yml` with v0.3.1 news entry. No changes to README.md or any R source.

**Tech Stack:** pkgdown 2.x, R Markdown (plain Markdown in index.md), `_pkgdown.yml` YAML

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `pkgdown/index.md` | Create | Homepage content (overrides README on pkgdown site) |
| `man/figures/bulk_dispatch.gif` | Create (copy) | Standard pkgdown image location for homepage |
| `_pkgdown.yml` | Modify | Add v0.3.1 news release entry |
| `IDEAS.md` → `internal/IDEAS.md` | Move | Remove stray root .md from pkgdown output |
| `PLAN.md` → `internal/PLAN.md` | Move | Remove stray root .md from pkgdown output |
| `implementation.md` → `internal/implementation.md` | Move | Remove stray root .md from pkgdown output |
| `.Rbuildignore` | Modify | Exclude new paths added to root/internal |

---

### Task 1: Move stray root .md files out of pkgdown's reach

pkgdown renders all `.md` files it finds in the package root. `IDEAS.md`, `PLAN.md`, and `implementation.md` are dev-only files that should not appear as pages on the site.

**Files:**
- Move: `IDEAS.md` → `internal/IDEAS.md`
- Move: `PLAN.md` → `internal/PLAN.md`
- Move: `implementation.md` → `internal/implementation.md`
- Modify: `.Rbuildignore`

- [ ] **Step 1: Move the files**

```bash
mv /home/yeli/repos/courieR/IDEAS.md /home/yeli/repos/courieR/internal/
mv /home/yeli/repos/courieR/PLAN.md /home/yeli/repos/courieR/internal/
mv /home/yeli/repos/courieR/implementation.md /home/yeli/repos/courieR/internal/
```

- [ ] **Step 2: Verify .Rbuildignore already excludes these**

```bash
grep -E "PLAN|implementation|IDEAS" /home/yeli/repos/courieR/.Rbuildignore
```

Expected output includes lines for `^PLAN\.md$`, `^implementation\.md$`, `^IDEAS\.md$`. If any are missing, add them. The `^internal$` line added earlier covers the internal/ directory.

- [ ] **Step 3: Commit**

```bash
git -C /home/yeli/repos/courieR add -A
git -C /home/yeli/repos/courieR commit -m "chore: move dev-only .md files out of pkgdown root"
```

---

### Task 2: Set up man/figures/ with the Bulk Dispatch GIF

`man/figures/` is the standard pkgdown directory for images referenced from the homepage. pkgdown copies it to `reference/figures/` in the built site, and paths like `man/figures/foo.gif` resolve correctly from `pkgdown/index.md`.

**Files:**
- Create: `man/figures/bulk_dispatch.gif` (copy from `vignettes/figures/`)

- [ ] **Step 1: Create man/figures/ and copy the GIF**

```bash
mkdir -p /home/yeli/repos/courieR/man/figures
cp /home/yeli/repos/courieR/vignettes/figures/bulk_dispatch.gif \
   /home/yeli/repos/courieR/man/figures/bulk_dispatch.gif
```

- [ ] **Step 2: Verify the file copied correctly**

```bash
ls -lh /home/yeli/repos/courieR/man/figures/
```

Expected: `bulk_dispatch.gif` present with non-zero size.

- [ ] **Step 3: Commit**

```bash
git -C /home/yeli/repos/courieR add man/figures/bulk_dispatch.gif
git -C /home/yeli/repos/courieR commit -m "chore: add bulk_dispatch.gif to man/figures for pkgdown homepage"
```

---

### Task 3: Create pkgdown/index.md — the new homepage

`pkgdown/index.md` overrides `README.md` as the pkgdown homepage source. GitHub still shows README.md unchanged. The content follows the approved layout: tagline → install snippet → GIF → feature strip → platform footnote.

**Files:**
- Create: `pkgdown/index.md`

- [ ] **Step 1: Create the pkgdown/ directory and write index.md**

Create `/home/yeli/repos/courieR/pkgdown/index.md` with this exact content:

```markdown
# courieR

<!-- badges: start -->
[![R-CMD-check](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/lennon-li/courieR/actions/workflows/R-CMD-check.yaml)
[![CRAN status](https://www.r-pkg.org/badges/version/courieR)](https://CRAN.R-project.org/package=courieR)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

**Migrate R packages between R versions — no reinstalling.**

courieR detects every R installation on your machine and syncs packages between
them — from the console or a point-and-click dashboard.

## Install

```r
install.packages("courieR")
library(courieR)

hub()                      # open the dashboard
migrate("4.5", "4.6")     # one-liner CLI migration
```

## Dashboard

Select a source and target R installation, click **Compare** to see what's
missing or outdated, then click **Ship**. Progress streams live in the log
pane — no frozen screens.

![Bulk Dispatch: select source/target, compare, ship](man/figures/bulk_dispatch.gif)

## How it works

| | |
|---|---|
| 🔍 **Auto-detect** | Finds R installs from the registry, Homebrew, rig, conda — no paths to configure |
| 📦 **pak-powered** | Resolves CRAN, GitHub, and Bioconductor packages from source metadata |
| 🖥 **Dashboard + CLI** | `hub()` for point-and-click, `ship()` for scripting — same engine |

Works on **Windows · macOS · Linux**. No packages required on the source R installation.

## Learn more

- [Get Started](articles/get-started.html) — full walkthrough with screenshots
- [Reference](reference/index.html) — all functions
```

- [ ] **Step 2: Verify the file was written**

```bash
head -5 /home/yeli/repos/courieR/pkgdown/index.md
```

Expected: starts with `# courieR`.

- [ ] **Step 3: Commit**

```bash
git -C /home/yeli/repos/courieR add pkgdown/index.md
git -C /home/yeli/repos/courieR commit -m "feat: add dashboard-forward pkgdown homepage (pkgdown/index.md)"
```

---

### Task 4: Update _pkgdown.yml — news entry for v0.3.1

The news section currently only lists v0.2.3. Add v0.3.1.

**Files:**
- Modify: `_pkgdown.yml`

- [ ] **Step 1: Add v0.3.1 to the releases list**

In `_pkgdown.yml`, find:

```yaml
news:
  releases:
  - text: "0.2.3"
    href: https://github.com/lennon-li/courieR/releases/tag/v0.2.3
```

Replace with:

```yaml
news:
  releases:
  - text: "0.3.1"
    href: https://github.com/lennon-li/courieR/releases/tag/v0.3.1
  - text: "0.2.3"
    href: https://github.com/lennon-li/courieR/releases/tag/v0.2.3
```

- [ ] **Step 2: Commit**

```bash
git -C /home/yeli/repos/courieR add _pkgdown.yml
git -C /home/yeli/repos/courieR commit -m "chore: add v0.3.1 to pkgdown news releases"
```

---

### Task 5: Build and verify the site

- [ ] **Step 1: Run pkgdown build**

```r
/usr/bin/R -e "pkgdown::build_site()"
```

Expected: ends with `── Finished building pkgdown site for package courieR ──` and no ERRORs or WARNINGs. The "Checking for problems" step should be silent.

- [ ] **Step 2: Confirm stray files are gone**

```bash
ls /home/yeli/repos/courieR/docs/ | grep -E "^(IDEAS|PLAN|implementation)"
```

Expected: no output (those files should not appear in the built site).

- [ ] **Step 3: Confirm homepage has the GIF**

```bash
grep "bulk_dispatch" /home/yeli/repos/courieR/docs/index.html
```

Expected: a line containing `bulk_dispatch.gif` confirming the image is referenced in the rendered homepage.

- [ ] **Step 4: Commit the built site**

```bash
git -C /home/yeli/repos/courieR add docs/
git -C /home/yeli/repos/courieR commit -m "chore: rebuild pkgdown site with dashboard-forward homepage"
```
