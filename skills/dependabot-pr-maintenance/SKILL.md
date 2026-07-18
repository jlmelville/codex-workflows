---
name: dependabot-pr-maintenance
description: Review, validate, update, and merge Dependabot or Renovate dependency PRs. Use for automated dependency updates, GitHub Actions SHA pins, stale bot branches, dirty-worktree or temp-merge validation, red-check triage, generated comment or lockfile fixes, batch PRs, and expected-head merges.
---

# Dependabot PR Maintenance

Use this for automated dependency update pull requests.

## Triage

1. Confirm the PR author is the dependency bot and the target repository is
   correct.
2. Inspect the title, dependency name, old version, new version, update type,
   changed files, and PR body.
3. Read the exact patch. Do not rely only on the PR title.
4. Identify whether the update is patch, minor, major, security, or tooling
   metadata.
5. Check whether the branch is behind `main` and whether the displayed diff is a
   direct branch comparison rather than the true merge result.

## Conditional Workflows

- For Renovate Dependency Dashboard, compatibility-island, or configuration
  work, read [renovate.md](references/renovate.md).
- For SHA-pinned GitHub Actions updates, stale red checks, patch-based combined
  validation, or batch merges, read
  [pinned-actions-and-stale-ci.md](references/pinned-actions-and-stale-ci.md).

## Safety Checks

- For GitHub Actions, confirm the new ref is still a full-length SHA, nearby
  comments match the updated human-readable version, and the SHA matches the
  advertised upstream tag when the PR claims a tag or version.
- For lockfiles, confirm dependency graph changes match the PR description.
- For major updates, check runtime requirements and breaking changes before
  merging.
- For security updates, prioritize validation but still inspect the patch.
- For generated bot branches that predate recent main changes, preview or test
  the merge result before merging.
- If the local worktree is dirty or on unrelated work, validate patches in a
  temporary clone or worktree under `/tmp` instead of touching user changes.

## Validation

Use GitHub check status first, then run local checks when the repository is
available locally:

```sh
gh pr checks <number> --repo owner/repo
gh pr diff <number> --repo owner/repo --patch
```

If a `gh` command fails with sandboxed DNS or network errors, rerun the same
command with network approval and a narrow `gh pr ...` prefix rule. Treat that
as an environment retry, not as evidence that the PR or authentication is bad.

For scripted `gh pr view --json` checks, prefer portable fields:
`state`, `mergedAt`, `mergeCommit`, `headRefOid`, `mergeable`, and
`mergeStateStatus`. Avoid relying on a `merged` field; older `gh` versions may
not expose it.

## Updating The PR

Make the smallest possible correction on the PR branch when the bot update is
right but local metadata is stale, such as an inline version comment beside a
pinned SHA.

Do not rewrite broad bot-generated changes by hand. If the branch is conflicted
or badly stale, prefer asking Dependabot to rebase or recreate unless a narrow
manual fix is clearly safer.

## Merge

1. Re-read PR state immediately before merging, including head SHA, mergeable
   state, base branch, check status, and whether the branch is already merged.
2. Confirm the head SHA matches the commit that was validated. If it changed,
   restart validation.
3. Merge only when required checks pass, or when failed checks have been
   classified and accepted according to repository policy.
4. Use an expected head SHA so the merge fails if the branch moves, for example:

   ```sh
   gh pr merge <number> --repo owner/repo --squash --match-head-commit <sha>
   ```

   Add `--delete-branch` when the user or repository policy requests branch
   deletion. Use `--merge` or `--rebase` only when that matches repository
   convention.
5. If `gh pr merge` fails with a sandboxed network or API connection error,
   re-read PR state first. If it did not merge, rerun the same merge command
   with network approval.
6. Confirm the PR is merged, record the merge commit or resulting commit SHA,
   and verify branch deletion when requested.
7. Fetch the remote base branch after merging without disturbing local changes.
   Avoid `git pull` or checkout changes when the worktree is dirty.

## Report

Summarize the dependency, version change, files changed, checks observed, merge
commit, and any local follow-up. Mention if CLI authentication or network
approval affected inspection.
