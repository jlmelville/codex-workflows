---
name: github-actions-hardening
description: Harden and maintain GitHub Actions workflows in any repository, including action SHA pinning, permissions, checkout credentials, Dependabot updates, concurrency, actionlint, zizmor, ShellCheck, and safe pull_request behavior. Use when Codex edits, reviews, audits, or debugs .github/workflows or .github/dependabot.yml outside a more specific ecosystem skill.
---

# GitHub Actions Hardening

Use this for GitHub Actions infrastructure that is not covered by a more
specific language or package skill.

## Use A More Specific Skill When

- Use `$r-ci-hardening` for workflows in R package repositories.
- Use `$dependabot-pr-maintenance` for automated dependency PR review or merge
  decisions.
- Use `$repo-bootstrap` when creating first-pass CI for a new repository.

## Workflow Rules

1. Pin third-party `uses:` entries to full-length commit SHAs.
2. Keep a nearby comment naming the human-readable action version or reason for
   the pin, and update it with the SHA.
3. Set top-level permissions to read-only unless the workflow requires more:

```yaml
permissions:
  contents: read
```

4. Put write permissions only on the narrow job that publishes, deploys, or
   comments.
5. Set `persist-credentials: false` on every `actions/checkout` step unless a
   later step intentionally uses the checkout token.
6. Use concurrency for expensive workflows and deploy workflows.
7. Keep pull request workflows build-only; do not deploy or publish from
   untrusted PR code.
8. Keep Dependabot configured for `github-actions`.

## Review Procedure

1. Inspect the workflow diff and any generated scaffolding before editing.
2. Check every `uses:` line for SHA pins and stale nearby version comments.
3. Confirm job and top-level `permissions` are as narrow as practical.
4. Confirm checkout credential handling is per-step, not just somewhere in the
   file.
5. Confirm PR events cannot write to protected branches, publish artifacts as
   releases, or deploy sites.
6. Run the checks below.

## Checks

Run the checks that exist in the repository:

```sh
actionlint
zizmor .github/workflows  # or uvx zizmor .github/workflows when not installed
shellcheck path/to/scripts/*.sh
```

Use this skill's bundled audit script when available:

```sh
scripts/audit-actions.sh .github/workflows
```

From a skill repository root, the same script may be under:

```sh
./skills/github-actions-hardening/scripts/audit-actions.sh .github/workflows
```

The audit script runs the tag comment checker in offline `--require-comment`
mode, so every full-SHA pin needs a nearby version or reason comment. When a
review specifically needs to confirm that nearby version comments still match
full-SHA pins, use `--require-tag`; `--verify-remote` uses `git ls-remote` and
may need network approval:

```sh
./skills/github-actions-hardening/scripts/check-action-tag-comments.sh --require-tag .github/workflows
./skills/github-actions-hardening/scripts/check-action-tag-comments.sh --require-tag --verify-remote .github/workflows
```

Treat tool failures from network or missing dependencies separately from
workflow findings, and rerun after installing or approving the needed tool.
Prefer an installed `zizmor` when present; use `uvx zizmor` as the fallback.

## CI Triage Fallback

When `gh auth status` is invalid in the Codex environment but the repository is
public, use public Actions run/job metadata and public job-page annotations as a
fallback. Be explicit that authenticated raw logs may remain unavailable; do
not claim certainty beyond the visible annotations and status metadata.

## Dependabot

Use a minimal Dependabot configuration for GitHub Actions unless the repository
already has stricter conventions:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

Review Dependabot PRs with `$dependabot-pr-maintenance`.

## Merge Safety

For action update PRs, inspect the merge result against current `main`, not just
the PR branch diff. A stale dependency branch can appear to remove newer
workflow hardening when compared directly to `main`, even if the actual merge is
clean.
