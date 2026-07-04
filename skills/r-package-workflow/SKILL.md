---
name: r-package-workflow
description: General R package development workflow for repositories under /home/james/dev, including CRAN-style packages with testthat, roxygen2, pkgdown, Air, lintr, Rcpp, GitHub Actions, and local plans or handoff files. Use whenever Codex is asked to edit, review, clean up, test, document, release-check, or otherwise work inside an R package repository.
---

# R Package Workflow

Use this as the default operating procedure for R package work.

## First Pass

1. Inspect the worktree before editing: `git --no-optional-locks status --short`.
2. Read package context before assuming structure: `DESCRIPTION`, `NAMESPACE`,
   relevant `R/`, `src/`, `tests/testthat/`, `NEWS.md`, `README.md`, and any
   active plan or handoff under `plans/`.
3. Do not revert unrelated user changes. If touched files already contain user
   edits, work with them.
4. Keep behavioral fixes, generated documentation, and broad formatting in
   separate phases unless the user explicitly asks for one combined sweep.

## Change Discipline

- Prefer existing repo patterns over new abstractions.
- Before finalizing new exported functions or metrics, check that public names
  are literal, discoverable, and defensible without private project backstory.
  Reserve niche terminology for documentation when a clearer API name exists.
- Prefer exported API tests over private-helper tests. If an internal test
  remains, document the safety or user-visible behavior it protects.
- Treat these as generated unless intentionally refreshed:
  `R/RcppExports.R`, `src/RcppExports.cpp`, `NAMESPACE`, `man/*.Rd`,
  pkgdown output under `docs/`.
- Use `apply_patch` for manual edits. Use package tools for generated output.
- After `usethis` modifies infrastructure, re-harden generated files rather
  than accepting templates as final.

## Checks

Choose checks based on blast radius. See [checks.md](references/checks.md) for
the command matrix and warning attribution workflow.

Common commands:

```sh
Rscript -e 'testthat::test_local()'
Rscript -e 'Rcpp::compileAttributes()'
Rscript -e 'roxygen2::roxygenise()'
Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"))'
air format . --check
Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'
actionlint
zizmor .github/workflows  # or uvx zizmor .github/workflows when not installed
```

Scripts:

- `scripts/check-r-package.sh`: run a local check bundle.
- `scripts/audit-generated-r-files.sh`: list likely generated files touched in
  the current diff.

For sparse `Matrix` slot-level implementation work, use the idioms in
[sparse-matrix.md](references/sparse-matrix.md).

## Cross-Repo Norms

For James's R repos, use the patterns captured in
[repo-patterns.md](references/repo-patterns.md). Relevant reference repos often
include `uwot`, `RcppHNSW`, `rnndescent`, `flotsam`, `snedata`, and `vizier`.

If the task touches a narrower area, also apply the focused skill when
available:

- GitHub Actions, pkgdown deploy, coverage, Dependabot: `$r-ci-hardening`.
- Tests and fixtures: `$r-test-hygiene`.
- README, NEWS, roxygen, articles, pkgdown: `$r-docs-pkgdown`.
- Rcpp, compiled code, `src/`, `Makevars`: `$r-rcpp-package`.
- Performance benchmarks, phased optimization, before/after evidence:
  `$r-performance-workflow`.
