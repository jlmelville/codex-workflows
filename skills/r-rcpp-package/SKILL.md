---
name: r-rcpp-package
description: Rcpp and cpp11 compiled-code workflow for R packages, including src changes, Makevars, generated bindings, C++ formatting, thread safety, exception propagation, and compiled checks. Use when Codex edits or reviews C/C++/Rcpp/cpp11 code, headers, wrappers, Makevars, or compiled behavior.
---

# Compiled R Package Work

Use this for compiled-code changes in R packages.

## Core Rules

- Identify the bridge before editing from `DESCRIPTION` `LinkingTo`, source
  attributes, and generated-file headers. Do not infer Rcpp merely from the
  presence of compiled code.
- Read `src/`, `src/Makevars`, relevant R wrappers, and the binding-specific
  generated files: `R/RcppExports.R` and `src/RcppExports.cpp` for Rcpp, or
  `R/cpp11.R` and `src/cpp11.cpp` for cpp11.
- Keep generated C++ separate from clang-format decisions.
- Prefer repository-local helper patterns over new concurrency or distance
  abstractions.
- Preserve exception propagation from worker threads; do not swallow worker
  exceptions.

## Generated Files

Choose the generator from the detected bridge:

- For Rcpp, after changing `// [[Rcpp::export]]` functions or attributes, use
  `Rcpp::compileAttributes()` and inspect `R/RcppExports.R` and
  `src/RcppExports.cpp`. Follow the exact
  [Attribute Workflow](references/rcpp.md#attribute-workflow).
- For cpp11, after changing `[[cpp11::register]]` functions or registered
  signatures, use `cpp11::cpp_register()` and inspect `R/cpp11.R` and
  `src/cpp11.cpp`. A hand-maintained parameter rename can change generated R
  formals and C++ signatures without changing the registered function name.

Run the selected generator twice; the second pass must be idempotent. Do not
run the other bridge's generator or hand-edit generated outputs to repair a
diff. If generated output changes unexpectedly, stop and inspect before
layering on more edits.

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

Choose exactly one generation command when bindings changed:

```sh
Rscript -e 'Rcpp::compileAttributes()' # Rcpp
Rscript -e 'cpp11::cpp_register()'     # cpp11
Rscript -e 'testthat::test_local()'
Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"))'
clang-format --dry-run --Werror <hand-maintained-C++-paths>
```

Always exclude generated `src/RcppExports.cpp` or `src/cpp11.cpp` from
hand-maintained formatting judgments.
