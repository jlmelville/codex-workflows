# Verification Judgment

Use when a reviewed observation may support or contradict an existing accepted outcome, or for
existing verification proposals and contradictions. Discover relevant outcomes with bounded
`verification-context --destination TEXT --compact`; expand selected IDs before judging the claim.
For observed harm, use `accepted-records` across all dispositions so inactive identities are
visible. Apply the
parent skill's authority and shared evidence rules. Pass an accepted ID or a proposal ID from
`review-queue` to `verification-context --id ID` to read the target, its exact opportunity, and
selected, applied, and pending proposals together, then read the protocol's
[Accepted Records And Verification](../../skill-retro/references/state-protocol.md#accepted-records-and-verification)
for evidence bases, typed decisions, eligible transitions, and identity rules.

Judge the evidence once. Apply only to an `accepted` or `implemented` target when it exercises the
exact opportunity, its basis and claim match the observation, and the transition is eligible:
`unverified` to `supported`, `unverified`/`supported` to `contradicted`, or
`supported` to `supported` with a materially useful `supplemental_reason`. Judge what a supplement
adds; its presence or a different claim label is insufficient. Preserve known guidance context and
judge independence.

For new evidence that warrants verification, use `prepare-verification`, complete the
claim, opportunity match, basis, evidence and review rationale, and submit once with
`record-verification`. Include original observation IDs in `source_observation_ids`. Processing
needs its own authority; capture authority permits no application or observation closure.
Preparation establishes neither an evidence claim nor acceptance.

Optionally select fully reviewed source observations in `review.close_observation_ids`. The helper
records their closure with the verification reference and preserves original evidence. A source
link alone requests no closure. Leave observations open when another claim, source change or action
still needs review. Legacy candidates and papercuts keep their existing closure paths. Closing an
observation does not resolve the accepted record's contradiction or authorize another owner's work.

When evidence does not warrant verification, record that conclusion on the observation. Defer only a
named unresolved decision. Use `prepare-decision` and `process-verification` only for existing
legacy proposals; rejection preserves accepted state. New legacy creation is retired.

Keep the prepared VP identity and completed input. After interruption, retry unchanged input or
resume with `record-verification --id VP-ID`; the queue retains unfinished work, including closures.
Completed retries change nothing; conflicting input or closure judgments fail. Verification archives
do not advance cadence; observation closures count as ordinary reviews.

When an intervening review prevents completion, make an explicit recovery judgment with processing
authority. Use `record-verification --id VP-ID --reject --rationale TEXT` only before application.
After application, use `--acknowledge-closure RC-ID --rationale TEXT` for each selected observation
already completed by another review. Preserve that review; acknowledgment resolves this submission's
closure obligation, not other work or a contradiction. Open or deferred observations do not qualify.
Ordinary retries use the stored resolution. See command help for retry and conflict rules.

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
