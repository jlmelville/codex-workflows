---
name: r-test-hygiene
description: R package test design and cleanup for testthat suites, fixtures, snapshots, helper files, internal-only tests, testthat edition migrations, test-only hooks, and Air readability guards. Use when Codex writes, reviews, refactors, migrates, or cleans tests in tests/testthat or test helpers for an R package.
---

# R Test Hygiene

Use this for R package tests and fixtures.

## Principles

- Test user-visible behavior through exported APIs where practical.
- Keep internal-helper tests only when they protect a meaningful safety
  invariant that cannot be observed through public paths; document why.
- Remove test-only exported R or C++ hooks before release unless explicitly
  justified.
- Keep tests readable enough to explain the behavior under review. Test files
  can use different formatting choices from application code when clarity
  requires it.
- Avoid mixing unrelated fixture reformatting with correctness changes unless
  the user asks for a test-readability sweep.

## Fixture Formatting

For shape-sensitive fixtures, preserve visual structure:

- distance matrices,
- nearest-neighbor index matrices,
- co-ranking matrices,
- triplet matrices,
- expected graph/list structures,
- compact synthetic datasets.

Use `# fmt: skip` immediately before the expression when Air would obscure the
shape. See [fixtures.md](references/fixtures.md).

## testthat Edition Migrations

When opting an existing package into `Config/testthat/edition: 3`, isolate the
migration if initial probing shows broad numerical fallout:

1. Remove deprecated `context()` calls and update `DESCRIPTION`/`Suggests`
   deliberately.
2. Run the full suite immediately. If testthat's failure cap hides the pattern,
   rerun
   `Rscript -e 'testthat::set_max_fails(Inf); testthat::test_local()'`.
3. Record the complete failure set before editing expectations.
4. Prefer explicit tolerances, near-zero thresholds, optimizer invariants, or
   success properties over production changes.
5. Do not change production behavior unless the migration exposes a real bug
   with independent evidence.
6. Rerun full tests, then broaden to format, lint, or package checks according
   to blast radius.

## Review Checklist

1. Search for direct private calls: `:::`, `getFromNamespace`,
   generated Rcpp wrappers, and internal helper names.
2. Replace with public API tests when behavior is observable.
3. Keep focused internal tests only with a comment or plan note explaining the
   external behavior or safety property protected.
4. Run focused tests first, then full `testthat::test_local()`.
5. Run `air format . --check` after adding formatter guards.
6. Run lintr when manual alignment is introduced.

## Common Commands

```sh
rg -n ":::|getFromNamespace|\\.Call|RcppExports|sourceCpp" tests
air format tests/testthat --check
Rscript -e 'testthat::test_local()'
Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'
```
