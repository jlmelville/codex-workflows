# Test Fixture Readability

Use `# fmt: skip` sparingly, immediately before the expression Air should not
rewrite.

## Matrix Fixtures

Prefer row-wise layout when rows matter:

```r
# fmt: skip
dm <- matrix(
  c(
    0, 1, 4,
    1, 0, 5,
    4, 5, 0
  ),
  nrow = 3,
  byrow = TRUE
)
```

Use this for distance matrices, neighbor index matrices, co-ranking matrices,
embeddings, and triplets.

## Probe Broad Air Changes

Before a broad Air cleanup in fixture-heavy tests, format a temporary copy and
inspect the churn before touching real files:

```sh
tmp=$(mktemp -d /tmp/air-fixtures.XXXXXX)
cp -a tests/testthat "$tmp/"
air format "$tmp/testthat"
git diff --no-index --stat tests/testthat "$tmp/testthat"
```

The `git diff --no-index` command exits non-zero when it finds differences;
that is expected for a formatting probe.

Use the probe diff to find layouts that Air expands into unreadable
one-value-per-line fixtures. Add targeted `# fmt: skip` guards in the real
files before formatting them. Use `# fmt: skip file` only for helper or fixture
files where most of the file is intentionally shaped data and expression-level
guards would be noisier than preserving the file as-is.

## Expected Lists

Use shape-preserving layout for expected nested objects when it shows the
contract:

```r
# fmt: skip
expected <- list(
  idx = matrix(
    c(
      2, 3,
      1, 3,
      1, 2
    ),
    nrow = 3,
    byrow = TRUE
  )
)
```

## When Not To Skip

Do not add `# fmt: skip` to ordinary expectations, simple scalar vectors, or
application code where Air's formatting is acceptable.

## After Guards

Always run:

```sh
air format tests/testthat --check
Rscript -e 'testthat::test_local()'
```

Run lintr too if manual alignment was added.
