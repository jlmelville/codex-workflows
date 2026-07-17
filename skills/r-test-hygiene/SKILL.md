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
- For numerical or statistical robustness work, inventory existing tests by
  algorithm family before changing behavior. Separate golden trace/output
  regressions from mathematical invariant or property tests, then list missing
  invariants in the active plan. For factory-return objects, benchmark
  functions, or derivative code, also use
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

## Local Download Fixtures

When a public download, dataset, or parser wrapper accepts `base_url`, `url`,
or `tmpdir`, prefer tiny local fixtures over remote integration tests for
wrapper plumbing. Use `file://` gzip fixtures for byte parsers and local tar or
folder fixtures for archive/directory readers.

Keep payloads minimal, but include non-contiguous labels or ids when the parser
maps codes to descriptions or factors. Include boundary-like values such as
`0` and a high label so tests catch factor-code indexing mistakes, including
patterns like `description_levels[as.numeric(label)]`.

For untrusted tar archives, entry-name and normalized-path checks are not
enough: inspect tar type flags before extraction and reject symbolic links,
hard links, and unsupported special entries. Add a local link-containing tar
fixture alongside traversal and duplicate-path regressions; keep tar and ZIP
expectations separate because their metadata APIs and extractors differ.
Construct link fixtures by writing a minimal tar header or using an archive API
that sets the entry type and link target directly; do not require
`file.symlink()` as an intermediate step because CI runners may lack that
filesystem capability.

## Warning Regressions

For R partial-match warnings, fix the source by using exact `[[...]]` access for
optional list fields instead of suppressing the warning. Add a focused
regression with `options(warnPartialMatchDollar = TRUE)`, restore options with
`on.exit()`, and assert `expect_warning(..., NA)` around the behavior that
previously emitted the partial match.

## Validation Diagnostics

For paired validation branches, test both directions and assert diagnostic
direction through public APIs. Examples include sparse versus dense inputs,
logical versus numeric storage, reference versus query data, and model versus
newdata compatibility. Prefer expectations that distinguish which side is
wrong; a loose substring can preserve an inverted user-facing error.

When canonical metadata gains names, classes, or other attributes, rerun the
raw parser/spec boundary with tiny local fixtures. `identical()` compares
attributes as well as values, so normalize with `unname()` or a similarly
explicit value-only comparison when raw attributes are not part of the
contract, while preserving the canonical attributes in result expectations.

## Looped Test Diagnostics

Not every testthat expectation accepts `info` consistently across installed
versions. For table-driven comparison diagnostics, prefer
`expect_true(<comparison>, info = case$name)` when the case label matters, and
smoke-run the focused test immediately after adding diagnostic arguments.

## testthat Edition Migrations

When opting an existing package into `Config/testthat/edition: 3`, isolate the
migration, record the complete failure set before editing expectations, and do
not assume tolerance semantics are unchanged. See
[testthat-edition-migrations.md](references/testthat-edition-migrations.md).

## Review Checklist

1. Search for direct private calls: `:::`, `getFromNamespace`,
   generated Rcpp wrappers, and internal helper names.
2. Replace with public API tests when behavior is observable.
3. Keep focused internal tests only with a comment or plan note explaining the
   external behavior or safety property protected.
4. Run focused tests first, then full `testthat::test_local()`.
5. Run `air format . --check` after adding formatter guards.
6. Run lintr when manual alignment is introduced.

## Focused Package Tests

Prefer `testthat::test_local(filter = "pattern")` for focused package runs. A
bare `testthat::test_file()` can fail with missing package functions,
internals, or helpers because package loading did not happen. Use
`pkgload::load_all()` before `test_file()` only for explicit ad hoc probes that
need direct file execution.

## Common Commands

```sh
rg -n ":::|getFromNamespace|\\.Call|RcppExports|sourceCpp" tests
air format tests/testthat --check
Rscript -e 'testthat::test_local(filter = "pattern")'
Rscript -e 'testthat::test_local()'
Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'
```
