---
name: r-test-hygiene
description: Design and clean R package tests for testthat suites, fixtures, snapshots, helpers, internal-only tests, edition migrations, test-only hooks, and Air readability. Use when Codex writes, reviews, refactors, migrates, or cleans tests in tests/testthat or test helpers.
---

# R Test Hygiene

Use this for R package tests and fixtures.

## Principles

- Test user-visible behavior through exported APIs where practical.
- Keep internal-helper tests only when they protect a meaningful safety
  invariant that cannot be observed through public paths; document why.
- Before intentionally tightening a validation contract, find tests that
  positively characterize the soon-to-be-invalid behavior and invert them to
  rejection expectations before changing production code. Retain the focused
  pre-fix failure set as evidence that the suite distinguishes the old and new
  contracts.
- For numerical or statistical robustness work, inventory existing tests by
  algorithm family before changing behavior. Separate golden trace/output
  regressions from mathematical invariant or property tests, then list missing
  invariants in the active plan. For this work, also use
  [numerical-contracts.md](references/numerical-contracts.md).
- Remove test-only exported R or C++ hooks before release unless explicitly
  justified.
- For cleanup chunks that fix multiple unrelated bugs, organize regression tests
  by bug-scoped files or clearly separated sections so each fix can be reviewed,
  staged, and committed independently.
- Keep tests readable enough to explain the behavior under review. Test files
  can use different formatting choices from application code when clarity
  requires it.
- Avoid mixing unrelated fixture reformatting with correctness changes unless
  the user asks for a test-readability sweep.

## Coverage ROI Triage

When an R package already has high coverage, treat `covr` output as a map, not
a target. Use `as.data.frame(covr::package_coverage(type = "tests"))` when you
need inspectable uncovered ranges; direct `$` access on coverage internals can
be brittle. See [coverage-roi.md](references/coverage-roi.md) for
function-level aggregation and visualization-output patterns.

Classify gaps by user-visible risk before adding tests. Prefer default public
paths, deterministic internal algebra, and diagnostics users can observe. Do
not invent APIs, exported hooks, or artificial C++ entry points just to cover
defensive-only branches such as overflow guards, dependency failure paths,
builder misuse, or unload cleanup, unless there is a concrete regression or
release risk.

Before writing direct tests for uncovered private helpers, classify each helper
as test, remove, or consciously retain. Use `rg` to confirm active references
in `R/` and `tests/testthat/`; when current public paths no longer use the
helper, prefer removal plus public-contract tests over preserving dead internals
with direct coverage tests.

## Refactor Safety Nets

Before refactoring state machines, hook dispatchers, staged pipelines, caches,
or lifecycle controllers, add small synthetic contract tests before changing
code, even when existing coverage or integration traces look broad. Build tiny
custom hooks or stages that mutate state and assert downstream effects: event
order, stage or sub-stage writeback, termination short-circuiting, validation
rollback, eager parameter propagation, and restart hook replacement. Direct
internal probes are justified when public golden traces cannot localize those
lifecycle invariants; keep them named and narrow.

For cache validity, reset lifetimes, oracle authority, state identity, and
tested-constructor wiring, read
[state-machine-contracts.md](references/state-machine-contracts.md).

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

## Download And Archive Fixtures

For local download or parser fixtures, label-code edge cases, or archive-safety
regressions, read
[download-and-archive-fixtures.md](references/download-and-archive-fixtures.md).

## Diagnostic Regressions

For warning regressions, paired validation branches, metadata attributes, or
table-driven diagnostic labels, read
[diagnostic-regressions.md](references/diagnostic-regressions.md).

## testthat Edition Migrations

When opting an existing package into `Config/testthat/edition: 3`, isolate the
migration, record the complete failure set before editing expectations, and do
not assume tolerance semantics are unchanged. See
[testthat-edition-migrations.md](references/testthat-edition-migrations.md).

## Focused Package Tests

Prefer `testthat::test_local(filter = "pattern")` for focused package runs. A
bare `testthat::test_file()` can fail with missing package functions,
internals, or helpers because package loading did not happen. Use
`pkgload::load_all()` before `test_file()` only for explicit ad hoc probes that
need direct file execution.

For exact file selection, reported-context checks, compact result totals, or a
suspected incomplete full-suite run, read
[test-selection-and-totals.md](references/test-selection-and-totals.md).
When claiming an exact total, name the command and counting convention, reconcile
legacy top-level expectations, and report additional validation lanes separately
rather than folding them into the structured testthat count.

For callback budgets and result validation, bounded numerical searches, or
adapters that install backend results, read
[numerical-callbacks-and-results.md](references/numerical-callbacks-and-results.md).

## Common Commands

Use the public-versus-internal test rule above when the private-call search
finds a candidate. Run focused tests before the full suite; include Air or
lintr when the change affects formatting or lint configuration.

```sh
rg -n ":::|getFromNamespace|\\.Call|RcppExports|sourceCpp" tests
air format tests/testthat --check
Rscript -e 'testthat::test_local(filter = "pattern")'
Rscript -e 'testthat::test_local()'
Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'
```
