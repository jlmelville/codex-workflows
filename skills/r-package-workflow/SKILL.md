---
name: r-package-workflow
description: General R package development workflow, especially James's repos using testthat, roxygen2, pkgdown, Air, lintr, Rcpp, GitHub Actions, or local plans. Use whenever Codex edits, reviews, cleans up, tests, documents, release-checks, or otherwise works inside an R package repo.
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
- For scientific or multi-author cleanup work, preserve contributed methods,
  mathematical code, historical bridge code, and long-form vignettes unless a
  change fixes an objective bug, resource-safety issue, packaging integration,
  tests, or safe typo. Use wrapper docs/articles for navigation and defer
  structural rewrites to separate tested plans.
- When widening accepted dimensions or configurations, revalidate formulas,
  stored metadata, and documentation that claim broader applicability at every
  newly admitted boundary class. Use the reference-applicability checklist in
  [checks.md](references/checks.md#reference-metadata-applicability).
- For API naming, public diagnostic value, warning ownership, or progress-message
  contracts, read
  [public-api-contracts.md](references/public-api-contracts.md).
- When an exported API forwards `...` to interchangeable backends, follow
  [variadic-backend-controls.md](references/variadic-backend-controls.md) for
  early validation, routing categories, fallback behavior, and public tests.
- Prefer exported API tests over private-helper tests. If an internal test
  remains, document the safety or user-visible behavior it protects.
- Treat these as generated unless intentionally refreshed:
  `R/RcppExports.R`, `src/RcppExports.cpp`, `NAMESPACE`, `man/*.Rd`,
  pkgdown output under `docs/`.
- When introducing top-level hidden development config files such as
  `.air.toml`, `.lintr`, or `.styler.R`, add exact anchored `.Rbuildignore`
  entries in the same phase and confirm the R CMD check hidden-file check is OK.
- When moving runtime dependencies to `Suggests`, guard every execution path
  with `requireNamespace()`, give users a clear install message, document the
  optional requirement, and skip tests that execute the optional path when the
  package is absent.
- Use `apply_patch` for manual edits. Use package tools for generated output.
- After `usethis` modifies infrastructure, re-harden generated files rather
  than accepting templates as final.

## Checks

Choose checks based on blast radius. See [checks.md](references/checks.md) for
the command matrix, warning attribution, and final-validation workflows.

After substantive edits to hand-maintained R source or tests, run the
configured Air check and lintr in addition to behavior-driven checks. If either
configured check is unavailable, name the command not run and report validation
as incomplete.

Treat every repository-attributable package-check error, warning, or note as
unfinished work and resolve it when first found. A completed local package check
should report 0 errors, 0 warnings, and 0 notes attributable to the repository.
If an environmental or external-service diagnostic cannot be cleared after
appropriate reruns, lead the validation summary with the incomplete or blocked
state rather than normalizing it as baseline noise. Preserve the exact
diagnostic, attribution evidence, and whether it was present before the change.
Treat a new, code-specific, or behavior-changing diagnostic as attributable to
the repository until evidence establishes another owner.

For ambiguous check ownership, use the exact restricted-environment mechanics
in [checks.md](references/checks.md#restricted-environment-mechanics). Consult
[check-diagnostic-cases.md](references/check-diagnostic-cases.md) only when that
default judgment and the relevant mechanics do not make the next action clear.

For compiled packages, do not run `covr::package_coverage()` and
`testthat::test_local()` concurrently from the same worktree. Sequence them to
avoid transient package DLL copy/load races, and rerun a `dyn.load()` failure
alone before treating it as a code regression.

Scripts:

- `${HOME}/.agents/skills/r-package-workflow/scripts/check-r-package.sh`:
  run a local check bundle.
- `${HOME}/.agents/skills/r-package-workflow/scripts/audit-generated-r-files.sh`:
  list likely generated files touched in the current diff.

For sparse `Matrix` slot-level implementation work, use the idioms in
[sparse-matrix.md](references/sparse-matrix.md).

If the task touches a narrower area, also apply the focused skill when
available:

- GitHub Actions, pkgdown deploy, coverage, Dependabot: `$r-ci-hardening`.
- Tests and fixtures: `$r-test-hygiene`.
- README, NEWS, roxygen, articles, pkgdown: `$r-docs-pkgdown`.
- Rcpp, compiled code, `src/`, `Makevars`: `$r-rcpp-package`.
- Performance benchmarks, phased optimization, before/after evidence:
  `$r-performance-workflow`.
