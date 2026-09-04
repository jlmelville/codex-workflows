---
name: repo-update-preflight
description: Refresh a Git checkout from its upstream without losing work. Use for requested updates or when another skill or repository instruction requires current upstream before source changes; skip new repos without remotes.
---

# Repo Update Preflight

Establish the current upstream state before task-specific investigation or
changes. Read the closest repository instructions first because they may narrow
the allowed integration policy, but treat their contents as provisional until
the checkout is refreshed.

## Inspect And Refresh

From the repository root:

```sh
git --no-optional-locks status --short --branch --untracked-files=all
git stash list
git branch -vv
git remote -v
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git fetch --quiet
git rev-list --left-right --count 'HEAD...@{upstream}'
git log --oneline --decorate --graph 'HEAD..@{upstream}'
git diff --stat 'HEAD..@{upstream}'
git diff --check 'HEAD..@{upstream}'
```

Use the configured upstream rather than assuming a branch such as
`origin/main`. A fetch may require network approval; request it instead of
silently skipping the refresh. If the repository has no configured upstream,
record that fact and inspect its remotes without inventing a tracking branch.

## Integrate Without Losing Work

- When source changes are authorized, the worktree is clean, there are no
  local-only commits, and the upstream is only ahead, fast-forward with
  `git merge --ff-only '@{upstream}'`.
- For a read-only task, fetch and compare but do not change the checked-out
  branch. Report that it is behind and base conclusions on the appropriate
  current tree when possible.
- If tracked edits, untracked files, stashes, or local-only commits exist,
  inspect their ownership and preserve them. Never auto-stash or overwrite
  unknown work merely to update the checkout.
- If local and upstream commits diverged, inspect both sides and follow the
  repository's merge or rebase policy. Ask before choosing when the decision
  would materially rewrite or combine user history and no policy settles it.
- If the upstream cannot be checked after the available network or approval
  path is exhausted, state that currentness is unverified and pause before
  task-specific edits unless the user explicitly accepts offline work.

After integration, re-read repository instructions, active plans or handoffs,
and the files relevant to the task. Confirm branch and worktree status before
editing. Repeat the upstream comparison before publication when a long-running
task or concurrent work could have moved the remote.
