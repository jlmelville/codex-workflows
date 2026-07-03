---
name: dependabot-pr-maintenance
description: Review, validate, update, and merge Dependabot or Renovate dependency pull requests, especially GitHub Actions SHA pin updates and package version bumps. Use when Codex is asked to inspect an automated dependency PR, decide whether it is safe, handle stale generated changes, update comments or lockfiles, wait for checks, or merge with expected head SHA.
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

## Safety Checks

- For GitHub Actions, confirm the new ref is still a full-length SHA and nearby
  comments match the updated human-readable version.
- For lockfiles, confirm dependency graph changes match the PR description.
- For major updates, check runtime requirements and breaking changes before
  merging.
- For security updates, prioritize validation but still inspect the patch.
- For generated bot branches that predate recent main changes, preview or test
  the merge result before merging.

## Validation

Use GitHub check status first, then run local checks when the repository is
available locally:

```sh
gh pr checks <number> --repo owner/repo
gh pr diff <number> --repo owner/repo --patch
```

For workflow dependency PRs, run the repository's workflow audit on the merged
or current workflow state when possible:

```sh
actionlint
uvx zizmor .github/workflows
```

If checks are still running, wait for completion before merging.

## Updating The PR

Make the smallest possible correction on the PR branch when the bot update is
right but local metadata is stale, such as an inline version comment beside a
pinned SHA.

Do not rewrite broad bot-generated changes by hand. If the branch is conflicted
or badly stale, prefer asking Dependabot to rebase or recreate unless a narrow
manual fix is clearly safer.

## Merge

1. Re-check PR state after any push to the branch.
2. Merge only when required checks pass and the patch is understood.
3. Use an expected head SHA when the tool supports it so the merge fails if the
   branch moves.
4. Prefer squash merge for routine dependency updates unless the repository has
   a different convention.
5. Pull or fetch `main` after merging and confirm the local checkout is clean.

## Report

Summarize the dependency, version change, files changed, checks observed, merge
commit, and any local follow-up. Mention if CLI authentication or network
approval affected inspection.
