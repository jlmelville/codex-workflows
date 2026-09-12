---
name: planning-workflow
description: Plan and resume complex coding work that needs durable decisions, execution packets, or handoffs. Skip small changes and report-only audits.
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
3. Record the objective, accepted scope, constraints, and completion evidence in
   the smallest useful form. When proposing replacement of a working approach,
   explain why it is insufficient and whether a capacity or scope adjustment
   would preserve it. Treat inherited mechanisms as proposals unless accepted.
   Ordinary implementation choices and replacements within an authorized refactor do not need another
   approval. When designing or materially changing an API, component boundary, or operator workflow,
   sketch a representative task from the consumer's side before settling the interface. Include the
   operation that exposes a consequential ownership, sequencing, or lifecycle decision. Use the sketch
   to challenge unnecessary caller knowledge and machinery while preserving accepted constraints.
4. Hold the owner's objective, constraints, and non-goals fixed during review while allowing the
   chosen approach to be challenged. Assess discoveries against that accepted contract, including
   behavior to preserve and applicable, named safety and authority boundaries. Add a plan item only
   when omitting it would leave an obligation unmet or required evidence missing. Usefulness, a
   reviewer's suggestion, or possible future value alone does not justify it. For an uncertainty
   affecting the approach or acceptance within scope, identify the decision and the evidence needed to
   resolve it against the requested outcome and relevant constraints. Use the smallest adequate check
   that preserves the behavior in question, and stop when the evidence supports a decision. Seek
   direction before materially expanding goals, behavior, acceptance criteria, or authority.
   Before an existing safeguard requires replacing an approach or adding a parallel path, identify
   how it is enforced and where it applies. Strengthening it or widening its scope requires separate,
   proportionate evidence; the existing safeguard does not itself authorize either expansion.
5. Before a long unattended loop, define an observation that distinguishes
   progress, success, regression, and failure, plus its stop boundary. End at a
   human-judgment boundary; the witness does not expand authority or cost.
6. Use `$agent-instructions-maintenance` when instruction policy, rather than
   execution state, is the main task.

For reader-facing documentation, let the applicable documentation skill own
visible order, terminology, and depth. The plan records obligations and
evidence, not a prose outline.

## Proportionality And Acceptance

A plan records accepted obligations; it does not create them. A confirmed defect does not expand
those obligations. Identify the smallest adequate remedy separately from the defect. If that remedy
would extend the accepted contract through durable state, a public API, schema or configuration
surface, compatibility requirements, background work, retries, persistence machinery, a new subsystem,
or wider behavior, stop with `scope-reopen`. Present the correction within scope separately from the
proposed expansion. Do not break the expansion into tasks or schedule it before acceptance.

When a scope decision needs acceptance, present the concrete proposed change,
existing capabilities it preserves or replaces, and material cost or tradeoffs.
Carry prior user authorization forward; pause only for a decision outside it.

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

Continue through implementation, relevant validation, and in-scope fixes until
the accepted contract is satisfied or a blocker needs new authority or input.
An implementation checkpoint or separable phase is not itself a request for
review. Respect an explicitly requested review boundary. A future agent must be
able to identify the goal, current state, decisions and rationale, relevant
files and commands, validation and gaps, next action, and guardrails without
chat history.
