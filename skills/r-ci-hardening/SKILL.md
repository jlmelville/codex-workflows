---
name: r-ci-hardening
description: Configure or review R-specific GitHub Actions behavior for package checks, optional dependencies, coverage, and pkgdown deployment. Complements the shared workflow-hardening skill.
---

# R CI Hardening

Use this with `$github-actions-hardening` when working on GitHub Actions or
CI-related infrastructure in an R package. The generic skill owns shared action
pinning, permissions, checkout credentials, concurrency, Dependabot, and audit
tool behavior. This skill owns R-specific workflow semantics.

## Use A More Specific Skill When

- Use `$dependabot-pr-maintenance` for automated dependency PR review, stale
  branch validation, or merge decisions.
- Use `$repo-bootstrap` when creating first-pass CI for a new repository before
  R-specific hardening starts.

## R Workflow Rules

1. Treat `usethis` workflow output as scaffolding, not final hardening.
2. Keep `r-lib/actions` setup and check inputs aligned with the package's
   dependency, vignette, and release policy.
3. Separate optional-dependency lanes so an intentionally unavailable
   suggestion does not hide coverage of every other optional path.
4. Treat external-source health checks as scheduled or manually strict service
   probes, not as package-regression evidence in ordinary pull requests.

See [github-actions.md](references/github-actions.md) for patterns.

## Legacy CI Retirement

Retire a hosted CI provider from the outside in. Disable push and pull-request
triggers, or delete the provider project, before pushing the cleanup commit.
Then remove repository configuration, ignore entries, badges, and current
release claims. Verify the active replacement checks and branch-protection
expectations before removing a required legacy context. After the push, confirm
that the retired provider emitted no fresh build or status when practical;
historical contexts on old commits are not current activity.

## Pkgdown Deploy Pattern

Prefer a two-job workflow:

- `build-site`: read-only, builds docs, uploads `docs` as an artifact.
- `deploy-site`: non-PR only, depends on `build-site`, has `contents: write`,
  downloads the artifact, pushes to `gh-pages`.

This avoids giving write credentials to dependency installation and site build
steps.

## Required Checks

After workflow changes, run the complete
[generic workflow checks](../github-actions-hardening/SKILL.md#checks). That
skill owns the audit command, actionlint and zizmor behavior, SHA pinning,
checkout credentials, nearby pin comments, and optional remote tag
verification. Add the R-specific hosted or semantic checks from
[github-actions.md](references/github-actions.md) that apply to the change.
