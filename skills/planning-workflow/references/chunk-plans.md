# Chunk Plans

Use this with `$planning-workflow` when broad cleanup, audit, or polish work
needs bounded packets instead of one monolithic instruction list.

## Minimum Shape

Include the goal and guardrails, source audit or review when applicable,
chunking rules, a queue with scope and exit criteria, and a progress log of
changes, validation, decisions, and the next packet. Each agent completes one
coherent chunk, validates it, updates the log, and stops with a handoff when
work remains. Do not combine unrelated chunks because context remains.

Create a separate packet only when it enables independently useful progress or isolates a genuinely distinct ownership, dependency, change-set, validation, or recovery boundary. Files, components, layers, phases, and available agents alone do not justify separation; keep tightly coupled implementation and validation together.

If an active chunk proves oversized but is making coherent progress, finish its
current contract and apply smaller boundaries prospectively. When independent
review is required, use the bounded loop in
[audits-and-review-packets.md](audits-and-review-packets.md#bounded-independent-review).

## Durable Source Boundary

Keep chronology, packet identifiers, and review status in the plan or handoff.
Source comments and user-facing output must stand alone and explain a lasting
domain, API, compatibility, numerical, or safety constraint. Prefer structure
that makes the intent clear enough to omit the comment.

## Mechanical Splits And Staging

For a behavior-neutral file split, snapshot and mechanically reconstruct the
original with explicit separators, then compare it before tests. Any other
difference needs review. Strip boundary-only trailing blank lines rather than
treating them as source content.

For cleanup that reveals unrelated bugs, keep fixes and regression tests
independently stageable when practical. In shared checkouts, inspect complete
status immediately before staging and stop on overlapping or unattributed
changes; do not hide or overwrite another worker's edits.

## Accepted Mapping Crosswalk

When a packet accepts an itemized mapping, preserve it as the completion
checklist. Compare any inline subset before editing and resolve contradictory
limiting language. Crosswalk every row against final source; for renames, check
declarations, definitions, call sites, and remaining old executable names.
Passing behavioral tests does not establish item-set completeness. Append later
corrections and evidence instead of rewriting earlier progress claims.

## Warning Ownership

Before moving on, fix each remaining warning or anomaly, classify it with exact
evidence, or assign a named follow-up packet with a next action.
