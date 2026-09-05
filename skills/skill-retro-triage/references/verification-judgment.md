# Verification Judgment

Use for verification proposals and contradicted accepted outcomes. Apply the
parent skill's authority and shared evidence rules. Read the target record and
its exact recorded opportunity, then the protocol's
[Accepted Records And Verification](../../skill-retro/references/state-protocol.md#accepted-records-and-verification)
for evidence bases, typed decisions, eligible transitions, and identity rules.

Choose `apply` or `reject` for each proposal. Apply only to an `accepted` or
`implemented` target when evidence exercises its exact opportunity, its basis
and claim match the observation, and the transition is eligible: `unverified`
to `supported`, or `unverified`/`supported` to `contradicted`. Reject stale,
duplicate, overclaimed, mismatched, or insufficient evidence.

When processing is authorized, use `template verification-decision` and
`process-verification`. Application updates the existing accepted identity and
archives provenance; rejection archives without changing accepted state.
Verification processing does not advance candidate artifact-audit cadence.

Drain contradictions by correcting source and marking the old outcome
`superseded`, removing guidance and marking it `reverted`, or creating an
explicit residual ledger with owner, trigger, next action, and close condition.
Preserve contradictory evidence and the accepted identity. A new identity is
justified only when a corrected decision is itself accepted; use the
[candidate route](candidate-judgment.md) for that change. Before creating a
residual ledger, read the protocol's
[Drafts, Ledgers, And Cleanup](../../skill-retro/references/state-protocol.md#drafts-ledgers-and-cleanup).
When the current task authorizes verification processing alone, report source
or residual-action proposals that still need authority. Finish authorized state
processing with helper validation.
