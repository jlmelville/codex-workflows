---
name: r-ci-hardening
description: Harden and maintain R package GitHub Actions, pkgdown deploys, coverage workflows, Dependabot, actionlint, and zizmor. Use when Codex touches .github/workflows, .github/dependabot.yml, pkgdown Pages deploys, codecov, CI permissions, action pins, workflow security, or usethis CI files.
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

## Pkgdown Deploy Pattern

Prefer a two-job workflow:

- `build-site`: read-only, builds docs, uploads `docs` as an artifact.
- `deploy-site`: non-PR only, depends on `build-site`, has `contents: write`,
  downloads the artifact, pushes to `gh-pages`.

This avoids giving write credentials to dependency installation and site build
steps.

## Required Checks

Run after workflow changes:

```sh
${HOME}/.agents/skills/github-actions-hardening/scripts/audit-actions.sh .github/workflows
```

The generic audit owns actionlint, zizmor fallback behavior, SHA pinning,
checkout credentials, and nearby pin comments. From the `codex-workflows`
source repository, run
`./skills/github-actions-hardening/scripts/audit-actions.sh .github/workflows`.

For rare reviews that need to confirm nearby version tags against full-SHA pins,
use
`${HOME}/.agents/skills/github-actions-hardening/scripts/check-action-tag-comments.sh`;
its `--verify-remote` mode uses `git ls-remote` and may need network approval.
