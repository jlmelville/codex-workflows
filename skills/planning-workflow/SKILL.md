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

## Audits And Review Packets

Keep audits and execution plans separate when possible. Audits preserve raw
critique and evidence; execution plans convert that evidence into ordered work.

Review packets should be self-contained and should ask the reviewer to
challenge assumptions, gaps, and risks, not merely summarize the plan. Include
the narrow evidence needed for review and the specific questions to answer.

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

When creating a persistent plan, choose a location deliberately:

- Use the established plan directory when it is intentionally local or ignored.
- Use a visible tracked path, such as a root `EXECPLAN-*.md`, when the plan must
  appear in normal `git status` or be reviewed in a PR.
- Explain the location choice in the plan when ignored paths or visibility
  could surprise a later agent.

Avoid adding or expanding generic `PLANS.md` or `AGENTS.md` rules when this
skill already covers them. Keep repo instructions short and repo-specific.

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

If any of those are missing at a stopping point, update the plan or include a
handoff before ending the turn.
