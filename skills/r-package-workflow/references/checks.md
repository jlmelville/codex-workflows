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

For baseline or no-change validation, treat `devtools::run_examples()` as a
potentially mutating command. Check `git status` immediately afterward and
record or revert unrelated metadata churn, especially roxygen maintenance in
`DESCRIPTION` such as `Config/roxygen2/version` changes. When examples need to
be exercised without documentation upkeep, prefer
`devtools::check(document = FALSE, ...)` when it gives enough coverage.

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

For CRAN-published packages or explicit release-prep work, add a separate CRAN
release lane after the development checks:

- CRAN-style local check:
  `Rscript -e 'rcmdcheck::rcmdcheck(args = c("--as-cran", "--no-manual"))'`
- External platform checks such as R-hub and win-builder when submission
  compatibility matters.
- `revdepcheck` when the package has downstream dependencies and the change can
  affect public behavior.

Treat R-hub, win-builder, CRAN metadata, and reverse-dependency results as
remote service state. Report queued, unavailable, or network-blocked checks
separately from local package failures.

Inspect generated and temporary output before finalizing:

1. Run `scripts/audit-generated-r-files.sh` when present.
2. If absent, inspect
   `git diff --name-status -- NAMESPACE man docs`, check whether `docs/`
   exists or is tracked, and review generated Rd, NAMESPACE, or pkgdown output.
3. Run `git diff --check`.
4. Confirm no local `*.Rcheck`, temporary pkgdown destination, or other build
   artifact remains in the repo.

`git diff --check` does not cover files that are still untracked. After
creating new files, run an explicit whitespace check over those paths, such as
`rg -n '[ \t]+$' <new-files>`, or use
`git diff --no-index --check /dev/null <new-file>` for a single file.

## Documentation

- Roxygen refresh: `Rscript -e 'roxygen2::roxygenise()'`
- README/article smoke tests if present.
- pkgdown build when changing `_pkgdown.yml`, articles, examples, or generated
  docs: `Rscript -e 'pkgdown::build_site(new_process = FALSE)'`

After roxygen refreshes, inspect `git diff -- DESCRIPTION` separately and
restore unrelated roxygen metadata churn, such as `RoxygenNote` being replaced
by `Config/roxygen2/version`, unless that modernization is explicitly in scope.

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
- `R CMD build` or `devtools::check()` messages such as
  `Removed empty directory 'pkg/.agents'`, `pkg/.codex`, or `pkg/plans` when
  they refer to temporary build-source cleanup rather than repository files;
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

When a check NOTE reports a bare `as()` as having no visible global definition,
do not assume its import suggestion requires a roxygen `@importFrom`. Follow the
package's namespace style: normally qualify the call as `methods::as(...)` and
declare `methods` in `DESCRIPTION`, unless the package intentionally imports
`as` into its namespace.

For "Removed empty directory" messages, check `git status` before reporting
local deletions. Treat them as package-build temporary-source cleanup unless
the working tree actually changed.

Do not treat missing or untracked `docs/` output as a package source diff unless
the repo tracks pkgdown output or the user asked to update the site.

## Formatting and Lint

- Air CLI owns formatting for supported R source files:
  `air format . --check`.
- Do not treat a clean directory check as proof that embedded R code in `.Rmd`
  or Quarto documents was checked. Confirm mixed-document capabilities against
  the installed Air version and integration.
- Lintr should not fight Air:
  `Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'`

For embedded R code, use an explicitly supported editor integration such as
Quarto-cell or injected-language formatting, or a repository-local helper that
extracts fenced R blocks, formats only the R input, reinserts only block bodies,
and has an exercised check mode. Do not pass an entire Markdown document to
`air format` and interpret a parse failure as a formatting result.

When Air CI fails, inspect the workflow and `air.toml` before editing, confirm
the local `air --version` matches CI when the workflow pins Air, then run
`air format .` followed by `air format . --check`. Report the changed files and
diff scope; even roxygen trailing whitespace can be the whole failure.

For scoped formatting work, format the intended scope first and confirm it with
a scoped check, such as `air format tests/testthat --check` for test cleanup.
Then finish with `air format . --check`. If the repo-wide check reports
additional non-generated `R/` files, review a temporary-copy Air diff before
applying the formatting. Do not let formatting sweeps touch generated files
such as `R/RcppExports.R`, `src/RcppExports.cpp`, `NAMESPACE`, `man/*.Rd`, or
pkgdown output unless those files are intentionally being regenerated.

When changing `.lintr` policy in an Air-formatted repo, trial candidate linters
without editing the config first. During discovery, isolate the trial from
inherited user or local config by using explicit linters and
`parse_settings = FALSE`:

```sh
Rscript -e 'linters <- lintr::linters_with_defaults(line_length_linter = NULL, object_usage_linter = NULL); lints <- lintr::lint_package(linters = linters, parse_settings = FALSE); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'
```

Enable only rules that stay low-noise on the real package. Treat
`object_usage_linter` and `line_length_linter` as high-risk in same-package
work until proven otherwise: `object_usage_linter` can flag local/test helpers
as missing globals, and Air-clean code can still exceed lintr's default line
length rule.

When `object_usage_linter` flags ordinary functions defined elsewhere in the
same package, confirm that linting sees the current package namespace before
adding suppressions. Call `pkgload::load_all(quiet = TRUE)` in the same R
process before `lint_package()`, or install the current source into a temporary
library and put that library first. A stale installed namespace can omit new
helpers or global declarations. Reserve `utils::globalVariables()` for genuine
NSE or data-mask symbols; registering ordinary helper functions can conceal
real misspellings.

After editing `.lintr`, rerun both `air format . --check` and
`lintr::lint_package()` from the saved config with normal settings parsing.
Keep multi-line `.lintr` values as valid DCF: continuation lines, including
closing parentheses for R expressions, must stay indented rather than starting
at column 1.

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
