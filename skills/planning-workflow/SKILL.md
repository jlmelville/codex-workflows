---
name: planning-workflow
description: Create, execute, resume, and hand off plans for complex coding work. Use for features, migrations, debugging phases, cross-module changes, plan-producing audits or cleanups, PLANS.md, plan directories, EXECPLAN files, review packets, AGENTS.md execution state, or fresh-agent handoffs. Do not use for report-only audits with no planning artifact.
---

# Planning Workflow

Use this skill to make complex work executable and resumable without depending
on chat history.

## First Decisions

1. Inspect the current worktree before trusting any plan:
   `git --no-optional-locks status --short --untracked-files=all`.
2. Discover existing planning artifacts, including ignored files. Adapt this
   search to the repo, and prefer targeted globs over a broad ignored-file
   scan in dependency-heavy trees:

   ```sh
   rg --files -uu \
     -g '**/AGENTS.md' -g '**/PLANS.md' -g '**/plans/**' \
     -g '**/plans_pending/**' -g '**/docs/plans/**' \
     -g '**/EXECPLAN*.md' -g '**/*handoff*.md' -g '**/*audit*.md' \
     -g '**/*review-packet*.md' -g '**/*briefing*.md' \
     -g '!**/.git/**' -g '!**/.venv/**' -g '!**/node_modules/**' \
     -g '!**/__pycache__/**'
   ```

3. Read only the relevant artifacts: repo instructions, the active plan or
   newest likely plan, the latest handoff if present, and source files needed
   for the current chunk.
4. Decide the smallest planning surface that will keep the work on track:
   - No persistent plan for Q&A, small edits, one-file fixes, simple validation,
     or scratch exploration.
   - Use an ExecPlan for complex features, migrations, cross-module changes,
     debugging phases with meaningful state, or work likely to outlive one
     context window.
   - Use a chunk plan for broad cleanups, audits, or polish efforts where each
     agent should complete one coherent packet and stop.
   - Use an audit or review packet when the goal is to preserve evidence or ask
     another model to challenge conclusions.
   - Treat scratch notes and prototypes as inputs, not as the active source of
     truth, unless the user says otherwise.
5. Use `$agent-instructions-maintenance` when the main task is creating,
   auditing, shrinking, or updating `AGENTS.md` or equivalent instruction
   policy rather than managing execution state.

## Artifact Types

Classify planning files explicitly when creating or updating them:

- `execplan`: living execution document for feature or debugging work.
- `chunk-plan`: queue of bounded packets for multi-agent cleanup.
- `audit`: evidence-first critique, separate from the execution queue.
- `review-packet`: self-contained briefing for external review or challenge.
- `handoff`: concise continuation prompt; chat-first by default.
- `scratch`: exploratory notes, scripts, or research that may inform a plan.

Do not mix all artifact types into one file unless the repo already requires
that shape.

## State Reconciliation

For fresh-agent starts, handoffs, or long-running plans, assume chat summaries
can be stale until checked. Compare the latest handoff against the active plan,
worktree status, and source files that show actual completion. Search untracked
and ignored planning paths when the repo uses local plans. If the artifacts
disagree, record the reconciliation as a discovery or current-state update
before continuing.

When a live handoff names an accepted table or packet and also presents an
inline checklist, compare their item sets before editing. If omissions or
extras combine with limiting language such as `only` or `complete`, surface the
scope contradiction for resolution; do not silently narrow or broaden the
named authority.

## ExecPlans

Create or update an ExecPlan when a future agent must be able to continue from
the repo plus the plan alone.

Use [execplans.md](references/execplans.md) for the section skeleton, detailed
update rules, decision-entry template, and commit-hash caveat.

## Chunk Plans

For repository cleanups or broad audits, prefer small packets over one
monolithic instruction list. See [chunk-plans.md](references/chunk-plans.md) for
the required shape, packet boundaries, sandboxed staging recovery,
behavior-neutral file split verification, bug-scoped staging, and warning
ownership rules.

## Audits And Review Packets

Keep audits and execution plans separate when possible. Audits preserve raw
critique and evidence; execution plans convert that evidence into ordered work.

When converting an external audit or model review into a chunk plan, preserve
the source audit, statically confirm findings before making them tasks, mark
unverified claims, and resolve open questions into explicit decisions where
possible. The resulting plan should include the source audit pointer, confirmed
findings, guardrails, a decision log, open questions, and which claims still
need test evidence.

For stabilization chunks, review packet structure, and audit-to-plan conversion
details, see
[audits-and-review-packets.md](references/audits-and-review-packets.md).

For layered numerical-method reproductions, use the evidence-gated oracle
ladder, constrained-limit closure, and stop decisions in
[numerical-reproduction-work-packets.md](references/numerical-reproduction-work-packets.md).

## Workflow Retrospective Notes

During multi-agent work, keep process observations in the plan only when they
are needed for execution continuity or a later phase decision. Use
`$papercut-capture` for authorized friction intake and `$skill-retro` for mature
reusable conclusions; do not duplicate those external records into tracked
plans. See
[workflow-retrospective-notes.md](references/workflow-retrospective-notes.md)
for the boundary and examples.

## Handoffs

Use a fresh-agent handoff when ending a meaningful phase, stopping with
unfinished work, completing debugging or smoke-test follow-up, or when the user
is likely to continue in a new session. Skip handoffs for ordinary Q&A, minor
clarifications, and trivial edits unless the user asks.

See [handoffs.md](references/handoffs.md) for placement, durable-state pointers,
environment assumptions, path validation, and the full template.

## Location, Visibility, And Cleanup

Respect the repo's existing plan location and keep repo instructions short and
repo-specific. Use
[plan-file-visibility.md](references/plan-file-visibility.md) when plans may be
ignored, untracked, noisy for package checks, or subject to cleanup.

## Resume And Recovery

When resuming after compaction, interruption, or a fresh-agent handoff:

1. Re-read repo instructions, this skill, the active plan, and the latest
   handoff.
2. Re-check worktree status and inspect touched files before editing.
3. Verify the plan against the code. If they disagree, record the discrepancy
   as a discovery and update the current state before continuing.
4. Continue with the next coherent step, not with stale chat memory.

## Completion Bar

A plan is good enough when a future agent can identify:

the goal and current state; what changed or was ruled out; decisions made and
why; relevant files, commands, and expected observations; validation already run
and remaining gaps; the exact next action and guardrails; and any reusable
workflow-retrospective notes gathered during the work.

For a handoff, verify every `Read first` path exists in the recipient's context.
Name an inline substitute explicitly, and keep independent required reads
separable so one missing or substituted path cannot suppress the rest.

If any of those are missing at a stopping point, update the plan or include a
handoff before ending the turn.
