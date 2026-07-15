---
name: agent-instructions-maintenance
description: Create, audit, shrink, or update repo agent instructions such as AGENTS.md, CLAUDE.md, or local guidance. Use when Codex should decide whether instructions are needed, reduce drift, move generic workflow rules into skills, preserve repo invariants, or review always-loaded guidance.
---

# Agent Instructions Maintenance

Use this skill to keep always-loaded repository guidance short, local, and
non-duplicative.

## Use A More Specific Skill When

- Use ordinary docs editing for README, changelog, or user-facing docs changes
  that do not affect always-loaded agent instructions.
- Use `$planning-workflow` for active plans, handoffs, audits, or plan-file
  cleanup when the main task is execution state rather than instruction policy.
- Use `$github-actions-hardening` or `$r-ci-hardening` for CI workflow rules
  before promoting any CI guidance into `AGENTS.md`.

## First Pass

1. Inspect the worktree before editing:
   `git --no-optional-locks status --short --untracked-files=all`.
2. Find existing instruction files and local skills:

   ```sh
   rg --files -uu | rg '(^|/)(AGENTS|CLAUDE|PLANS)\.md$|(^|/)\.agents/|(^|/)docs/agents/'
   ```

3. Read the current `AGENTS.md` or equivalent, nearby repo docs, active plans,
   and relevant installed skills before deciding what belongs where.
4. Preserve user changes. If instruction files are untracked or ignored, still
   treat them as user-authored guidance.

## Classification

Classify each instruction before keeping, moving, or deleting it:

- `repo-invariant`: hard local fact that applies to most work in this repo.
- `repo-map`: concise path map that prevents expensive rediscovery.
- `command-default`: common commands that are safer to know up front.
- `skill-routable`: workflow already covered by an installed or repo-local skill.
- `deep-dive`: useful only for a narrow task; belongs in a skill, reference, or
  on-demand doc.
- `stale-duplicate`: repeats another source of truth or old convention.
- `ordinary-judgment`: generic engineering advice Codex already knows.

Keep `repo-invariant`, short `repo-map`, and important `command-default`
content. Move or reference `skill-routable` and `deep-dive` content. Remove
`stale-duplicate` and `ordinary-judgment` content unless the repo has an unusual
reason to keep it.

## When To Create AGENTS.md

Create an always-loaded instruction file only when the repo has hard,
non-obvious local invariants that skills will not reliably cover. Good reasons:

- generated files or directories that must never be hand-edited;
- nonstandard build, test, release, or dependency policy;
- important repo map or ownership boundaries;
- local compatibility stance that differs from default expectations;
- safety constraints around data, credentials, generated artifacts, or
  expensive commands;
- skill-routing notes that tell Codex which existing skill to use for a narrow
  repo workflow.

Do not create `AGENTS.md` just to store generic planning, testing, review,
handoff, formatting, or language workflow rules when installed skills already
cover them.

## Preferred Shape

Keep `AGENTS.md` compact. A useful shape is:

- project stance and compatibility policy;
- repo map with only high-value paths;
- hard local constraints and generated-file rules;
- command defaults and validation caveats;
- skill-routing notes for specialized workflows;
- communication or done criteria only when locally unusual.

Avoid long templates, long handoff prompts, full planning skeletons, generic
language workflow, CI hardening checklists, broad review checklists, and copied
tool docs. Put that material in skills, references, scripts, prompts, or normal
repo documentation as appropriate.

## Cleanup Workflow

When shrinking an existing file:

1. Identify the skill or source of truth that will cover removed generic
   workflow.
2. Replace large duplicated sections with a short skill-routing note.
3. Preserve repo-specific command names, path names, vetoes, and invariants.
4. Keep ignored or untracked instruction files visible in the final status
   summary, since they may not be committed.
5. Do not delete local skills or deep-dive docs merely because the root file now
   references global skills; remove them only when the user asks or the repo has
   a clear migration plan.

## Validation

For instruction-only changes, validation is usually:

- read the resulting file top to bottom;
- search for removed boilerplate terms that should no longer appear;
- check `git status --short --untracked-files=all`;
- confirm any referenced skills or docs exist.

Do not run project tests for pure instruction edits unless the edit also changes
code, tooling, or generated artifacts.
