# R Package Check Selection

Use the smallest check set that gives real confidence. Broaden when touching
shared behavior, generated files, infrastructure, or compiled code.

## R Behavior

- Focused test file: `Rscript -e 'testthat::test_local(filter = "pattern")'`
- Focused package-style test file:
  `Rscript -e 'pkgload::load_all(); testthat::test_file("tests/testthat/test-name.R")'`
- Full tests: `Rscript -e 'testthat::test_local()'`
- Full package check: `Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"))'`

Before running a single `tests/testthat/test-*.R` file directly, inspect
`tests/testthat.R`. If the suite loads the package before running tests, use
`pkgload::load_all()` before `testthat::test_file()`. A bare `test_file()`
failure such as "could not find function" may be a harness failure, not package
behavior, when no package code was loaded.

Run full tests after changes to exported behavior, validation, data conversion,
cross-module helpers, or test fixtures used by multiple files.

## Vignette Skip Semantics

When CI policy is "do not build vignettes", distinguish the two `rcmdcheck`
layers:

- `build_args` is passed to `R CMD build`.
- `args` is passed to `R CMD check`.

For `r-lib/actions/check-r-package`, putting `--no-build-vignettes` only in
`args` does not stop build-time vignette rebuilds. When no `inst/doc` vignette
output is expected, use `--no-build-vignettes` on the build side and
`--ignore-vignettes` on the check side:

```r
rcmdcheck::rcmdcheck(
  args = c("--no-manual", "--ignore-vignettes"),
  build_args = c("--no-manual", "--no-build-vignettes"),
  error_on = "never"
)
```

If local or CI output says a vignette was rebuilt despite an intended skip, or
reports "Package vignette without corresponding single PDF/HTML", inspect both
layers before changing vignette sources.

## R Warning Attribution

When a warning mentions symbols that could be local code, graphics/device state,
or dependency internals, prove the source before assigning blame:

1. Reproduce a minimal path and the user's full path.
2. Search local package code first for the warning text, symbol, helper name, or
   call path.
3. If the signal points into a dependency, inspect exported and unexported
   helpers:
   `getAnywhere("name")`, then
   `get("name", envir = asNamespace("pkg"), inherits = FALSE)` when the package
   is known.
4. Use `options(warn = 2)` or focused tracing only when needed to turn an
   intermittent warning into a traceback.
5. Do not attribute the warning to platform graphics, headless devices, or local
   plotting code until both the local path and dependency path have been checked.

Record the exact warning text, local call path, dependency package/helper, and
line or expression that emits the warning.

## Final Validation Bundles

For final cleanup chunks, release-like checks, or package-wide infrastructure
and documentation work, run the broadest feasible bundle and classify notes
against the known baseline:

- full tests: `Rscript -e 'testthat::test_local()'`
- package check:
  `Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"))'`
- formatting: `air format . --check`
- lint:
  `Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'`
- workflow checks when workflows changed: `actionlint` and
  `zizmor .github/workflows`
- pkgdown build when site output, articles, examples, or `_pkgdown.yml` changed.

Inspect generated and temporary output before finalizing:

1. Run `scripts/audit-generated-r-files.sh` when present.
2. If absent, inspect
   `git diff --name-status -- NAMESPACE man docs`, check whether `docs/`
   exists or is tracked, and review generated Rd, NAMESPACE, or pkgdown output.
3. Run `git diff --check`.
4. Confirm no local `*.Rcheck`, temporary pkgdown destination, or other build
   artifact remains in the repo.

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

## Check Notes and Restricted Environments

Codex sandboxes, CI-like containers, and local planning artifacts can produce
notes that are not regressions. Classify and report them once instead of
rediscovering them every run.

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
- top-level planning directories such as `plans` during `R CMD check`, when
  they are active local work artifacts;
- compiler flag notes from local toolchains, such as
  `-mno-omit-leaf-frame-pointer`, when already present before the change.

Do not hide these notes. Record the exact note, explain whether it is believed
to be environmental or known repo state, and say whether the same note was
present before the change. If a note is new, code-specific, or changes package
behavior, treat it as a real finding until proven otherwise.

For `R CMD check` notes caused by local planning directories, record whether the
path is tracked, untracked, or ignored. Do not move or delete active plans only
to silence the note unless the user chooses a different plan location or
`.Rbuildignore` policy.

Do not treat missing or untracked `docs/` output as a package source diff unless
the repo tracks pkgdown output or the user asked to update the site.

## Formatting and Lint

- Air owns R/Rmd formatting: `air format . --check`
- Lintr should not fight Air:
  `Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'`

For test fixtures, use `# fmt: skip` around shape-sensitive matrix/list
fixtures where Air reduces readability.

## GitHub Actions

- Syntax/security checks: `actionlint` and `zizmor .github/workflows`; use
  `uvx zizmor .github/workflows` when `zizmor` is not installed.
- Inspect all `uses:` entries for full-length SHA pins.
- Confirm checkout steps set `persist-credentials: false`.

## Coverage

- `Rscript -e 'covr::package_coverage()'`
- Use `.covrignore` only for intentional exclusions.
