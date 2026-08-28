# Skill-Repository Reconciliation Overlay

Apply `$repo-update-preflight` before this reference. It owns upstream refresh,
worktree and stash inspection, divergence handling, safe integration, and
generic post-integration checks. This overlay owns the additional decisions for
a skill source repository that also has installed copies and machine-local
operational state.

## Re-read Reconciled Policy

After integration, inspect incoming changes to skill layout, installer
destinations, state protocols, and validation tools relevant to the task.
Re-read `AGENTS.md`, the active plan, and the relevant source skills and
references. Earlier chat summaries and installed skill copies are not evidence
that newly integrated source has the same structure or policy.

## Validate Machine-Local State

When incoming changes affect a helper or schema for machine-local operational
state, use the newly integrated source helper before the installed copy. For
this repository's retrospective state, run from the source repository root:

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
