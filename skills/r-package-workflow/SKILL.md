---
name: r-package-workflow
description: Develop and review R packages with package-specific generated-file, dependency, and validation conventions. Use for package implementation and integration work.
---

# R Package Workflow

Use this for R package implementation and integration. For a focused task,
consult only the package conventions and specialist guidance it needs.

## First Pass

Read applicable repository instructions and inspect the worktree. Apply
`$repo-update-preflight` when the user requests an update or repository policy
requires current upstream. Read `DESCRIPTION` when dependencies or package
tooling matter, then follow the affected source, tests, generated files, and
active plan as needed to resolve the task.

Preserve unrelated user edits. Keep broad formatting separate from behavioral
fixes unless requested; keep required generated output with its source change.

## Change Discipline

- For scientific or multi-author cleanup work, preserve contributed methods,
  mathematical code, historical bridge code, and long-form vignettes unless a
  change fixes an objective bug, resource-safety issue, packaging integration,
  tests, or safe typo. Use wrapper docs/articles for navigation and defer
  structural rewrites to separate tested plans.
- When widening accepted dimensions or configurations, revalidate formulas,
  stored metadata, and documentation that claim broader applicability at every
  newly admitted boundary class. Use the reference-applicability checklist in
  [checks.md](references/checks.md#reference-metadata-applicability).
- For API naming, public validation domains, shared controls, documented
  sentinels, equivalent exported workflows, public diagnostic value, warning
  ownership, or progress-message contracts, read
  [public-api-contracts.md](references/public-api-contracts.md).
- When an exported API forwards `...` to interchangeable backends, follow
  [variadic-backend-controls.md](references/variadic-backend-controls.md) for
  early validation, routing categories, fallback behavior, and public tests.
- For a compiled package, identify the binding toolchain from `LinkingTo`,
  source attributes, and generated-file headers before selecting a generator
  or generated-file workflow. Rcpp and cpp11 use different commands and own
  different outputs.
- Treat these as generated unless intentionally refreshed:
  `R/RcppExports.R`, `src/RcppExports.cpp`, `R/cpp11.R`, `src/cpp11.cpp`,
  `NAMESPACE`, `man/*.Rd`, pkgdown output under `docs/`.
- When introducing top-level hidden development config files such as
  `.air.toml`, `.lintr`, or `.styler.R`, add exact anchored `.Rbuildignore`
  entries in the same phase and confirm the R CMD check hidden-file check is OK.
- When moving runtime dependencies to `Suggests`, guard every execution path
  with `requireNamespace()`, give users a clear install message, document the
  optional requirement, and skip tests that execute the optional path when the
  package is absent.
- After `usethis` modifies infrastructure, re-harden generated files rather
  than accepting templates as final.

## Checks

Select checks using [checks.md](references/checks.md).

When a release check has a large, compiled, or repository-sensitive reverse-
dependency universe, follow [revdepcheck.md](references/revdepcheck.md) before
starting `revdepcheck`. It owns dependency preparation, external staging, and
the exact runner-path preflight.

For scoped source or test changes, run the affected behavior checks and
configured formatting and lint checks at the relevant scope. Broaden for shared
behavior, package integration, or explicit repository gates. Use the
[final validation bundle](references/checks.md#final-validation-bundles) for
package-wide cleanup, infrastructure or documentation work, and release checks.

Fix failures caused by the change and diagnostics within the accepted task.
Attribute other failures with evidence and report them without silently adding
unrelated repairs. Treat new code-specific or behavior-changing diagnostics as
repository-owned until evidence identifies another owner. Never claim a
required gate passed when it was skipped, unavailable, interrupted, or failed;
report the command, limitation, and remaining validation. An unrelated baseline
failure does not expand scope or make a failing required gate successful.

For ambiguous check ownership, use the exact restricted-environment mechanics
in [checks.md](references/checks.md#restricted-environment-mechanics). Consult
[check-diagnostic-cases.md](references/check-diagnostic-cases.md) only when that
default judgment and the relevant mechanics do not make the next action clear.

For compiled packages, do not run `covr::package_coverage()` and
`testthat::test_local()` concurrently from the same worktree. Sequence them to
avoid transient package DLL copy/load races, and rerun a `dyn.load()` failure
alone before treating it as a code regression.

Scripts:

- `${HOME}/.agents/skills/r-package-workflow/scripts/check-r-package.sh`:
  run a local check bundle, refreshing the one existing Rcpp or cpp11 binding
  family; use `$r-rcpp-package` to initialize or disambiguate bindings.
- `${HOME}/.agents/skills/r-package-workflow/scripts/audit-generated-r-files.sh`:
  list likely generated files touched in the current diff.

For sparse `Matrix` class preservation, exact structural-support contracts, or
slot-level implementation work, use the idioms in
[sparse-matrix.md](references/sparse-matrix.md).

Use a focused skill when its decisions or mechanics are needed for the task.
Mentioning an area or reading one of its files does not require entering its
workflow:

- GitHub Actions, pkgdown deploy, coverage workflows, or Dependabot
  configuration:
  `$r-ci-hardening`.
- Automated dependency PR review, stale-branch validation, or merge decisions:
  `$dependabot-pr-maintenance`.
- Tests, fixtures, and local coverage analysis: `$r-test-hygiene`.
- README, NEWS, roxygen, articles, pkgdown: `$r-docs-pkgdown`.
- Rcpp or cpp11 bridges, compiled code, `src/`, or `Makevars`:
  `$r-rcpp-package`; select its binding-specific branch before generation.
- Performance benchmarks, phased optimization, before/after evidence:
  `$r-performance-workflow`.
- Package-wide modularity, reachability, coupling, or structural cleanup review:
  `$r-architecture-audit`.
