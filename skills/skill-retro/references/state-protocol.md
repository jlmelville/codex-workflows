# External Retrospective State Protocol

`codex-workflows` stores reusable skills and the mechanism for improving them.
It does not store personal cross-repository reports, verdict history, drafts,
ledgers, or audit cadence. Those disposable Markdown documents live beneath a
filesystem root selected by:

```sh
CODEX_WORKFLOWS_STATE_DIR=/path/to/personal/codex-workflows-state
```

The location may be local, mounted, or synchronized by another service. Its
contents are operational state, not a source-of-truth dependency. Losing it
must not invalidate an installed skill or a public source commit.

## Ownership Boundary

Git owns:

- skills and meta-skills;
- deterministic routing and validation code;
- schemas, templates, and temporary self-test fixtures;
- small documentation needed to run the loop.

The configured state root owns:

- open and reviewed papercut observations;
- candidate inbox and processed archive;
- verification-proposal inbox and processed archive;
- curated accepted records and applied verification evidence;
- deferred candidates and uninstalled drafts;
- maintenance ledgers, learning-process audits, and cadence state.

Do not configure the state root inside a Git worktree. The bundled helper
refuses to initialize or write there.

## Layout

`retro-state.rb init` creates:

```text
$CODEX_WORKFLOWS_STATE_DIR/
  state-version
  papercuts/
    inbox/
    archive/
  retrospectives/
    inbox/
    archive/
    accepted/
  verifications/
    inbox/
    archive/
  drafts/
  ledgers/
  audits/
    learning-process/
```

Records are Markdown files with YAML frontmatter. Use one papercut, candidate,
or verification proposal per file so records can be reviewed, promoted,
judged, or deleted independently. Opaque `PC-*`, `RC-*`, and `VP-*` IDs contain
no repository or session name. Accepted `SCR-*` records use an array of
`originating_candidate_ids` so merges and splits remain representable.

Existing schema-version-1 roots without `verifications/` remain valid. `init`
or the first verification route creates both verification directories; a
partially present verification layout is invalid.

## Installed Helper

Use the installed command from arbitrary project repositories:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" --help
```

From this source repository root, the equivalent command is:

```sh
./skills/skill-retro/scripts/retro-state.rb --help
```

Use `--help` for the current operation list and flags, and `template KIND` for
the current record shape and field vocabularies. This protocol owns the
decisions those interfaces cannot make: authority, evidence, operation ordering,
identity, privacy, and recovery.

For state-preservation checks, save a `snapshot` outside the state root and run `compare`.
For supported authorized state operations, repeat `--allow-action ACTION:ID`
to include each selected record's exact footprint and required writer bookkeeping.
Omit allowances for read-only work; see `--help` for supported forms and scope.

The helper performs deterministic mechanics only. The agent owns evidence selection,
sanitization, judgment, destination choice, implementation, and interpretation.
New files publish atomically after their contents are written. Candidate processing and
reconsideration, verification processing, accepted-record updates, ledger closure, and audit
recording share a local writer lock; this does not coordinate synchronized copies on different
machines.

For producer writes, generate the current template, complete it in a temporary
file when practical, and submit it with the matching `--file` operation. These
operations accept `--file -` for standard input. Remove temporary input when
practical, and use the installed helper rather than locating this source checkout.

When `CODEX_WORKFLOWS_STATE_DIR` is unset, templates still work; `route`,
`route-verification`, and `record-papercut` print validated paste-ready input
without writing. Do not silently invent a default state location.

When a configured root is blocked only by the sandbox, retry an authorized write
through the narrowly scoped approval path or explain the durable writable-root
configuration. This does not broaden authority; preserve the paste-ready record
when approval is unavailable or denied.

## Papercut Intake And Closure

A papercut preserves unexpected, avoidable workflow friction before anyone
knows whether it is reusable or who owns the remedy. Required fields are
`source_scope`, `kind`, `observation`, `impact`, `resolution`, `owner_hint`, and
`redaction_review`. `workaround` is optional. The helper validates bounded
vocabularies documented by `template papercut`; `owner_hint` defaults to
`unknown` in that template.

Papercut capture requires explicit authority. Authority may come from standing
user or repository instructions that enable `$papercut-capture`, a task or
session request, or a per-item request. Implicit skill activation alone does
not authorize a write. Standing or session authority permits qualifying records
to be written without interrupting the user each time. Capture authority
permits only new inbox records. It does not authorize closure, candidate
creation or promotion, project edits, commits, pushes, or messages. The
qualification, privacy, fallback, and disclosure workflow lives in
[`$papercut-capture`](../../papercut-capture/SKILL.md).

`papercuts` lists only the open inbox by default. Use `papercuts --archive` only
when reviewed history is relevant. Close each reviewed observation with one of:

```text
no-action
local-fix
candidate
external-owner
duplicate
```

Closure appends `outcome`, `rationale`, and `closed_at` without changing the
digested intake fields, then moves the record to the archive. `duplicate`
requires `--related-papercut-id PC-*`; `candidate` requires
`--related-candidate-id RC-*`, and the formal candidate must exist first. Other
outcomes reject related IDs. Closing requires explicit state-mutation authority
from the review user. If closure is interrupted after archive creation, retry
the same `close-papercut` operation. A matching archive is retained with its
original `closed_at`; a different intake or closure decision is refused.

Do not promote mechanically. Reviewers synthesize a new candidate only when
the observation is reusable, materially missing from current coverage, and has
a justified destination. Repository-local fixes and external-owner actions do
not need to pass through the candidate inbox.

### Historical Classifications

New papercuts use the bounded vocabulary in `template papercut`. Existing records may retain
unfamiliar textual values for `kind`, `impact`, `resolution`, and `owner_hint`; reading or closing
them does not reclassify their intake. Empty or non-text values still fail validation.

The intake digest continues to cover every original field and the evidence body. Any mismatch
fails validation; the helper does not guess prior classifications or rebase digests. Historical
`schema_repairs` receipts remain intact and their digest history is still validated. There is no
repair-writing command. A structural or integrity failure needs separate investigation, not a
classification change.

## Candidate Intake

Generate `template candidate`; the self-contained record preserves the decision
surface without a transcript. New routes require `evidence_lineage` and a note
naming the affected guidance and conditioning boundary. Classify lineage as
`independent` when guidance was inactive; `descendant` when it may have shaped
the work or report; `mixed` for both sources; `unknown` when retained evidence
cannot decide; or `not-applicable` when the claim needs no behavioral use.
Legacy omissions are `unknown`. Grounded descendant evidence can establish a
source gap, conformance, or intended outcome, but repetition alone cannot prove
independent recurrence, transfer, or comparative improvement.

Treat synchronized state as exposed: omit transcripts, tool dumps, credentials,
private source, runtime paths, unredacted home paths, and unnecessary repository
names. User or standing `auto` authority permits only sanitized new inbox
records—not application or other edits, commits, pushes, or messages.

When later evidence changes a previously accepted decision, a new candidate may
add `supersedes_accepted_id` and `now_false`. Use those fields only when the
corrected decision is itself a new candidate. Evidence that merely supports or
contradicts the same decision and witness belongs in a verification proposal
for the existing accepted identity; it does not create a second candidate or
accepted identity.

## Triage And Archive

Triage inspects `review-queue`, re-reads the named destination, and judges every
candidate independently. Verdicts are `accept`, `defer`, `reject`, `split`,
`merge`, or `no-change`. By default, present verdicts and the proposed public
implementation batch before editing source.

Query `accepted-records` before a possible repeat or destination-repair verdict. It searches all
dispositions and states by case-insensitive literal substring: `--destination` matches destinations;
`--text` includes selected metadata, originating candidate IDs, public commits, and the Markdown
body. Repeat either filter to combine terms; see `--help` for matching rules. This identity lookup
also covers inactive outcomes.

Use `prepare-decision --id ID --verdict VERDICT` with an already-reviewed `--rationale TEXT`, or
fill the blank rationale afterward. Deferrals remain incomplete until their substantive fields
are filled, even with a supplied rationale. Decision templates omit optional notes; add them only
when useful. Review the completed decision, then use `process` to attach it and move the record
from inbox to archive. The intake digest and original intake fields remain in the archived
document. For a deferred verdict, first state the `unresolved_decision` that current evidence cannot
justify. Post-implementation behavioral uncertainty is not a deferral: implement the justified
outcome, keep it behaviorally `unverified`, and retain its destination-matched
`verification_opportunity`. If processing is interrupted after archive creation, retry `process`
with the same candidate and decision. The helper verifies the existing archive and removes the
inbox copy; a conflicting archive is refused. Retrying does not add another counted candidate.

Every new or reconsidered candidate deferral names its `unresolved_decision` and includes these
follow-up fields. New open ledgers use the same fields without claiming that an already accepted
but blocked action is an undecided question:

```yaml
owner: "skill-retro-triage"
review_trigger: "Concrete review condition and how the owner checks it."
next_action: "Executable action when the review condition is met."
close_condition: "Condition that resolves or replaces the action."
```

The owner is the person or process responsible for reviewing the action. Put any relevant date,
threshold, named artifact, or missing input directly in `review_trigger`, together with the check
needed to recognize it. `review-queue` lists unresolved work; the reviewer decides whether its
condition is met. The helper does not schedule work or evaluate triggers. Avoid a generic "next
use" condition unless an existing record or query makes that use observable.

Existing records remain readable without migration, including records without an explicit owner.
Legacy `review_trigger_*` metadata is preserved as historical context and is no longer interpreted
as a typed contract. New deferrals and open follow-ups must supply the fields above.

Use `review-queue` as the complete intake and action inventory: pending candidates, open papercuts,
verification proposals, archived deferrals, contradicted accepted outcomes, drafts, ledger actions,
accepted publication gaps, and a due artifact audit. Detailed intake commands remain available for
focused views. Queue presence does not authorize processing or require draining unrelated intake.
An `accepted-publication` row means
an archived `accept` or
`split`, or a `merge` into a publication-bound related outcome, is absent from
every accepted record. A merge into only deferred, rejected, or no-change
outcomes consolidates evidence without creating a publication obligation.
Treat it as advisory reconciliation work: determine whether the public source,
accepted metadata, or both were interrupted, then repair the missing surfaces.
Its presence does not make the state invalid because an active triage
legitimately archives a verdict before publishing source and metadata. Triage
decides which event-based triggers have fired rather than merely refreshing
their dates. Every triage run must inspect that queue before proposing its
batch.

When a deferred candidate's review trigger fires, use `prepare-decision`, complete
the replacement draft, and use `reconsider --id ID --decision PATH`. The helper accepts only a
currently deferred archived candidate and a newer `reviewed_at` timestamp. It
preserves every prior deferral in `triage_history`, replaces the active `triage`,
and leaves a replacement `defer` in the review queue while removing a terminal
replacement verdict from it. Do not direct-edit archived triage state.

For an authorized implementation batch, follow
[report-to-patch.md](report-to-patch.md) for public implementation, validation,
publication, and accepted-record ordering. The source commit must stand on its
own without access to external state and need not expose the candidate ID.

## Accepted Records And Verification

Accepted records remain curated evidence rather than raw intake. Disposition
and verification are independent:

```text
Disposition: accepted | implemented | no-change | superseded | reverted
Verification: unverified | supported | contradicted
Basis:        none | later-session | deterministic-test
```

After the public commit exists, use `prepare-accepted --id RC-ID --commit SHA` for a new outcome.
It prepares explicit linkage and relevant candidate and merge-ancestor context while leaving outcome
judgments incomplete; see `--help` for multiple origins, split outcomes, commits, and defaults.
Complete the blank fields, curate evidence, verify the final destination and public commit, and
review redaction before submitting with `record-accepted`. Recording automatically discards
preparation comments and prior context. Preparation writes no state and establishes neither
implementation nor behavioral verification. For an existing identity, use `prepare-accepted-update`
with chosen `--commit` and `--destination` overrides as needed; see `--help` for their scope.
Review the prepared replacement, then submit with `update-accepted` under the rules below.

Static validation of a prose or trigger edit can justify `implemented`; it does
not prove the guidance improved a later session. Use `deterministic-test` only
for executable contracts actually exercised. Use `later-session` only for an
ordinary task that records the decisive behavior or failure, affected guidance,
and why the observation supports or contradicts it.

Every verification update states exactly what its evidence establishes. A
deterministic test normally supports executable correctness. Later-session
evidence may support conformance to the guidance or occurrence of the intended
outcome. Neither basis establishes comparative improvement without an observed
comparator.

Accepted records may declare `unverified_claims` as a list of distinct, nonblank remaining claim
scopes. Omit it when those scopes have not been assessed; an explicit empty list means none remain
declared. Keep these scopes narrower than broad claim categories when evidence covers only one
boundary. Curate the list with `prepare-accepted-update` and `update-accepted` when a reviewed outcome
changes what remains; proposal application preserves it because resolving a scope requires judgment.

Use `verification-context --destination TEXT --compact` for bounded discovery across destinations
materially involved in a completed task. Repeat destinations to combine them without duplicate
identities; optional `--text` filters narrow expected behavior or opportunities before pagination.
It includes active outcomes in every verification state. Literal filters may omit relevant outcomes;
adjust or omit terms when broader coverage is needed. See `--help` for matching and pagination;
follow `next_offset` when more relevant records remain. Expand accepted or proposal
IDs, including proposal IDs directly from `review-queue`, with `verification-context --id ID`.
It retrieves the original accepted record and each selected, applied, or pending proposal once,
with ID lists recording their roles. Claim summaries retain observations and explicit remaining
scopes. Compact discovery includes the destination and expected behavior for selecting records.
Read their exact opportunities, claims, and evidence before constructing support. Legacy support
without proposal provenance remains limited to the retained evidence.
Both discovery formats expose applied support and contradiction scopes plus declared unverified
claims; do not read the overall status as support for every expected benefit. Missing claim metadata
is unknown, not evidence that every claim has been verified. See command help for the output contract.
The command retrieves context without judging relevance, opportunity match, or supplementation.
Source text and metadata are returned unchanged; repeated prose does not require curation or an
overlap review. Historical `verification_context` metadata remains opaque source data and no longer
controls rendering or validation. Existing overlap manifests remain historical local files and no
longer govern review decisions. No evidence migration is required.

When the task produces decisive evidence for the target's exact opportunity, use
`prepare-verification --id SCR-ID --verification STATE` for the chosen target and proposed state.
Complete the blank evidence and judgment fields, review the proposal, then submit separately with
`route-verification`; see `--help` for context, conditional fields, and eligibility checks.
Another conforming task alone need not add evidence that changes adjudication. A proposal names one
`target_accepted_id`, proposes `supported` or `contradicted`, selects
`later-session` or `deterministic-test`, records the opportunity match and
observation, and classifies its claim as one of:

```text
executable-correctness
guidance-conformance
intended-outcome
comparative-improvement
```

The narrower `verification-opportunities` and `accepted-records --active-supported` views remain
available; ordinary checkpoints use `verification-context` to avoid reconstructing their join.

When observed failure or harm bears on active guidance, use a bounded
`accepted-records --destination TEXT` or `--text TEXT` query to locate the
applicable identity across all dispositions, then expand it with `verification-context --id ID`.
Route a contradiction only when the evidence
addresses that record's claim and opportunity. Use a candidate when the
decision itself changes.

Contradicted proposals must also state `what_is_false`; supported proposals
must not. Further support when support is pending or the target is supported
requires `supplemental_reason`: what the evidence materially adds beyond existing
support, such as a previously untested boundary or a stronger warranted claim.
A different task or claim label alone is insufficient. Omit redundant support;
preserve useful supplements and contradictions. Route one proposal per file.
A query hit creates no obligation; routing authority creates only a new inbox file.

Triage selects proposals from `review-queue`, prepares `apply` or `reject` using `prepare-decision`
with a reviewed rationale, and records the result with
`process-verification`. Apply only to an `accepted` or `implemented` target and
only for these transitions:

```text
unverified -> supported
unverified -> contradicted
supported  -> contradicted
supported  -> supported (material supplemental evidence only)
```

Application updates the existing accepted identity's observation, decisive
evidence, verification state and basis, records the `VP-*` provenance, and
creates the structured contradiction mapping when needed. Rejection archives
the proposal without changing the accepted record. Supplemental application
retains both observations, accumulated evidence, and proposal provenance; each
proposal preserves its own basis. Triage must judge the supplemental reason,
not merely its presence. Processing is recoverable
if interrupted between accepted-state replacement and proposal archival: retry
with the same apply decision. An already-applied proposal cannot be rejected,
and a conflicting archive is refused before accepted state changes.
Verification proposal archives do not increment candidate artifact-audit
cadence.

Use `update-accepted --id ID --file PATH` for later disposition, public-source
destination, evidence curation, or commit updates; use the typed proposal path
for new verification evidence. Generic updates reject changes to verification
state or basis. Start with `prepare-accepted-update --id ID`; the helper
preserves `accepted_id`, `accepted_at`, and prior
`implementation_commits`, appending new commits without duplicates.
It requires the originating candidate, supersession lineage, and applied
proposal IDs to remain intact. A pure relocation uses this existing identity
and retains its verification state and basis. Do not direct-edit the stored
record or create a second accepted identity for the same outcome merely to
record later evidence.

A newly contradicted record includes:

```yaml
contradiction:
  summary: "What the later evidence establishes."
  what_is_false: "What the accepted outcome asserted that is now false."
  recorded_at: "YYYY-MM-DDTHH:MM:SSZ"
  decisive_evidence:
    - "Sanitized later-session or deterministic evidence."
  residual_ledger_id: LE-YYYYMMDD-abcdef # optional
```

The helper allows legacy schema-version-1 records without this mapping, but any
new or updated contradicted record must supply it. Once present, verification
cannot move away from `contradicted`; its summary, false assertion, timestamp,
and prior decisive evidence cannot be removed. Later evidence may be appended.

Resolve a contradiction by correcting guidance and marking the old record `superseded`, removing
guidance and marking it `reverted`, or retaining still-valid guidance after reviewing the failure.
For retention, use `prepare-accepted-update` and `update-accepted` to add:

```yaml
contradiction:
  # Preserve the existing contradiction fields and evidence.
  resolution:
    outcome: retained
    rationale: "Why the guidance remains appropriate despite the observed failure."
    resolved_at: "YYYY-MM-DDTHH:MM:SSZ"
```

Retention requires an authorized judgment that no source change or further action is warranted. It
does not establish successful application: preserve `verification: contradicted`, valid positive
evidence, and proposal provenance. The timestamp cannot predate the contradiction. Material new
evidence may reopen review by removing the resolution through `update-accepted`; preserve the
contradiction itself.

Until resolved, the record remains in `review-queue`. Assigning an open residual ledger with an
owner, trigger, next action, and close condition transfers the live action to that ledger; it does
not resolve it. A residual ledger cannot close until its accepted record is superseded, reverted, or
explicitly retained. Preserve `verification: contradicted` after resolution.

When archived correction candidates name earlier outcomes, `record-accepted`
derives and preserves `supersedes_accepted_ids`.

Occasional authoring checks follow the
[bounded forward-testing guidance](../../codex-skill-repo/references/semantic-authoring.md#bounded-forward-testing).
They do not replace the typed verification evidence required here.

## Drafts, Ledgers, And Cleanup

New draft creation is retired. Keep an undecided proposal as a deferred candidate with its missing
evidence and unresolved decision. Use a ledger for an agreed future action, implementation blocker,
or maintenance hypothesis. Its Markdown body can hold provisional skill text, conventions, and
readiness criteria without another record type or required fields. Create it with `template ledger`
and `record-ledger`, using the owner, review condition, next action, and close condition from
[Triage And Archive](#triage-and-archive).

Existing `SD-*` drafts remain readable and validated without migration. Their IDs, evidence,
metadata, and audit references remain intact. `open` and `revised` drafts still appear in
`review-queue`; `activated` and `deprecated` drafts remain historical records. Review and resolve
existing drafts within the invoking task's authority. The helper no longer offers `template draft`
or `record-draft`.

Close an open maintenance ledger through `close-ledger`. The helper preserves
the record, marks it closed, updates `last_reviewed`, and adds a UTC closure
timestamp and rationale. It rejects missing and already closed ledger IDs.
Legacy closed records without structured closure metadata remain valid.

This state is deliberately disposable. Delete closed papercuts, rejected
history, stale audit material, discharged ledger entries, and superseded drafts
whenever they no longer help future judgment. The public repository must not
rely on retention.

## Completed Audits And Artifact Cadence

`audits/learning-process` stores completed, sanitized system diagnoses. Generate
`template audit`, create every unresolved consequence first as an existing
candidate deferral or ledger action with the required follow-up fields,
list those IDs in `unresolved_action_ids`, and use `record-audit --file PATH`
only after the user has authorized the external-state mutation. The helper
requires each listed action to exist and be open when the audit is recorded. Existing open legacy
drafts may still be referenced; historical audit references remain validated after actions close.
Completed audits stay cold; only their unresolved action records belong in
`review-queue`.

Use `audit_kind: learning-process` for feedback-loop diagnoses and
`audit_kind: skill-repository` for completed report-only artifact audits. The
helper derives an approximate reminder from retained candidate archives and the latest completed
`skill-repository` audit:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" artifact-audit-status
```

The default reminder becomes due at ten retained candidates whose first triage `reviewed_at` is
later than that audit's `completed_at`. For reconsidered candidates, the earliest `triage_history`
entry supplies the original review time. With no retained repository audit, count all retained
candidate archives. Learning-process audits and verification proposals do not reset or advance
this count. Use `--archive-threshold N` for a different reminder threshold.

This is an advisory estimate. Pruning archives can reduce it; backdated reviews or activity at the
audit timestamp can delay the reminder. It does not measure source-change volume. Status queries
write nothing. The old `artifact-cadence.yml` file and counter metadata in historical audits are
preserved but no longer used for scheduling. No migration or counter repair is required.

`record-audit --file PATH` atomically publishes a fresh completed audit. Its publication supplies
the next reminder cutoff; there is no separate cache update. After an interrupted or lost response,
inspect `audits` and `show --id LA-ID` before deciding whether a fresh record is needed. An already
published audit needs no recovery write; the former `record-audit --id` option is retired. A failed
publication supplies no new cutoff. The shared writer lock, atomic publication, evidence checks,
and open-action validation remain in force.

Due state authorizes only the report described by `prompts/skill-repository-retrospective.md`; it
never authorizes source edits or automatic corpus rewrites. `artifact-audit-status` retains its
five tab-separated fields: status (`due` or `not-due`), approximate candidate count since the
cutoff, configured threshold, latest repository-audit ID (or `none`), and latest audit path (or `-`).

## Validation Boundary

Run `retro-state.rb validate` explicitly against live state. Repository CI and
`./scripts/validate-skills.sh` exercise only temporary fixtures through the
helper self-test; they never read `CODEX_WORKFLOWS_STATE_DIR`.
