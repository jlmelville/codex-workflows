# Rcpp Package Reference

## Attribute Workflow

After adding, removing, or changing `// [[Rcpp::export]]` functions:

```sh
Rscript -e 'Rcpp::compileAttributes()'
git diff -- R/RcppExports.R src/RcppExports.cpp
Rscript -e 'Rcpp::compileAttributes()'
```

The second run should be idempotent.

## Formatting

- Format hand-maintained C++ files with the repo's `.clang-format`.
- Do not manually format generated `src/RcppExports.cpp` unless the repo has
  explicitly decided to do so.
- Use explicit target lists for clang-format when needed:

```sh
clang-format --dry-run --Werror src/distance.h src/random-dist.cpp
```

## Threading

- Use RAII joiners or established local parallel helpers.
- Capture and rethrow worker exceptions.
- Avoid using chunk end offsets as thread IDs.
- Keep RNG contracts explicit in docs/tests: same seed plus same thread count
  should be reproducible unless a different contract is documented.

## Tests

- Prefer public R API tests for compiled behavior.
- If an internal compiled helper is necessary for safety coverage, document why
  it remains and remove it before release if public paths become available.
- Include too-small input, invalid metric, tie/edge cases, and thread-count
  coverage when those semantics matter.

## Check Output

`R CMD check` notes for compiler flags or time verification may be environment
specific. Record known notes in project plans rather than treating them as new
regressions each run.
