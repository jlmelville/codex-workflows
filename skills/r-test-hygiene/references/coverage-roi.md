# Coverage ROI Triage

Use this when coverage is already moderate or high and raw file-level
percentages are too blunt to identify useful tests.

## Function-Level Aggregation

Optionally aggregate the inspectable `covr` data by function before choosing
test targets:

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

Use the result to find user-visible gaps or deterministic helper families, not
to chase a package-wide percentage.

For compiled packages, do not run coverage and `testthat::test_local()` in
parallel from the same worktree; see the sequencing caveat in
`r-package-workflow > Checks`.

## Coverage-Blind Semantic Probes

When coverage is already high and uncovered R ranges are mostly validation or
defensive branches, add a few minimal public API probes before concluding the
remaining work is pure test fill-in. Focus on semantics that coverage
percentages do not expose: sentinel or missing-value handling, zero-length or
boundary `k` values, duplicated ids, ordering ties, and default versus explicit
argument paths.

Classify any failing public probe as a bug-revealing test, not a pure test
addition. Preserve the exact public call, observed behavior, expected behavior,
and whether implementation changes are required in the handoff or plan. This is
especially important when missing-value sentinels such as `0`, `NA`, or empty
neighbors could be accidentally counted as ordinary data.

## Private Helper Cleanup

When uncovered ranges sit in private helpers, check whether the helper still
belongs in the package before adding internal tests. Search current source and
tests, including direct private calls:

```sh
rg -n "helper_name" R tests
```

If public behavior has moved to a newer path and no current code uses the
helper, prefer deleting it and adding public-contract tests for the replacement
behavior. Retain a private helper only when it still protects a meaningful
internal invariant, and explain that invariant in the test or plan.

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
