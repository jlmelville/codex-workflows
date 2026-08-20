# Sparse Matrix Implementation Notes

Use this when touching sparse-safe R code that works directly with
`Matrix::dgCMatrix` slots.

## Conversion Boundaries

Detect supported sparse S4 objects before generic coercion with
`methods::is(x, "sparseMatrix")`; `is.numeric()` alone is not a reliable sparse
class test. For each downstream route, explicitly preserve the sparse object or
reject it with a clear contract. Do not allow a shared `as.matrix()` fallback
to densify it silently.

Pair public route tests with one narrow private class-preservation or object
identity assertion when numerically correct results cannot prove that an
allocation-unsafe conversion was avoided. Document the safety invariant that
justifies the internal test.

## Structural Support Contracts

When one sparse input estimates numerical quantities and another defines where
contributions may be scattered, test those contracts independently. Define the
allowed coordinate set, construct an adversarial fixture with estimation-only
rows or columns, and assert that occupied slots are an exact subset of the
allowed support and forbidden slots remain exactly zero. Keep tolerance-based
value comparisons and algebraic invariants as separate evidence; dense
closeness cannot establish structural nonparticipation.

## Slot Aggregation

For unweighted structural counts, `tabulate()` is appropriate:

```r
degree <- tabulate(B@i + 1L, nbins = nrow(B))
```

For weighted row aggregation, do not rely on `tabulate(..., weights = ...)`;
that argument is not available in all R environments. Aggregate slot values with
`rowsum()` and assign back into a full-length vector:

```r
row_abs_sum <- numeric(nrow(B))
rs <- rowsum(abs(B@x), B@i + 1L, reorder = FALSE)
row_abs_sum[as.integer(rownames(rs))] <- rs[, 1L]
```

Validate sparse slot code against high-level `Matrix` operations such as
`Matrix::rowSums(abs(B))` on small matrices only. Avoid converting large sparse
inputs to dense matrices for validation or production paths.
