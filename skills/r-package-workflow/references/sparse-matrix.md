# Sparse Matrix Implementation Notes

Use this when touching sparse-safe R code that works directly with
`Matrix::dgCMatrix` slots.

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
