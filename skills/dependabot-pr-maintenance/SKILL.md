---
name: dependabot-pr-maintenance
description: Review, validate, update, and merge Dependabot or Renovate dependency pull requests, especially GitHub Actions SHA pin updates, stale-base bot branches, dirty-worktree or temp-merge validation, red-check triage, verified or batch PR merges, and package version bumps. Use when Codex is asked to inspect an automated dependency PR, decide whether it is safe, handle stale generated changes, update comments or lockfiles, wait for checks, or merge with expected head SHA.
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

## Pinned Actions PR Audit

For GitHub Actions PRs that update SHA-pinned `uses:` entries:

1. Confirm bot author, patch scope, changed workflow files, and nearby version
   comments.
2. Verify updated refs remain full-length SHAs.
3. Check each new SHA against the advertised upstream tag or tags with
   `git ls-remote`.
4. Compare the PR base with the current remote base branch; validate the state
   that would actually be merged, not only the displayed PR diff.
5. Apply the PR patch to a clean temporary checkout when the local worktree is
   dirty or the PR branch is stale.
6. Run workflow linters on the patched or merged state.
7. For a batch of narrow action-update PRs, test each PR individually and then
   test the combined merge result in `/tmp` before recommending merge order.
8. Report a merge-safety summary that separates patch safety, stale CI state,
   missing network/tool validation, and local dirty-worktree constraints.

For workflow dependency PRs, run the repository's workflow audit on the merged
or current workflow state when possible:

```sh
actionlint
zizmor .github/workflows  # or uvx zizmor .github/workflows when not installed
```

If checks are still running, wait for completion before merging.

## Failed Check Triage

For a red check on a narrow bot PR:

1. Inspect the failing log enough to identify the file, line, command, and
   failure class.
2. Compare the failure location with the PR patch. If the failed line or command
   is untouched, treat it as unrelated until proven otherwise.
3. Compare the same location against current remote `main`; stale bot bases can
   fail on code that has already been fixed.
4. If the PR merges cleanly into current `main` and the merged state passes the
   relevant local checks, classify the original failure as stale CI and
   recommend rebase, rerun, or merge according to repository policy.
5. Do not change unrelated product or language code on a dependency bot branch
   merely to make a stale-base check green.

Separate conclusions clearly:

- `unsafe patch`: the dependency update changes risky behavior or fails on the
  merged state.
- `stale CI failure`: the bot branch failed because its base or check run was
  old, while the patch and current merge result are acceptable.
- `inconclusive`: validation could not inspect logs, fetch upstream refs, or
  run the relevant checks.

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

## Batch Merge

When merging multiple bot PRs, especially overlapping Dependabot action PRs,
repeat the verified merge loop for each PR:

1. Re-read the PR with portable JSON fields and confirm bot author, target repo,
   base branch, head SHA, check state, and mergeability.
2. If mergeability is `UNKNOWN`, wait briefly and re-read. GitHub may report
   `UNKNOWN` immediately after a preceding merge while it recomputes the next
   PR's merge result.
3. Confirm the head SHA is unchanged from validation and use
   `--match-head-commit` on every merge.
4. Merge with the repository's strategy and `--delete-branch` when requested.
5. Confirm merged state, merge commit, and branch deletion before moving to the
   next PR.
6. After each merge, fetch the remote base branch without disturbing local
   changes, then re-read the remaining PRs because mergeability and checks may
   have changed.

## Report

Summarize the dependency, version change, files changed, checks observed, merge
commit, and any local follow-up. Mention if CLI authentication or network
approval affected inspection.
