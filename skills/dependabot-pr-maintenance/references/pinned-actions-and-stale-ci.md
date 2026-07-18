# Pinned Actions And Stale CI

Use this reference for GitHub Actions dependency PRs, stale failures, combined
patch validation, and batch merges.

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

If a clean checkout cannot fetch PR refs because inherited Git URL rewriting or
local SSH configuration routes the remote through an unusable transport,
materialize each already-reviewed patch with `gh pr diff <number> --patch` and
apply the patches sequentially with `git apply --3way`. Confirm every patch
applies cleanly, the combined diff contains every expected pin, and the final
state passes the workflow validators. Writing patch files with shell
redirection may require separate network approval when the redirection prevents
an existing `gh pr diff` prefix rule from matching.

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
6. For the PR just merged, treat direct
   `gh pr view <number> --json state,mergedAt,mergeCommit` as the source of
   truth. If `gh pr list --state open` still shows it, wait and re-read before
   retrying the merge or reporting an inconsistency.
7. After each merge, fetch the remote base branch without disturbing local
   changes, then re-read the remaining PRs because mergeability and checks may
   have changed.
