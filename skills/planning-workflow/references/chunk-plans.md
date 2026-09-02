# Chunk Plans

Use this with `$planning-workflow` when broad cleanup, audit, or polish work
needs bounded packets instead of one monolithic instruction list.

## Minimum Shape

Include the goal, guardrails, applicable source audit or review, chunking rules, scoped queue, and progress log of changes,
validation, decisions, and the next packet. Complete one coherent chunk per agent; do not combine unrelated work for context.

Create a separate packet only for independently useful progress or a distinct ownership, dependency, change-set,
validation, or recovery boundary. Files, phases, and available agents alone do not justify separation.

Before broad fan-out across similar units, use an existing proven mechanism or complete one representative unit end to
end. Verify any common deterministic mechanism against that result; reserve packets for exceptions and judgment.

If a chunk proves oversized but is making coherent progress, finish its contract and shrink later boundaries. For
independent review, use the bounded loop in
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

Preserve an accepted itemized mapping as the completion checklist and reconcile contradictory inline subsets before
editing. Crosswalk every row against final source; passing tests does not prove item-set completeness. Append later
corrections rather than rewriting earlier claims. For renames, check declarations, definitions, calls, and stale names.

## Warning Ownership

Before moving on, fix each remaining warning or anomaly, classify it with exact
evidence, or assign a named follow-up packet with a next action.
