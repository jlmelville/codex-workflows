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
- For numerical or statistical robustness work, inventory existing tests by
  algorithm family before changing behavior. Separate golden trace/output
  regressions from mathematical invariant or property tests, then list missing
  invariants in the active plan.
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
be brittle.

When file-level coverage is too blunt, optionally aggregate the inspectable
coverage data by function before choosing test targets:

```sh
Rscript -e 'cov <- covr::package_coverage(type = "tests")
df <- as.data.frame(cov)
fn <- aggregate(
  df$value,
  list(filename = df$filename, functions = df$functions),
  function(x) mean(x > 0)
)
print(fn[order(fn$filename, fn$functions), ], row.names = FALSE)'
```

Classify gaps by user-visible risk before adding tests. Prefer default public
paths, deterministic internal algebra, and diagnostics users can observe. Do
not invent APIs, exported hooks, or artificial C++ entry points just to cover
defensive-only branches such as overflow guards, dependency failure paths,
builder misuse, or unload cleanup, unless there is a concrete regression or
release risk.

## Visualization Outputs

For visualization-heavy packages, do not treat plots as untestable just because
browser, snapshot, or pixel comparisons would be brittle. Use coverage to find
deterministic helpers, branch logic, and public plot constructors that return
inspectable objects.

For Plotly outputs, call `plotly::plotly_build()` and assert trace, marker,
color, axis, and layout fields that express the user-visible contract. Normalize
vectors with `as.character()` or `as.numeric()` when names or attributes such
as `apiSrc` are irrelevant to the behavior under test. For base graphics paths,
use a temporary graphics device for no-error smoke coverage, then close it with
`on.exit()` cleanup.

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

## Warning Regressions

For R partial-match warnings, fix the source by using exact `[[...]]` access for
optional list fields instead of suppressing the warning. Add a focused
regression with `options(warnPartialMatchDollar = TRUE)`, restore options with
`on.exit()`, and assert `expect_warning(..., NA)` around the behavior that
previously emitted the partial match.

## Looped Test Diagnostics

Not every testthat expectation accepts `info` consistently across installed
versions. For table-driven comparison diagnostics, prefer
`expect_true(<comparison>, info = case$name)` when the case label matters, and
smoke-run the focused test immediately after adding diagnostic arguments.

## testthat Edition Migrations

When opting an existing package into `Config/testthat/edition: 3`, isolate the
migration if initial probing shows broad numerical fallout:

1. Remove deprecated `context()` calls and update `DESCRIPTION`/`Suggests`
   deliberately.
2. Run the full suite immediately. If testthat's failure cap hides the pattern,
   rerun
   `Rscript -e 'testthat::set_max_fails(Inf); testthat::test_local()'`.
3. Record the complete failure set before editing expectations.
4. After replacing deprecated `tol =` with `tolerance =`, do not assume the
   comparison semantics are unchanged. Edition 3 uses waldo-style comparison,
   and relative tolerance can expose small rounded optimizer or simulation trace
   differences.
5. Prefer explicit tolerances, near-zero thresholds, optimizer invariants, or
   success properties over production changes.
6. Do not globally shadow `expect_equal()`. If rounded trace fixtures
   intentionally need absolute tolerance, use a clearly named narrow helper
   such as `expect_equal_abs()` for those assertions and keep regular
   `expect_equal()` elsewhere.
7. Do not change production behavior unless the migration exposes a real bug
   with independent evidence.
8. Rerun full tests, then broaden to format, lint, or package checks according
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
