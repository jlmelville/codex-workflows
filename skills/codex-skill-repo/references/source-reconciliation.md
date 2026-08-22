# Shared-Checkout Source Reconciliation

Use this before source-changing maintenance in a repository that may receive
changes from another machine. The goal is to establish the actual source state
without discarding local work or letting an old checkout interpret newer
machine-local data.

## Establish The Evidence

Read the current repository instructions and active local plan first, but treat
them as provisional until upstream is refreshed. Record the current branch and
commit, then inspect all local work and recovery surfaces:

```sh
git --no-optional-locks status --short --branch --untracked-files=all
git stash list
git branch -vv
git remote -v
```

Fetch the configured upstream without changing the worktree. Use Git's upstream
configuration rather than assuming `origin/main` in a generic repository:

```sh
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git fetch
git rev-list --left-right --count 'HEAD...@{upstream}'
git log --oneline --decorate --graph 'HEAD..@{upstream}'
git diff --stat 'HEAD..@{upstream}'
git diff --check 'HEAD..@{upstream}'
```

Inspect changed paths and any machine-specific paths, installer destinations,
state protocols, or validation-tool changes relevant to the task. A fetch
updates remote-tracking refs; it does not authorize commits, rebases, stashes,
or source edits outside the user's task.

## Choose The Integration Branch

- If the worktree is clean, there are no local-only commits, and upstream is
  only ahead, use `git merge --ff-only '@{upstream}'`.
- If the worktree has changes or untracked files, inspect ownership and preserve
  them. Commit coherent authorized work, create a temporary branch, or stash
  only after deciding which mechanism fits; never auto-stash unknown work.
- If local commits and upstream have diverged, inspect both sides and follow the
  repository's merge or rebase policy. Preserve the pre-operation branch and
  commit so recovery does not depend on chat history.
- If an ignored or untracked plan could collide with incoming history, apply
  `$planning-workflow`'s plan-visibility recovery before integrating.

After integration, re-read `AGENTS.md`, the active plan, the relevant skills and
references, and the incoming files that define the task. Re-check worktree and
branch status before editing. Earlier chat summaries and installed skill copies
are not evidence that the newly integrated source has the same structure.

## Validate Machine-Local State

When the repository owns a helper or schema for machine-local operational state,
use the newly integrated source helper before the installed copy. For this
repository's retrospective state, run from the source repository root:

```sh
# From the source repository root:
./skills/skill-retro/scripts/retro-state.rb validate
./skills/skill-retro/scripts/retro-state.rb pending
./skills/skill-retro/scripts/retro-state.rb review-queue
```

Read the newly pulled state protocol before any migration or mutation. If the
source helper rejects a version, directory, or record shape, treat that as a
compatibility question: do not hand-edit state, reject candidates, or overwrite
records with the stale installed helper. Use only an explicit migration or
initialization path documented by the pulled source.

After source validation and any authorized migration, install the reconciled
skills, run `./install.sh --check`, and repeat live-state validation with the
installed helper. Each machine's inbox, archive, ledger, audit, and cadence
state remains local operational data; Git synchronizes the mechanism, not those
records.
