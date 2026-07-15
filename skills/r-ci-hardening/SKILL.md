---
name: r-ci-hardening
description: Harden and maintain R package GitHub Actions, pkgdown deploys, coverage workflows, Dependabot, actionlint, and zizmor. Use when Codex touches .github/workflows, .github/dependabot.yml, pkgdown Pages deploys, codecov, CI permissions, action pins, workflow security, or usethis CI files.
---

# R CI Hardening

Use this when working on GitHub Actions or CI-related package infrastructure.

## Use A More Specific Skill When

- Use `$dependabot-pr-maintenance` for automated dependency PR review, stale
  branch validation, or merge decisions.
- Use `$repo-bootstrap` when creating first-pass CI for a new repository before
  R-specific hardening starts.

## Workflow Rules

1. Treat `usethis` workflow output as scaffolding, not final hardening.
2. Pin every third-party action to a full-length commit SHA.
3. Keep top-level permissions read-only unless a workflow truly needs more:

```yaml
permissions:
  contents: read
```

4. Set `persist-credentials: false` on `actions/checkout`.
5. Grant write permissions only on the narrow job that deploys or publishes.
6. Use concurrency groups for workflows that deploy or consume significant CI.
7. Preserve pull request safety: PR jobs should build and check, not deploy.
8. Keep Dependabot configured for GitHub Actions updates.

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
actionlint
zizmor .github/workflows  # or uvx zizmor .github/workflows when not installed
${CODEX_HOME:-$HOME/.codex}/skills/r-ci-hardening/scripts/audit-actions.sh .github/workflows
```

Use the bundled `audit-actions.sh` from this skill when available. It prefers an
installed `zizmor`, falls back to `uvx zizmor`, and treats uvx network/download
failures as environment issues rather than workflow findings. It also runs an
offline nearby-comment check for full-SHA action pins. From this source
repository, the same helper is available at
`skills/r-ci-hardening/scripts/audit-actions.sh`.

For rare reviews that need to confirm nearby version tags against full-SHA pins,
use
`${CODEX_HOME:-$HOME/.codex}/skills/github-actions-hardening/scripts/check-action-tag-comments.sh`;
its `--verify-remote` mode uses `git ls-remote` and may need network approval.
