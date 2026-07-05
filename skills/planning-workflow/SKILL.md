---
name: planning-workflow
description: Create, execute, resume, and hand off plans for complex, multi-session coding work. Use when Codex is asked to plan or continue larger features, audits, cleanups, migrations, debugging phases, cross-module changes, or work involving PLANS.md, AGENTS.md, plans/, plans_pending/, docs/plans/, EXECPLAN*.md, audits, review packets, or fresh-agent handoffs. Also use to decide when planning ceremony should be skipped for small tasks.
---

# Planning Workflow

Use this skill to make complex work executable and resumable without depending
on chat history.

## First Decisions

1. Inspect the current worktree before trusting any plan:
   `git --no-optional-locks status --short --untracked-files=all`.
2. Discover existing planning artifacts, including ignored files. Adapt this
   search to the repo:

   ```sh
   rg --files -uu | rg '(^|/)(AGENTS|PLANS)\.md$|(^|/)plans(_pending)?/|(^|/)docs/plans/|(^|/)EXECPLAN.*\.md$|handoff|audit|review-packet|briefing'
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

Use these sections unless the local repo already has a compatible skeleton:

- `Purpose / Big Picture`
- `Current State` or a short status block near the top
- `Progress`
- `Surprises & Discoveries`
- `Decision Log`
- `Context and Orientation`
- `Plan of Work`
- `Concrete Steps`
- `Validation and Acceptance`
- `Idempotence and Recovery`
- `Artifacts and Notes`
- `Outcomes & Retrospective`
- `Interfaces and Dependencies`, when public interfaces or APIs are changing

Keep the plan self-contained. Name repository-relative files, functions,
commands, fixtures, expected observations, acceptance criteria, non-goals, and
user vetoes. Summarize logs and errors; do not paste long transcripts unless
the exact output is necessary to continue.

Update `Progress`, `Surprises & Discoveries`, `Decision Log`, validation state,
and outcomes whenever work pauses, changes direction, completes a milestone, or
hands off. Put the active state and next action near the top so large plans do
not bury what matters.

Use decision entries with this shape:

```md
- Decision: <choice made>
  Rationale: <why this choice fits the evidence and constraints>
  Date/Author: <YYYY-MM-DD> / Codex
```

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

For cleanup chunks that may reveal several unrelated correctness bugs, decide
the likely commit boundaries before editing. Keep fixes and tests independently
stageable by bug whenever practical, instead of making one shared regression
file or broad hunk that later requires delicate partial staging.

## Audits And Review Packets

Keep audits and execution plans separate when possible. Audits preserve raw
critique and evidence; execution plans convert that evidence into ordered work.

When converting an external audit or model review into a chunk plan, preserve
the source audit, statically confirm findings before making them tasks, mark
unverified claims, and resolve open questions into explicit decisions where
possible. The resulting plan should include the source audit pointer, confirmed
findings, guardrails, a decision log, open questions, and which claims still
need test evidence.

Review packets should be self-contained and should ask the reviewer to
challenge assumptions, gaps, and risks, not merely summarize the plan. Include
the narrow evidence needed for review and the specific questions to answer.

## Workflow Retrospective Notes

During multi-agent work, record reusable process findings as they arise, not
only at the final retrospective. Put them under `Artifacts and Notes`,
`Outcomes & Retrospective`, or a local equivalent.

Capture feature-orthogonal observations such as:

- repeated workflow, validation, benchmark, or handoff patterns;
- tool failures, sandbox limitations, or environment-specific workarounds;
- repo conventions that were not obvious from existing guidance;
- planning friction, missing context, or handoff gaps;
- candidate skills, scripts, prompts, or references;
- why the lesson is reusable beyond the current feature.

Keep these notes concise and evidence-based. They should let the final agent run
a skill retrospective using evidence from every phase, not only its current
context window.

## Handoffs

Use a fresh-agent handoff when ending a meaningful phase, stopping with
unfinished work, completing debugging or smoke-test follow-up, or when the user
is likely to continue in a new session. Skip handoffs for ordinary Q&A, minor
clarifications, and trivial edits unless the user asks.

Put handoffs in the chat response by default. Write persistent handoff files
only when the user asks or the repo already uses them for active work. The
active plan should hold durable state; the handoff should point to it.

Use a fenced `text` block:

```text
Fresh-agent handoff prompt

We are working in <repo path> on <goal>. Phase/chunk <id> is <complete/in progress/blocked>.

Read first:
- <repo instructions or active plan>
- <supporting audit/review file, if needed>

Current state:
- <what changed or was learned>
- <important files touched or inspected>
- <key decisions, constraints, or user vetoes>

Validation:
- Ran `<command>`: <result>
- Ran `<command>`: <result or failure>

Open issues:
- <bug/failure/uncertainty>
- <thing not yet tested>

Next recommended steps:
1. <next task>
2. <next task>
3. <tests or smoke checks to run>

Guardrails:
- <do not revisit / do not broaden / preserve this behavior>
```

Keep handoffs concise. Prefer exact file paths, function names, commands,
statuses, and error messages over broad narrative.

## Location And Visibility

Respect the repo's existing convention for plan locations. Search ignored paths
because active plans may live under ignored `plans/`, `plans_pending/`, or
`docs/plans/` directories.

When editing an ignored active plan, use ignored-aware status or discovery such
as `git status --ignored --short` or `rg --files -uu`, and call out the hidden
plan edit in the final response.

When editing an untracked active plan, report that status explicitly. Ordinary
`git diff -- path/to/plan.md` has no baseline and may show no content for a
`??` file; use file line references, a short summary, or `git diff --no-index`
against a saved prior copy only when a content diff is necessary.

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

Avoid adding or expanding generic `PLANS.md` or `AGENTS.md` rules when this
skill already covers them. Keep repo instructions short and repo-specific.

## Cleaning Local Planning Files

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

- the goal and current state;
- what has already changed or been ruled out;
- decisions made and why;
- relevant files, commands, and expected observations;
- validation already run and remaining gaps;
- the exact next action and guardrails.
- any reusable workflow-retrospective notes gathered during the work.

If any of those are missing at a stopping point, update the plan or include a
handoff before ending the turn.
