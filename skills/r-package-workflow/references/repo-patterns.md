# James's R Repository Patterns

Use these conventions across `/home/james/dev` R packages unless a repository
clearly establishes a different local standard.

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

## Documentation

- Keep README quick-start focused.
- Move long metric explanations, background, and literature notes into pkgdown
  articles.
- Use `NEWS.md` for behavior changes and notable infrastructure changes.

## Reference Repos

Useful comparisons:

- `/home/james/dev/flotsam`
- `/home/james/dev/rnndescent`
- `/home/james/dev/snedata`
- `/home/james/dev/uwot`
- `/home/james/dev/RcppHNSW`
- `/home/james/dev/vizier`
