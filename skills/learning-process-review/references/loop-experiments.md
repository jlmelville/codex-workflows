# Learning-Loop Experiments

Use when a material change to the learning process has uncertain benefit or
recurring cost. Routine fixes need no experiment record. Keep any warranted
experiment in an existing maintenance ledger; use its Markdown body and shared
follow-up fields instead of introducing a registry or new required fields.
Creating state and changing source still require their respective authority.

Before an authorized trial, state:

- the concrete problem, hypothesis, and prior observation or baseline;
- the intended downstream benefit and the observation that would establish it;
- likely operating costs, including agent work, owner attention, added guidance,
  validation time, and duplicate review;
- which instruction or mechanism this replaces or allows retiring, or why it
  must coexist;
- the observation boundary and limitations, an owner, a concrete review condition and check,
  a next action, and a close condition.

Use counts or timings when they meaningfully distinguish outcomes; a countable
proxy alone does not establish benefit. Reuse evidence already available from
ordinary work. For growth or speed claims, use the existing drift audit, source
diff and validation timing, distinguishing inherited cost from the trial's
delta. Link an accepted identity when one already exists; an experiment ledger
does not require creating a candidate identity just for bookkeeping.

Generate `template ledger` with the reconciled helper and set its follow-up fields for the actual
review. Put a review date directly in `review_trigger` when useful; the owner checks it during a
review. The queue does not schedule work. Read
[Drafts, Ledgers, And Cleanup](../../skill-retro/references/state-protocol.md#drafts-ledgers-and-cleanup)
before writing or closing a ledger.

At the first review after the trigger fires, record the observed benefit,
cost, limitations and recommended outcome in the review note:

- **kept:** the benefit justifies the observed recurring cost;
- **adjusted:** evidence supports a specific change to the trial;
- **retired:** the mechanism is not worth retaining;
- **inconclusive:** the available observations cannot settle the hypothesis.

Keep implementation, guidance conformance, and downstream effectiveness as
separate claims. Absence of task evidence is inconclusive. State whether the
current policy remains provisionally in force under existing authority; neither
a date nor an inconclusive result authorizes source changes. Under closure
authority, use `close-ledger` with the outcome and evidence summary in its
rationale. For an adjusted or inconclusive trial, create a successor only when
new evidence or a changed probe warrants one; name the new bounded question and
link it before closing the predecessor. Do not simply renew the observation
window. Report any unapproved action without applying it.
