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

## Synchronization Preflight And Recovery

Ignored status describes the current worktree, not repository history. Before
rebasing a long local stack that contains valuable ignored or untracked plans,
record the current branch and commit, check whether those exact paths appeared
in the commits that may be replayed, and optionally record content identities
with `git hash-object --no-filters -- <path>`.

If a pull or rebase stops because an untracked plan would be overwritten, do
not solve the collision by staging, deleting, or committing the private plan.
Preserve `git status`, the saved branch and commit, and any artifact hashes.
When the recovery goal is to abandon the replay and return to the pre-rebase
branch, inspect `HEAD` and `ORIG_HEAD`, run `git rebase --abort`, then verify the
branch commit and plan hashes against the saved values. If repository topology
or user intent instead requires completing the replay, stop and choose that
path explicitly rather than mutating the local plans as an unblock tactic.

## Ignored Executable Evidence

Treat an ignored script, notebook, or benchmark harness as executable evidence,
not as a passive planning note. Before citing its result, confirm its tracking
and ignore status, resolve its entry points and record shapes against current
source, and run the cheapest bounded smoke invocation. Repeat that freshness
gate after private constructors, fields, or protocols it consumes are renamed.
If it is stale, make a harness-only refresh an explicit prerequisite rather
than running it as though it were current evidence.

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

Do not require fixed emoji or marker taxonomies. If a repo or user explicitly
requests progress markers for an active ExecPlan, define a small phase-local
legend in chat and record it in `Artifacts and Notes`. Keep markers out of code,
generated docs, commit messages, and copied terminal output.

## Unpublished Experiment Retirement

Do not infer history rewriting from a request to remove an experiment. Clarify
whether the operator wants only current-tree cleanup or also wants unpublished
experimental commits removed from the active branch. Use an ordinary removal or
revert for published or shared history.

When active-history removal is explicitly authorized for unpublished work,
first preserve one verified recovery branch, bundle, or equivalent artifact;
identify the upstream base; classify independently useful spillovers; and
separate compact nonreproducible evidence from large reproducible caches. Rebuild
the active line from the upstream base and reapply only validated product
changes, then verify the experiment is absent from both the final tree and the
active ancestry. Leave the recovery artifact and any original dirty checkout
untouched until those checks pass.
