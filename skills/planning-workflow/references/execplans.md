# ExecPlans

Use an ExecPlan when a future agent must be able to continue from the repository
plus the plan alone.

## Section Skeleton

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

## Update Rules

Keep the plan self-contained. Name repository-relative files, functions,
commands, fixtures, expected observations, acceptance criteria, non-goals, and
user vetoes. Summarize logs and errors; do not paste long transcripts unless
the exact output is necessary to continue.

Update `Progress`, `Surprises & Discoveries`, `Decision Log`, validation state,
and outcomes whenever work pauses, changes direction, completes a milestone, or
hands off. Put the active state and next action near the top so large plans do
not bury what matters.

## Lifecycle Rollover

Keep updating an ExecPlan in place while it remains the smallest useful,
self-contained startup artifact. Line count alone is not a rollover trigger.
Create a successor at a coherent phase boundary when completed history
dominates the active queue, or when the next objective has a materially
different acceptance witness and keeping both phases active would obscure the
current work.

When rolling over:

1. Finish the predecessor's current-state and outcomes sections, mark it as
   historical, and link to the successor.
2. Make the successor self-contained for the new objective, including current
   state, relevant decisions and guardrails, acceptance, and the next action;
   link back to the predecessor for provenance.
3. Keep the predecessor out of required startup reads. Consult it only when
   earlier reasoning or evidence is needed; do not copy its chronology into the
   successor.
4. Put large result tables, logs, or benchmark outputs in bounded companion
   artifacts and summarize the decisions they support in the successor.

Do not record the hash of the commit currently being created in a file included
in that same commit; amending the file changes the commit hash immediately.
Record prior commit hashes in the plan, and report the final hash in chat or in
a later commit.

Use decision entries with this shape:

```md
- Decision: <choice made>
  Rationale: <why this choice fits the evidence and constraints>
  Date/Author: <YYYY-MM-DD> / Codex
```

## Request Provenance

Do not preserve a separate baseline for ordinary plan evolution. When
request-versus-delivery comparison is an explicit acceptance requirement and
the living ExecPlan is the only durable copy of the originating request, freeze
one exact pre-edit baseline before changing the plan. Keep that snapshot out of
the active queue and record an immutable identity for it; use a commit or tree
when tracked and a frozen copy or content digest when history is unavailable,
as described under [review target identity](audits-and-review-packets.md#review-target-identity).

Give baseline requirements stable IDs, record later operator additions
separately, and maintain each item's disposition with an evidence pointer as
implementation evolves. Before closing, reconcile the final crosswalk against
both the frozen baseline and post-baseline additions so `Outcomes &
Retrospective` distinguishes delivered, changed, deferred, and declined scope.
