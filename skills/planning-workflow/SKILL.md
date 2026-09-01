---
name: planning-workflow
description: Create, execute, resume, and hand off durable plans for complex coding work. Use for cross-module features, unresolved migrations, phased debugging, plan-backed audits or cleanups, ExecPlans, chunk plans, review packets, and fresh-agent handoffs. Do not use for report-only audits or small changes.
---

# Planning Workflow

Make complex work executable and resumable without turning planning into the
work itself.

## First Decisions

1. Inspect the complete worktree and discover existing plans, handoffs, audits,
   and repo instructions, including relevant ignored files. Read only the
   active or newest likely artifact and the source needed for the current work.
2. Choose the smallest planning surface that keeps the task on track:
   - no persistent plan for Q&A, small edits, one-file fixes, simple validation,
     or scratch exploration;
   - an ExecPlan for complex work likely to outlive one context window;
   - a chunk plan for broad work that needs bounded independent packets;
   - an audit or review packet to preserve evidence or challenge conclusions.
3. Before drafting a durable plan, write this compact scope decision in chat or
   at its top:

   ```text
   Owner objective:
   Already-working capabilities:
   Explicit non-goals:
   Existing proven path:
   Cheapest capacity or scope adjustment preserving that path:
   Why the proven path is insufficient:
   Replacement mechanism: none, or owner-approved proposal
   ```

   Treat inherited handoff mechanisms as proposals unless the owner accepted them. If insufficiency has no concrete answer, use the proven path.
   Replacing working code, even for a more bounded or elegant mechanism, is an owner question that must include the capacity-or-scope counterfactual. For workflow-heavy, human-operated work without a fixed external interface, sketch the shortest operator question-to-payoff path before stabilizing public APIs, schemas, persistent records, or large contract layers.
   Use unexplained concepts, expert defaults, manual choreography, or machinery with no visible consumer to narrow the design; skip this probe for small local changes or externally fixed contracts.
4. Freeze the owner's objective, constraints, and non-goals for review; keep
   chosen mechanisms challengeable. Classify discoveries against that contract.
   Admit a plan item only when omitting it would leave the accepted contract unmet or required evidence missing. Treat retained behavior and applicable, named safety and authority boundaries as part of that contract; usefulness, reviewer origin, and imagined future value are not enough. Admit only the smallest probe that can settle a concrete uncertainty material to in-scope implementation or acceptance, and seek direction for material expansion of goals, semantics, acceptance, or authority.
   Before an inherited safeguard forces replacement or a parallel path, name
   its enforcement and scope. Either increase is a new, proportionally evidenced
   decision; a lower or narrower safeguard cannot authorize its own escalation.
5. Before a long unattended loop, define an observation that distinguishes
   progress, success, regression, and failure, plus its stop boundary. End at a
   human-judgment boundary; the witness does not expand authority or cost.
6. Use `$agent-instructions-maintenance` when instruction policy, rather than
   execution state, is the main task.

For reader-facing documentation, let the applicable documentation skill own
visible order, terminology, and depth. The plan records obligations and
evidence, not a prose outline.

## Proportionality And Acceptance

A plan records accepted obligations; it does not create them. Classify the smallest honest remedy separately from
the defect; a confirmed defect does not expand the accepted contract. If that remedy would extend the contract
through durable state, a public API, schema or configuration surface, compatibility, background, retry or
persistence machinery, a new subsystem, or wider semantics, stop with `scope-reopen`. Re-present the in-contract
correction and proposed expansion separately; do not decompose or schedule the expansion before acceptance.

Before owner acceptance, summarize on one screen the objective, already-working capabilities, explicit non-goals, work-package count when named packages are used,
and the three costliest or most novel decisions; name a nearby precedent only when readily known. The count informs judgment, not acceptance or `scope-reopen`.

## Artifact And State Boundaries

Classify files as `execplan`, `chunk-plan`, `audit`, `review-packet`, `handoff`,
or `scratch`; do not mix them unless the repo requires it. Scratch and agent
proposals are evidence, not accepted authority.

At fresh starts and handoffs, reconcile the plan with source; verify every
`Read first` path, name inline substitutes, and keep remaining reads independent.
Compare inline checklists with named accepted packets before editing.

Use these routed references only when their condition applies:

- [execplans.md](references/execplans.md): durable section shape, request
  provenance, updates, and lifecycle rollover;
- [chunk-plans.md](references/chunk-plans.md): bounded packet execution;
- [audits-and-review-packets.md](references/audits-and-review-packets.md):
  audit conversion and independent review;
- [numerical-reproduction-work-packets.md](references/numerical-reproduction-work-packets.md):
  evidence-gated layered numerical reproduction;
- [handoffs.md](references/handoffs.md): concise continuation prompts;
- [plan-file-visibility.md](references/plan-file-visibility.md): ignored,
  untracked, or package-visible artifacts;
- [workflow-retrospective-notes.md](references/workflow-retrospective-notes.md):
  execution notes versus `$papercut-capture` and `$skill-retro`.

## Execution And Recovery

Keep the active state and next action near the top. Update decisions,
discoveries, progress, and validation when direction changes or work pauses.
After compaction or interruption, re-read repo instructions, this skill, the
active plan, and the latest handoff; verify them against source before
continuing.

Close when the accepted contract is satisfied and in-scope blockers are
resolved or explicitly dispositioned. A future agent must be able to identify
the goal, current state, decisions and rationale, relevant files and commands,
validation and gaps, next action, and guardrails without chat history.
