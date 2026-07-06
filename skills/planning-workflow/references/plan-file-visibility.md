# Plan File Visibility

Use this with `$planning-workflow` when plan files may be ignored, untracked,
local-only, or noisy for package tooling.

## Discovery

Respect the repo's existing convention for plan locations. Search ignored paths
because active plans may live under ignored `plans/`, `plans_pending/`, or
`docs/plans/` directories.

When editing an ignored active plan, use ignored-aware status or discovery such
as:

```sh
git status --ignored --short
rg --files -uu
```

Call out hidden plan edits in the final response.

When editing an untracked active plan, report that status explicitly. Ordinary
`git diff -- path/to/plan.md` has no baseline and may show no content for a
`??` file; use file line references, a short summary, or `git diff --no-index`
against a saved prior copy only when a content diff is necessary.

`git diff --check` also does not cover untracked plan files. When a new or
ignored plan file is part of the work, pair diff hygiene with an explicit
whitespace check over those paths, such as
`rg -n '[ \t]+$' plans/new-plan.md`, before claiming whitespace is clean.

## Location Choice

When creating a persistent plan, choose a location deliberately:

- Use the established plan directory when it is intentionally local or ignored.
- Use a visible tracked path, such as a root `EXECPLAN-*.md`, when the plan must
  appear in normal `git status` or be reviewed in a PR.
- Explain the location choice in the plan when ignored paths or visibility
  could surprise a later agent.

In package repositories, root planning directories can trigger package-check
notes, such as an `R CMD check` top-level-file note for `plans`. Record the
tracking/ignored state and intended policy; do not move or delete active plans
solely to silence package tooling.

## Cleanup

When asked to clean up `PLANS.md`, `AGENTS.md`, plan directories, or old
handoff files after this skill exists:

1. Search tracked, untracked, and ignored paths before deciding what is active.
2. Separate active execution state from historical notes, scratch research,
   audits, and completed handoffs.
3. Preserve durable current state: goal, decisions, validation, next action,
   guardrails, and user vetoes.
4. Shrink root `PLANS.md` or `AGENTS.md` to repo-specific addenda and skill
   routing. Remove copied skeletons, generic handoff templates, and fixed
   marker rules when this skill covers them.
5. Do not delete ignored plans, scratch files, or historical handoffs unless the
   user explicitly asks; report their status instead.
6. Note whether resulting files are tracked, untracked, or ignored, because
   future agents may not see them in ordinary status output.
