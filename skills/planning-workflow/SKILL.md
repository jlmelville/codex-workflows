---
name: planning-workflow
description: Create, execute, resume, and hand off plans for complex coding work. Use when Codex plans or continues features, audits, cleanups, migrations, debugging phases, cross-module changes, PLANS.md, AGENTS.md, plan directories, EXECPLAN files, review packets, or fresh-agent handoffs. Also use to skip planning for small tasks.
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

## ExecPlans

Create or update an ExecPlan when a future agent must be able to continue from
the repo plus the plan alone.

Use [execplans.md](references/execplans.md) for the section skeleton, detailed
update rules, decision-entry template, and commit-hash caveat.

## Chunk Plans

For repository cleanups or broad audits, prefer small packets over one
monolithic instruction list.

A chunk plan should include:

- goal and guardrails;
- source audit or review file, if any;
- explicit operational chunking rules;
- a chunk queue with scope, tasks, validation, and exit criteria;
- a progress log recording completed chunks, files changed, tests run,
  discoveries, decisions, and the recommended next chunk.

Each agent should complete one coherent chunk, run focused validation, update
the progress log, and stop with a handoff when more work remains. Do not
combine unrelated chunks just because context remains.

If staging or committing fails under managed sandboxing with a read-only
`.git/index.lock` error, and `git -C <repo>` is an approved command form, retry
the git operation with `git -C <repo>` before considering permission changes or
lock-file cleanup.

See [chunk-plans.md](references/chunk-plans.md) for behavior-neutral file split
verification, bug-scoped staging, and warning ownership rules.

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

## Workflow Retrospective Notes

During multi-agent work, record reusable process findings as they arise, not
only at the final retrospective. Put them under `Artifacts and Notes`,
`Outcomes & Retrospective`, or a local equivalent.

Keep notes concise, evidence-based, and focused on lessons reusable beyond the
current feature. See
[workflow-retrospective-notes.md](references/workflow-retrospective-notes.md)
for examples.

## Handoffs

Use a fresh-agent handoff when ending a meaningful phase, stopping with
unfinished work, completing debugging or smoke-test follow-up, or when the user
is likely to continue in a new session. Skip handoffs for ordinary Q&A, minor
clarifications, and trivial edits unless the user asks.

Put handoffs in chat by default and write files only when asked or when the repo
already uses them. Keep durable state in the active plan and point to it from
the handoff. See [handoffs.md](references/handoffs.md) for the full template.

## Location And Visibility

Respect the repo's existing convention for plan locations. Search ignored paths
because active plans may live under ignored `plans/`, `plans_pending/`, or
`docs/plans/` directories.

When creating a persistent plan, choose a location deliberately:

- Use the established plan directory when it is intentionally local or ignored.
- Use a visible tracked path, such as a root `EXECPLAN-*.md`, when the plan must
  appear in normal `git status` or be reviewed in a PR.
- Explain the location choice in the plan when ignored paths or visibility
  could surprise a later agent.

Avoid adding or expanding generic `PLANS.md` or `AGENTS.md` rules when this
skill already covers them. Keep repo instructions short and repo-specific.

See [plan-file-visibility.md](references/plan-file-visibility.md) for ignored
or untracked plan edits, package-check visibility issues, and cleanup rules.

## Cleaning Local Planning Files

When asked to clean up `PLANS.md`, `AGENTS.md`, plan directories, or old
handoff files after this skill exists, preserve durable current state and remove
generic copied rules only after checking tracked, untracked, and ignored paths.
Use [plan-file-visibility.md](references/plan-file-visibility.md) for the full
cleanup checklist.

## Resume And Recovery

When resuming after compaction, interruption, or a fresh-agent handoff:

1. Re-read repo instructions, this skill, the active plan, and the latest
   handoff.
2. Re-check worktree status and inspect touched files before editing.
3. Verify the plan against the code. If they disagree, record the discrepancy
   as a discovery and update the current state before continuing.
4. Continue with the next coherent step, not with stale chat memory.

## Progress Markers

Do not require fixed emoji or marker taxonomies. If a repo or user explicitly
requests progress markers for an active ExecPlan, define a small phase-local
legend in chat and record it in `Artifacts and Notes`. Do not put markers in
code, generated docs, commit messages, or copied terminal output.

## Completion Bar

A plan is good enough when a future agent can identify:

the goal and current state; what changed or was ruled out; decisions made and
why; relevant files, commands, and expected observations; validation already run
and remaining gaps; the exact next action and guardrails; and any reusable
workflow-retrospective notes gathered during the work.

If any of those are missing at a stopping point, update the plan or include a
handoff before ending the turn.
