# Reviewed Improvement Implementation

Use after triage has judged external evidence and implementation is authorized. Carry existing
batch acceptance forward; ask only for decisions or mutations outside that scope.

## State Before Source

Read the protocol's [Installed Helper](state-protocol.md#installed-helper) and
[Triage And Archive](state-protocol.md#triage-and-archive), then archive each complete verdict
before editing source. Preserve original observation or candidate IDs and use `reconsider` for a
fired deferral. Judge
verification proposals separately through the
[verification protocol](state-protocol.md#accepted-records-and-verification).

Keep operational records outside Git. Public changes must be understandable without private
evidence, repository names or opaque state IDs. Losing external bookkeeping does not invalidate a
correct source commit.

## Public Change

Follow `$codex-skill-repo` for authoring, validation, installation parity and publication. Its
[semantic authoring](../../codex-skill-repo/references/semantic-authoring.md) owns placement and
payload judgment. Implement the decision and destination accepted in triage; revisit them only
when current source or new evidence changes the assumptions. Preserve the required behavior and
add appropriate checks for executable changes.

For an already-landed outcome, verify the exact public commit and current destination against the
accepted decision. If no source delta remains, proceed to External Accepted Record using that
commit. Complete any independently required checks, but do not re-land the change, repeat finished
installation/publication work or make an empty commit. Landing alone establishes no later benefit.

For same-decision implementation drift, repair the missed or stale public surface under its
existing accepted identity even when the candidate verdict is `no-change`. Preserve prior commits
and behavioral verification when recording the repair after publication.

When a batch reveals repeated producer mistakes, report the concrete pattern. Change producer
guidance only when recurrence or decisive evidence justifies it within the accepted scope.
Execute agreed ledger actions whose conditions are met and resolve existing legacy drafts rather
than repeatedly refreshing them.

## External Accepted Record

Only after the public commit exists, read
[Accepted Records And Verification](state-protocol.md#accepted-records-and-verification).
For a new outcome, use `prepare-accepted --id RC-ID --commit SHA`, repeating origins or commits
when needed. Complete the blank outcome fields, judge the final destination and evidence, and
submit with `record-accepted`. Preparation supplies lineage and reviewed ancestor context without
treating the original proposal as the implemented outcome; its comments are discarded on recording.
For a state-preservation comparison, use `--allow-action record-accepted:SCR-ID`.

For an existing identity, supply known commits and any changed destination to
`prepare-accepted-update`, review the replacement and submit with `update-accepted`. Retain original
implementation provenance. Store sanitized outcome evidence, trigger and non-trigger, an exact
verification opportunity and known public commits without inventing observations.

Keep disposition and verification independent. Static checks of prose can support implementation,
not effectiveness. Use `deterministic-test` for exercised executable behavior and `later-session`
for an ordinary task with decisive observations. Preserve explicit claim scope; neither conformance
nor occurrence of an intended outcome proves comparative improvement without a comparator.

For a correction, preserve the old identity and contradiction evidence. Create a new accepted
identity only for a newly accepted decision; `record-accepted` derives its supersession links from
the archived review or legacy candidate intake. Close a residual contradiction ledger only after the
old outcome is
superseded, reverted or explicitly retained under the protocol. Same-decision source repair uses
the existing identity and leaves verification unchanged unless qualifying evidence establishes more.

Finish authorized state changes with helper `validate`. If bookkeeping fails after publication,
report the unfinished record update and repair it within scope; do not undo a correct source commit
merely because external state is unavailable.
