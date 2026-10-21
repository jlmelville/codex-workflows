# Verification Judgment

Use for verification proposals and contradicted accepted outcomes. Apply the
parent skill's authority and shared evidence rules. Pass an accepted ID or a proposal ID from
`review-queue` to `verification-context --id ID` to read the target, its exact opportunity, and
selected, applied, and pending proposals together, then read the protocol's
[Accepted Records And Verification](../../skill-retro/references/state-protocol.md#accepted-records-and-verification)
for evidence bases, typed decisions, eligible transitions, and identity rules.

Choose `apply` or `reject` for each proposal. Apply only to an `accepted` or
`implemented` target when evidence exercises its exact opportunity, its basis
and claim match the observation, and the transition is eligible: `unverified`
to `supported`, `unverified`/`supported` to `contradicted`, or `supported` to
`supported` with a materially useful `supplemental_reason`. Judge what the
supplement adds beyond existing support; its presence or a different claim
label alone is insufficient. Reject stale,
duplicate, overclaimed, mismatched, or insufficient evidence.

When processing is authorized, use `prepare-decision --id ID --verdict VERDICT` with a reviewed
`--rationale TEXT`, or fill the blank afterward. Review the decision, then use
`process-verification`. Application updates
the existing accepted identity and archives provenance; rejection archives
without changing accepted state.
Verification processing does not advance candidate artifact-audit cadence.

Resolve contradictions by correcting source and marking the old outcome `superseded`, removing
guidance and marking it `reverted`, or recording a justified retention under the protocol. Retain
guidance when the observed failure does not warrant changing it and no further action remains;
preserve `verification: contradicted`, valid positive evidence, and the accepted identity. For work
that remains, create a residual ledger with owner, trigger, next action, and close condition.
A new identity is justified only when a corrected decision is itself accepted; use the
[candidate route](candidate-judgment.md) for that change. Before creating a residual ledger, read
the protocol's
[Drafts, Ledgers, And Cleanup](../../skill-retro/references/state-protocol.md#drafts-ledgers-and-cleanup).
When the current task authorizes verification processing alone, report source
or residual-action proposals that still need authority. Finish authorized state
processing with helper validation.
