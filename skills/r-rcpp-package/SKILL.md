---
name: r-rcpp-package
description: Rcpp and compiled-code workflow for R packages, including src changes, Makevars, Rcpp attributes, generated RcppExports files, C++ formatting, thread safety, exception propagation, and compiled-code checks. Use when Codex edits or reviews C/C++/Rcpp code, src/ headers, Rcpp wrappers, Makevars, or compiled behavior in an R package.
---

# Rcpp Package Work

Use this for compiled-code changes in R packages.

## Core Rules

- Read `src/`, `R/RcppExports.R`, `src/RcppExports.cpp`, `src/Makevars`, and
  relevant R wrappers before editing.
- Do not hand-edit generated Rcpp exports except for diagnosis.
- Run `Rscript -e 'Rcpp::compileAttributes()'` after changing exported Rcpp
  functions or attributes.
- Keep generated C++ separate from clang-format decisions.
- Prefer repository-local helper patterns over new concurrency or distance
  abstractions.
- Preserve exception propagation from worker threads; do not swallow worker
  exceptions.

## Generated Files

Expected generated outputs:

- `R/RcppExports.R`
- `src/RcppExports.cpp`

If these change unexpectedly, inspect the diff and rerun
`Rcpp::compileAttributes()` to confirm idempotence.

## C++ Safety

- Validate inputs at the R boundary when possible.
- C++ helpers should still fail loudly for invalid internal states.
- Avoid test-only exported C++ hooks in release code unless explicitly
  documented.
- Use RAII for thread joining and resource cleanup.
- Prefer explicit chunk IDs for per-thread RNG streams.

See [rcpp.md](references/rcpp.md) for check guidance.

## Checks

```sh
Rscript -e 'Rcpp::compileAttributes()'
Rscript -e 'testthat::test_local()'
Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"))'
clang-format --dry-run --Werror src/*.cpp src/*.h
```

Adjust the clang-format target to exclude generated files when the repo treats
`src/RcppExports.cpp` as generated-only.
