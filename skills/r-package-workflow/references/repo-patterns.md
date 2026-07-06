# James's R Repository Patterns

Use these conventions across James's local R packages unless a repository
clearly establishes a different local standard. The repo root is usually under
`~/dev`; verify the actual path on the current machine before using a concrete
reference path.

## Infrastructure

- Prefer complete `usethis` scaffolding or a complete known-good reference repo
  bundle. Do not create only the obvious workflow file.
- After `usethis`, compare and harden generated workflows before considering
  them final.
- GitHub Actions should use SHA-pinned actions, read-only default permissions,
  `persist-credentials: false`, concurrency groups, and write permissions only
  in deploy jobs.
- Dependabot should cover GitHub Actions updates.

## Formatting

- Air owns R/Rmd formatting.
- Lintr should focus on non-formatting issues.
- Use `# fmt: skip` for matrix/graph fixtures where row or block shape is part
  of test readability.
- Keep generated files separate from manual formatting decisions.

## Generated Files

- `Rcpp::compileAttributes()` owns `R/RcppExports.R` and
  `src/RcppExports.cpp`.
- `roxygen2::roxygenise()` owns `NAMESPACE` and `man/*.Rd`.
- Do not edit generated files by hand unless diagnosing or explicitly making a
  narrow generated-file-only change.

## Tests

- Prefer exported API tests.
- Keep test-only hooks out of release code unless a documented safety invariant
  cannot be exercised through public paths.
- Fixture readability matters more in tests than in application code; preserve
  visual structure when it explains behavior.

## Local Benchmark Data

When work mentions `loadj()`, `savej()`, `nng()`, `nngi()`, or saved benchmark
neighbors, treat them as James-local helpers unless package code proves
otherwise. Do not spend time searching for them as package functions before
checking the local data surface.

Start with the read-only manifest when present:

```sh
column -t -s $'\t' /mnt/e/dev/R/datasets/R-datasets-manifest.tsv
```

Use it to identify dataset bundle files, `X`/`Y` shapes, label columns,
neighbor dimensions, and `nn_k` before loading data or recomputing nearest
neighbors. Current bundle entries are typically `*l.Rda`/`*l.Rds` files with
saved 150-nearest-neighbor graphs.

If the manifest is missing, stale, or a helper's behavior matters, inspect the
targeted definitions in `/home/james/.Rprofile` and load any `.Rda`/`.Rds`
files into an isolated environment, not `.GlobalEnv`. The canonical WSL data
root is usually `/mnt/e/dev/R/datasets`; on non-WSL machines this path may be
absent.

If asked to validate, update, or regenerate the manifest itself, use
`$local-r-dataset-manifest`.

## Documentation

- Keep README quick-start focused.
- Move long metric explanations, background, and literature notes into pkgdown
  articles.
- Use `NEWS.md` for behavior changes and notable infrastructure changes.

## Reference Repos

Useful comparisons, when present under the current machine's `~/dev`:

- `flotsam`
- `rnndescent`
- `snedata`
- `uwot`
- `RcppHNSW`
- `vizier`
