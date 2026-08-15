---
name: r-rcpp-package
description: Rcpp and compiled-code workflow for R packages, including src changes, Makevars, Rcpp attributes, RcppExports, C++ formatting, thread safety, exception propagation, and compiled checks. Use when Codex edits or reviews C/C++/Rcpp code, headers, wrappers, Makevars, or compiled behavior.
---

# Rcpp Package Work

Use this for compiled-code changes in R packages.

## Core Rules

- Read `src/`, `R/RcppExports.R`, `src/RcppExports.cpp`, `src/Makevars`, and
  relevant R wrappers before editing.
- Keep generated C++ separate from clang-format decisions.
- Prefer repository-local helper patterns over new concurrency or distance
  abstractions.
- Preserve exception propagation from worker threads; do not swallow worker
  exceptions.

## Generated Files

After changing `// [[Rcpp::export]]` functions or attributes, regenerate the
exports, confirm the generated diff contains only the intended signature or
registration change, and regenerate again; the second pass must be idempotent.
Do not hand-edit generated exports to repair a diff. Follow the exact
[Attribute Workflow](references/rcpp.md#attribute-workflow), including the
owned generated files. If generated output changes unexpectedly, stop and
inspect before layering on more edits.

## C++ Safety

- Validate inputs at the R boundary when possible.
- Treat registered routines as independently reachable when defining their
  supported callers and native safety boundary; technical reachability alone
  does not make direct calls supported.
- Let R own public semantic validation. Keep native checks needed on supported
  paths for representable conversion, bounded allocation, unchecked access,
  thread setup, or algorithm integrity. Do not duplicate whole-input scans
  solely to harden unsupported private calls unless an independent native
  memory-safety boundary is an explicit requirement.
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
