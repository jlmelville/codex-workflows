---
name: github-actions-hardening
description: Configure or audit GitHub Actions security and validation, including action pins, credentials, permissions, and Dependabot configuration.
---

# GitHub Actions Hardening

Use this for shared GitHub Actions policy and audit tooling. Combine it with a
more specific language or package skill when one applies.

## Use A More Specific Skill When

- For workflows in R package repositories, also apply `$r-ci-hardening` as the
  R-specific overlay on the shared rules and audit tooling here.
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
9. For privileged triggers such as `issue_comment`, `pull_request_target`, or
   `workflow_run`, treat PR heads and their artifacts as untrusted. Do not
   execute them with secrets, write permissions, or persisted credentials. If a
   trusted same-repository branch must be updated, verify its provenance, bind
   analysis to the approved immutable head SHA, and use a separate privileged
   write-back job with an expected-head guard.

## Review Procedure

1. Inspect the workflow diff and any generated scaffolding before editing.
2. Check every `uses:` line for SHA pins and stale nearby version comments.
3. Confirm job and top-level `permissions` are as narrow as practical.
4. Confirm checkout credential handling is per-step, not just somewhere in the
   file.
5. Confirm PR events cannot write to protected branches, publish artifacts as
   releases, or deploy sites.
6. For privileged events acting on a PR, trace the checked-out revision, code
   execution, credentials, artifacts, and write-back boundary as one path.
7. Run the checks below.

## Checks

Use this skill's bundled audit script as the canonical workflow check. It runs
`actionlint`, `zizmor` with its supported fallback, the action-pin comment
check, and the checkout-credential check:
The checkout check covers only direct workflow steps; when a pinned composite action performs or may perform checkout, inspect its pinned source or replace the wrapper with an explicit checkout before claiming the credential boundary is satisfied.

```sh
${HOME}/.agents/skills/github-actions-hardening/scripts/audit-actions.sh --quiet .github/workflows
```

From this source repository root, the same script is under:

```sh
./skills/github-actions-hardening/scripts/audit-actions.sh --quiet .github/workflows
```

Run ShellCheck separately for repository shell scripts when applicable:

```sh
shellcheck path/to/scripts/*.sh
```

The audit script runs the tag comment checker in offline `--require-comment`
mode, so every full-SHA pin needs a nearby version or reason comment. When a
review specifically needs to confirm that nearby version comments still match
full-SHA pins, use `--require-tag`; `--verify-remote` uses `git ls-remote` and
may need network approval:

```sh
${HOME}/.agents/skills/github-actions-hardening/scripts/check-action-tag-comments.sh --quiet --require-tag .github/workflows
${HOME}/.agents/skills/github-actions-hardening/scripts/check-action-tag-comments.sh --quiet --require-tag --verify-remote .github/workflows
```

The tag-comment checker also accepts one `.yml` or `.yaml` workflow file. Use a
file target when a new workflow must remain isolated and untracked. Ordinary
`git diff --check` ignores untracked files; inspect
`git diff --no-index --check /dev/null <workflow-file>` as a focused whitespace
check. A silent exit status of 1 is expected when the file differs from
`/dev/null`; reported whitespace errors are the failure signal.

Treat tool failures from network or missing dependencies separately from
workflow findings, and rerun after installing or approving the needed tool.
Prefer an installed `zizmor` when present; use `uvx --quiet --no-progress zizmor` as the fallback.

## CI Triage Fallback

When `gh auth status` reports invalid credentials in a network-restricted Codex
environment, first confirm that the expected CLI configuration is present and
that no environment-token override is intentionally active. Rerun the same
read-only status check through the narrow network-approval path before
concluding that GitHub rejected the credential. Request reauthentication only
after that networked check fails.

When authenticated access is genuinely unavailable but the repository is
public, use public Actions run/job metadata and public job-page annotations as
a fallback. Be explicit that authenticated raw logs may remain unavailable; do
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
