# R Package Check Selection

Use the smallest check set that gives real confidence. Broaden when touching
shared behavior, generated files, infrastructure, or compiled code.

## R Behavior

- Focused test file: `Rscript -e 'testthat::test_local(filter = "pattern")'`
- Full tests: `Rscript -e 'testthat::test_local()'`
- Full package check: `Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"))'`

Run full tests after changes to exported behavior, validation, data conversion,
cross-module helpers, or test fixtures used by multiple files.

## Documentation

- Roxygen refresh: `Rscript -e 'roxygen2::roxygenise()'`
- README/article smoke tests if present.
- pkgdown build when changing `_pkgdown.yml`, articles, examples, or generated
  docs: `Rscript -e 'pkgdown::build_site(new_process = FALSE)'`

Network-restricted environments may need escalation for pkgdown external
assets or CRAN metadata.

## Rcpp

- Attribute refresh: `Rscript -e 'Rcpp::compileAttributes()'`
- Full tests after compiled changes.
- `R CMD check` or `devtools::check()` for installation and compiled-code
  checks.
- Run clang-format checks for hand-maintained C++ if configured.

## Restricted Environment Notes

Codex sandboxes and CI-like containers can produce notes that are environmental
rather than regressions. Classify and report them once instead of rediscovering
them every run.

When R tooling needs caches in a restricted filesystem, redirect them to a
writable temporary path, for example `XDG_CACHE_HOME=/tmp/r-cache`. If
pkgdown/check validation fails because DNS, CRAN metadata, or external assets
are blocked and the validation matters, rerun with approved network escalation
instead of treating the first sandbox failure as package evidence.

Common examples:

- unable to verify current time or internet-dependent metadata;
- CRAN source index, package repository, or URL access blocked by network
  policy;
- system bus or desktop-service warnings from headless environments;
- compiler flag notes from local toolchains, such as
  `-mno-omit-leaf-frame-pointer`, when already present before the change.

Do not hide these notes. Record the exact note, explain why it is believed to be
environmental, and say whether the same note was present before the change. If
a note is new, code-specific, or changes package behavior, treat it as a real
finding until proven otherwise.

Do not treat missing or untracked `docs/` output as a package source diff unless
the repo tracks pkgdown output or the user asked to update the site.

## Formatting and Lint

- Air owns R/Rmd formatting: `air format . --check`
- Lintr should not fight Air:
  `Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'`

For test fixtures, use `# fmt: skip` around shape-sensitive matrix/list
fixtures where Air reduces readability.

## GitHub Actions

- Syntax/security checks: `actionlint` and `uvx zizmor .github/workflows`
- Inspect all `uses:` entries for full-length SHA pins.
- Confirm checkout steps set `persist-credentials: false`.

## Coverage

- `Rscript -e 'covr::package_coverage()'`
- Use `.covrignore` only for intentional exclusions.
