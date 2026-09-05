# R Package Check Selection

Use the smallest check set that exercises the changed contract, plus explicit
repository gates. Broaden when touching shared behavior, generated files,
infrastructure, or compiled code. A scoped prose correction normally needs
source, link, and relevant render checks; it does not itself require full
package tests. A passing check on unchanged inputs need not be repeated unless
new changes, failures, or unresolved concerns invalidate that evidence.

## R Behavior

- Focused test file: `Rscript -e 'testthat::test_local(filter = "pattern")'`
- Focused package-style test file:
  `Rscript -e 'pkgload::load_all(); testthat::test_file("tests/testthat/test-name.R")'`
- Full tests: `Rscript -e 'testthat::test_local()'`
- Full package check: `Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"), error_on = "note")'`

Before running a single `tests/testthat/test-*.R` file directly, inspect
`tests/testthat.R`. If the suite loads the package before running tests, use
`pkgload::load_all()` before `testthat::test_file()`. A bare `test_file()`
failure such as "could not find function" may be a harness failure, not package
behavior, when no package code was loaded.

Run full tests after changes to exported behavior, validation, data conversion,
cross-module helpers, or test fixtures used by multiple files.

## Stochastic And Threaded Reproducibility

When reviewing or documenting an exported stochastic or approximate operation,
identify which layer owns the seed and exercise a bounded matrix:

- repeat the same seed with the same thread count;
- change the seed while holding other inputs fixed;
- repeat at one thread and at a supported multi-thread count; and
- exercise a precomputed or saved-intermediate route when one exists.

Compare the user-relevant result with the exactness or tolerance appropriate to
its contract. Document the backend and the precise seed and thread conditions
under which reproducibility was observed; do not generalize one environment's
result into an unconditional cross-platform guarantee. When threaded execution
is nondeterministic, give users a deterministic execution mode or a persisted
intermediate strategy when durable reproduction matters.

## Dependency Attachment Changes

When moving a runtime dependency from `Depends` to `Imports`, validate the
installed search-path contract in a fresh library and a separate
`Rscript --vanilla` process. Check attachment, namespace loading,
package-internal calls, qualified method dispatch, and representative
unqualified user calls as distinct surfaces. Do not use `load_all()` or a
development session where the dependency may already be attached as evidence.

For returned `Matrix` S4 objects, obtain an object from the installed package,
assert that `package:Matrix` is absent from `search()` while its namespace is
loaded, and exercise display, group operations, multiplication, subsetting,
conversion, and Matrix-qualified generics such as `Matrix::t()` or
`Matrix::rowSums()`. An unqualified base generic can select a default method
when Matrix is not attached even though registered Matrix behavior remains
healthy; decide explicitly whether that user-visible change is intended.

## Reference Metadata Applicability

When a scientific factory returns stored reference metadata or its accepted
dimension/configuration domain changes:

1. Search executable consumers before adding, removing, or normalizing fields.
2. Inventory value and location fields such as `fmin` and `xmin` separately.
   Distinguish the factory's accepted domain, a formula's mathematical scope,
   and the configuration represented by each stored literal.
3. Test the smallest valid and exceptional boundary classes plus the stored
   reference configuration through the relevant callbacks. A passing stored
   example does not establish an all-dimensions or all-configurations claim.
4. Check that metadata and documentation state field applicability accurately,
   including empty-index or degenerate branches admitted by a widened contract.
5. When an adapter exposes applicability, represent documented applicability,
   known inapplicability, and an unestablished rule separately. In R, use
   `TRUE`, `FALSE`, and `NA` respectively, and retain a compact evidence-basis
   field such as fixed configuration, documented dimension rule, mismatch,
   missing reference, or unencoded rule. Compatible vector length proves shape,
   not reference validity.

For baseline or no-change validation, treat `devtools::run_examples()` as a
potentially mutating command. Check `git status` immediately afterward and
record or revert unrelated metadata churn, especially roxygen maintenance in
`DESCRIPTION` such as `Config/roxygen2/version` changes. When examples need to
be exercised without documentation upkeep, prefer
`devtools::check(document = FALSE, ...)` when it gives enough coverage.

## Focused Documentation And Compiled Checks

Use `$r-docs-pkgdown` for roxygen, README, article, vignette, and pkgdown
validation. Its routed
[documentation-validation reference](../../r-docs-pkgdown/references/validation.md)
owns fresh-session checks and the restricted temporary-library install recipe.

When CI intentionally skips vignette building, use the two-layer `rcmdcheck`
contract in `$r-ci-hardening`; workflow build and check arguments have different
owners. Use `$r-rcpp-package` for attribute regeneration, generated-wrapper
review, compiled checks, and C++ formatting boundaries.

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

For package-wide cleanup, release-like checks, or package-wide infrastructure
and documentation work, run this bundle, adding applicable repository gates.
Require 0 errors, 0 warnings, and 0 repository-attributable notes before claiming
a clean package check. A known baseline establishes attribution; it does not
make a failing gate pass. Repair failures within the accepted scope and report
unrelated diagnostics and their effect on completion:

- full tests: `Rscript -e 'testthat::test_local()'`
- package check:
  `Rscript -e 'devtools::check(document = FALSE, args = c("--no-manual"), error_on = "note")'`
- formatting: `air format . --check`
- lint:
  `Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'`
- complete [workflow audit](../../github-actions-hardening/SKILL.md#checks) from
  `$github-actions-hardening` when workflows changed;
- pkgdown build when site output, articles, examples, or `_pkgdown.yml` changed.

For CRAN packages or release preparation, follow the routed
[release lifecycle](release.md) after development checks. It owns candidate
identity, release validation, submission, acceptance, and return to development.

Inspect generated and temporary output before finalizing:

1. Run
   `${HOME}/.agents/skills/r-package-workflow/scripts/audit-generated-r-files.sh`
   when the installed skill is available.
2. Otherwise inspect
   `git diff --name-status -- NAMESPACE man docs`, check whether `docs/`
   exists or is tracked, and review generated Rd, NAMESPACE, or pkgdown output.
3. Run `git diff --check`.
4. Confirm no local `*.Rcheck`, temporary pkgdown destination, or other build
   artifact remains in the repo.

`git diff --check` does not cover files that are still untracked. After
creating new files, run an explicit whitespace check over those paths, such as
`rg -n '[ \t]+$' <new-files>`, or use
`git diff --no-index --check /dev/null <new-file>` for a single file.

## Restricted Environment Mechanics

Apply the diagnostic-ownership rule in `SKILL.md` before interpreting sandbox,
CI-container, or external-service output. Preserve these exact recipes:

- When R tooling needs caches in a restricted filesystem, redirect them to a
  writable temporary path such as `XDG_CACHE_HOME=/tmp/r-cache`.
- When material pkgdown or package-check validation fails because DNS, CRAN
  metadata, or external assets are blocked, rerun through the applicable
  network-approval path before assigning the failure to package behavior.
- When an otherwise clean check reports that it cannot verify current time, or
  a bad-clock NOTE has been attributed to a stale external time source using
  the clock witnesses in the casebook, rerun only that check with remote clock
  verification disabled:

  ```r
  withr::with_envvar(
    c("_R_CHECK_SYSTEM_CLOCK_" = "FALSE"),
    devtools::check(document = FALSE, args = c("--no-manual"), error_on = "note")
  )
  ```

  Retain every other check setting, disclose the initial diagnostic and clean
  rerun, and continue to fail genuine future-timestamp findings.

If ownership remains ambiguous after the relevant rerun and attribution
checks, consult the optional
[check diagnostic cases](check-diagnostic-cases.md). The casebook distinguishes
observation boundaries; it is not an additional default checklist.

## Formatting and Lint

- Air owns supported R formatting: `air format . --check`.
- Lintr should complement Air:
  `Rscript -e 'lints <- lintr::lint_package(); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'`

A clean directory check does not prove embedded R in Markdown or Quarto was
formatted. Use a supported cell or injected-language integration, or an
exercised helper that extracts and reinserts only R block bodies. Do not pass a
whole Markdown document to Air and call its parse failure a format result.

When Air CI fails, inspect the workflow and config, compare local and pinned
versions, then run `air format .` and `air format . --check` and report the diff
scope. Treat a version mismatch as an upgrade decision: trial the newer version
on a temporary copy; if its diff is accepted, update the explicit CI pin and
local tool together, otherwise use the pinned version and report the mismatch.

For scoped work, format and check the intended paths before the repository-wide
check. Review unexpected non-generated `R/` changes on a temporary copy. Exclude
generated bindings, `NAMESPACE`, `man/*.Rd`, and pkgdown output unless their
generator is intentionally running.

When changing `.lintr` policy in an Air-formatted repo, trial candidate linters
without editing the config first. During discovery, isolate the trial from
inherited user or local config by using explicit linters and
`parse_settings = FALSE`:

```sh
Rscript -e 'linters <- lintr::linters_with_defaults(line_length_linter = NULL, object_usage_linter = NULL); lints <- lintr::lint_package(linters = linters, parse_settings = FALSE); print(lints); quit(status = if (length(lints) > 0) 1L else 0L)'
```

Enable only rules that stay low-noise on the real package. Treat
`object_usage_linter` and `line_length_linter` as high-risk in same-package
work until proven otherwise.

When `object_usage_linter` flags ordinary functions defined elsewhere in the
same package, load the current source in that process or install it into a
temporary first library before adding suppressions. Reserve
`utils::globalVariables()` for genuine NSE or data-mask symbols.

After editing `.lintr`, rerun both `air format . --check` and
`lintr::lint_package()` from the saved config with normal settings parsing.
Keep multi-line `.lintr` continuations indented as valid DCF. Use `# fmt: skip`
only for shape-sensitive fixtures where Air reduces readability.
