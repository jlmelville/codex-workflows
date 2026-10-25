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
   - a chunk plan for broad work that needs bounded work packets;
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
4. Hold the owner's objective, constraints, and non-goals fixed. Frame work items as required
   outcomes or uncertainties to resolve; choose or revise methods by their expected contribution
   to that contract and total cost, including reconstruction, maintenance, and owner attention.
   A method's presence in a plan alone does not make it an accepted constraint.
   For consequential uncertainty within scope, own the investigation: identify the decision, choose
   methods and evidence, and establish the necessary access and feedback.
   Before an existing safeguard requires replacing an approach or adding a parallel path, identify
   how it is enforced and where it applies. Strengthening it or widening its scope requires separate,
   proportionate evidence; the existing safeguard does not itself authorize either expansion.
5. Before a long unattended loop, define an observation that distinguishes
   progress, success, regression, and failure, plus its stop boundary. End at a
   human-judgment boundary; the witness does not expand authority or cost.
   Before unattended work can incur material metered charges, identify the
   accepted budget and what bounds spending. Prefer native provider or
   execution limits, and verify their scope and cutoff behavior. Budget alerts
   are not enforced caps. Resolve any exposure outside the accepted limits
   before starting.
6. Use `$agent-instructions-maintenance` when instruction policy, rather than
   execution state, is the main task.

For reader-facing documentation, let the applicable documentation skill own
visible order, terminology, and depth. The plan records obligations and
evidence, not a prose outline.

## Proportionality And Acceptance

Admit a new plan item only when omitting it would leave an accepted obligation unmet or required
evidence missing. Preserved behavior and applicable, named safety and authority boundaries are
obligations. A finding or reviewer request does not itself authorize a remedy. Seek direction with
`scope-reopen` only for material changes to accepted goals, behavior, completion criteria, or
authority outside existing authorization. Ordinary method changes within scope proceed.

When a scope decision needs acceptance, present the concrete proposed change,
existing capabilities it preserves or replaces, and material cost or tradeoffs.

Name an acceptance witness for each requirement: an executable check, inspected
artifact, observation, or owner decision that bears on that requirement. State
what the result establishes and which consequential requirement remains unverified.
When a plausible mistake could pass the proposed check, use
[acceptance-evidence.md](references/acceptance-evidence.md) to construct a
distinguishing fixture or observe the relevant boundary. Stop checking once the evidence supports the
decision.

Invest early in verification tooling in proportion to consequential uncertainty
about setup, control, or observation. Reuse existing tooling or add the smallest
in-scope fixture, command, or harness, and exercise it to confirm the required
observations are available; repeated friction is not required.

Where it reduces consequential uncertainty, sequence a small consumer-visible
end-to-end result before optional expansion. That first result determines useful
ordering; preserve all accepted completion obligations.

Use `$agent-instructions-maintenance` when preserving or refreshing project-local
verification recipes.

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
