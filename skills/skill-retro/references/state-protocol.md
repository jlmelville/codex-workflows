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

- observation inbox and reviewed archive, including legacy candidates;
- existing papercut inbox and archive;
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

Records are Markdown files with YAML frontmatter. Capture each distinct observation once.
Review decisions stay with the original evidence; accepted outcomes and typed verification
proposals record separate judgments. Opaque `PC-*`, `RC-*`, and `VP-*` IDs contain
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

When `CODEX_WORKFLOWS_STATE_DIR` is unset, templates still work; `route` and `record-observation`
print validated paste-ready input without writing. Do not silently invent a default state location.

When a configured root is blocked only by the sandbox, retry an authorized write
through the narrowly scoped approval path or explain the durable writable-root
configuration. This does not broaden authority; preserve the paste-ready record
when approval is unavailable or denied.

## Observation Intake

Use `template observation` and `record-observation --file PATH` for all new capture. Required
content is a title, sanitized source scope, the observation, bounded `decisive_evidence` and a
redaction review. Keep guidance in use, impact, workaround, outcome and hypotheses in the body
when known. Capture does not require a remedy, taxonomy, owner, skill destination or proof of reuse.

Observations use `record_type: observation` in the existing `retrospectives/inbox` and archive.
Their `RC-*` IDs and `candidate_id` field retain the established identity and reference format;
these storage names do not classify an observation as a proposed skill. No migration is required.
The digest covers original fields and the evidence body. Review appends its decision and preserves
that evidence; never copy a new observation into a candidate merely to make it reviewable.

User or standing capture authority permits only sanitized new inbox records. It does not authorize
classification of existing records, closure, verification application, source edits, commits, pushes
or messages. Treat synchronized state as exposed. The capture and privacy workflow lives in
[`$skill-retro`](../SKILL.md); `$papercut-capture` is a compatibility entry to that same workflow.

## Candidate Intake

Existing `record_type: candidate` records retain their original required fields, lineage, IDs,
digests and review history. `route` remains a compatibility command for complete legacy candidate
input or observations. New producers use `template observation` and `record-observation`.
The old candidate and papercut templates and `record-papercut` command are retired.

Review owns reuse, destination, confidence and evidence-lineage judgments. Missing historical
lineage is `unknown`. Grounded descendant evidence may establish a gap, conformance or intended
outcome; repetition alone does not prove independent recurrence, transfer or comparative
improvement.

## Papercut Intake And Closure

Existing `PC-*` observations remain readable through `papercuts`, `show` and `review-queue`.
Preserve their original classifications and evidence. No new papercut stream is created.
Legacy closure uses `no-action`, `local-fix`, `candidate`, `external-owner` or `duplicate`.
Closure appends the rationale and timestamp and archives the record without changing intake.

A duplicate needs an existing `PC-*` target. A legacy `candidate` closure needs an existing `RC-*`
target first; this compatibility link does not accept or implement a change. Other outcomes reject
related IDs. Reviewers judge the remedy; local-fix and external-owner labels grant no edit or
message
authority. Closing requires applicable state-processing authority, separate from capture.

After an interrupted closure, retry the same operation. A matching archive retains its original
closure timestamp; a different intake or decision is refused. Historical classification text and
`schema_repairs` receipts remain readable and validated without rewriting digests. Empty or
malformed
fields and evidence mismatches still fail. There is no repair-writing command.

## Triage And Archive

Triage reads selected observations from `review-queue`, judges the evidence and checks relevant
coverage. Use `local-fix`, `external-owner` or `no-change` for those outcomes; `reject` for an
unsupported proposal; `accept`, `split` or `merge` for justified shared changes; and `defer` for a
named decision awaiting evidence. Record the rationale and reviewed scope in the decision or notes.
Classification grants no source, messaging or existing-state authority. Present the proposed batch
before changes unless that scope is already authorized.

Query `accepted-records` before a possible repeat or destination-repair verdict. It searches all
dispositions and states by case-insensitive literal substring: `--destination` matches destinations;
`--text` includes selected metadata, originating candidate IDs, public commits, and the Markdown
body. Repeat either filter to combine terms; see `--help` for matching rules. This identity lookup
also covers inactive outcomes.

For an accepted or split observation, fill `evidence_lineage` and `evidence_lineage_note` in the
review decision. Preparation leaves them blank. Use `independent` when relevant guidance was
inactive, `descendant` when it may have conditioned the work or report, `mixed` for both, `unknown`
when the context cannot decide, and `not-applicable` for claims needing no behavioral use.
For a correction, put `supersedes_accepted_id` and `now_false` in the review decision.
Legacy intake links and prior review references stay intact.

Use `prepare-decision --id ID --verdict VERDICT` with an already-reviewed `--rationale TEXT`, or
fill the blank rationale afterward. For `no-change`, `local-fix` or `external-owner`, a supplied
rationale completes the decision: submit it through `process --decision -` or a file, without
additional form editing or shared-change analysis. For other verdicts, complete the applicable
fields and review the decision before submission. Deferrals still require their substantive fields;
add optional notes only when useful. `process` attaches the decision and moves the record
from inbox to archive. The intake digest and original intake fields remain in the archived
document. For a deferred verdict, first state the `unresolved_decision` that current evidence cannot
justify. Post-implementation behavioral uncertainty is not a deferral: implement the justified
outcome, keep it behaviorally `unverified`, and retain its destination-matched
`verification_opportunity`. If processing is interrupted after archive creation, retry `process`
with the same candidate and decision. The helper verifies the existing archive and removes the
inbox copy; a conflicting archive is refused. Retrying preserves the single candidate archive.

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

Use `review-queue` as the complete inventory: observations, legacy candidates and papercuts,
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
Use the original reviewed observation IDs in `originating_candidate_ids`; the historical field name
also covers observations. No separate candidate is needed.
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

For a concrete observation that may verify existing guidance, use
`verification-context --destination TEXT --compact` for bounded discovery of relevant destinations.
Repeat destinations to combine them without duplicate identities; optional `--text` filters narrow
expected behavior or opportunities before pagination.
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

For new evidence that warrants verification, use
`prepare-verification --id SCR-ID --verification STATE`. Complete the claim, evidence and
`review.rationale` in this one document, then submit with `record-verification --file PATH` (or `-`
for stdin). The prepared review holds a stable VP identity and timestamp; retain them for retries.
Preparation writes no state and grants no authority. Processing requires authority to apply the
verification and any selected observation closures. See command help for fields and recovery.

New legacy proposal creation is retired: `route-verification` refuses without writing. Existing
proposals remain valid and processable; `--reviewed` is accepted but no longer selects a mode.
For a new observation that does not warrant verification, record the review conclusion on that
observation; no rejected proposal is required.

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
available; use `verification-context` when joined evidence is needed.

When observed failure or harm bears on active guidance, use a bounded
`accepted-records --destination TEXT` or `--text TEXT` query to locate the
applicable identity across all dispositions, then expand it with `verification-context --id ID`.
Record a contradiction only when the evidence addresses that record's claim and opportunity. Use
a candidate when the decision itself changes.

When an observation supplies evidence, include its `RC-*` or legacy `PC-*` ID in
`source_observation_ids`. The helper validates linked identities and original digests at submission
and application, and retains those dependencies during full-state checks. Existing proposals without
source links remain valid. A source link alone establishes no claim, permission or closure.

For optional closure, set `review.close_observation_ids` to selected source records whose entire
review is complete. This path closes new `record_type: observation` records; legacy candidates and
papercuts keep their existing closure operations. Omit selections by leaving the list empty. The
helper records a `no-change` intake decision linked to the verification and the supplied rationale,
without altering original evidence. A closure resolves intake review, not an accepted contradiction
or an outstanding source change. Preserve observations needed for further decisions or actions.

The `verification-proposal` format and `VP-*` identities remain. Immutable `review` records intent;
archival adds matching `triage`. Under the shared writer lock, the helper validates current target,
evidence and selected closures, publishes intent, applies and archives verification, then closes
selected observations. Removing verification inbox last keeps interrupted work in `review-queue`.
Writes are individually atomic; the whole sequence is recoverable rather than one transaction.

Retry the unchanged input after interruption or a lost response. After intent was published,
`record-verification --id VP-ID` resumes the stored review; a completed retry is a no-op. Keep the
original prepared identity rather than preparing another submission. Changed input or conflicting
closure decisions are refused. A matching observation archive/inbox pair from an interrupted
selected closure can resume; other ambiguous sources still fail. Legacy decision commands do not
override a reviewed submission's stored intent. No state migration is required.

Contradicted proposals must also state `what_is_false`; supported proposals
must not. Further support when support is pending or the target is supported
requires `supplemental_reason`: what the evidence materially adds beyond existing
support, such as a previously untested boundary or a stronger warranted claim.
A different task or claim label alone is insufficient. Omit redundant support;
preserve useful supplements and contradictions. A query hit creates no obligation or authority.

For existing legacy proposals, select from `review-queue`, prepare `apply` or `reject` using
`prepare-decision` with a reviewed rationale, and submit with `process-verification`. Both
processing paths apply only to an `accepted` or `implemented` target and only for these transitions:

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
Verification archives do not increment artifact-audit cadence. Explicit observation closures count
as ordinary observation reviews.

Use `update-accepted --id ID --file PATH` for later disposition, public-source
destination, evidence curation, or commit updates; use a reviewed submission for new verification
evidence. Generic updates reject changes to verification
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

When a reviewed correction names an earlier outcome, `record-accepted` derives and preserves
`supersedes_accepted_ids` from its review or legacy intake.

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

The public repository does not depend on retaining operational history. Within authorized cleanup,
prune obsolete records only when no retained record references them. Closed ledgers and legacy
drafts may still be referenced by audits. Observation origins, verification source links,
supersession links and applied proposals also remain integrity dependencies. Preserve referenced
records. Validate after pruning;
do not rewrite evidence or remove links merely to make deletion pass.

## Completed Audits And Artifact Cadence

`audits/learning-process` stores completed, sanitized diagnoses. Generate `template audit` and
link agreed executable follow-ups needing tracking in `unresolved_action_ids`. Reuse existing open
deferrals or ledgers; create new ones only within authority. Optional ideas and inconclusive
questions stay in the report, and an audit may have no action IDs. Unresolved contradictions retain
their existing queue obligation until resolved or transferred to an open residual ledger.
Use `record-audit --file PATH` only after state recording is authorized. Each listed action must
exist and be open. Open legacy drafts may still be referenced, and historical audit references
remain validated after actions close. Completed audits stay cold; open actions enter the queue.

Use `audit_kind: learning-process` for feedback-loop diagnoses and
`audit_kind: skill-repository` for completed report-only artifact audits. The
helper derives an approximate reminder from retained candidate archives and the latest completed
`skill-repository` audit:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" artifact-audit-status
```

The default reminder becomes due at ten retained observations or legacy candidates whose first
triage `reviewed_at` is
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

Due state is advisory: it neither expands the current task nor authorizes source edits. Use
`prompts/skill-repository-retrospective.md` for a requested or justified full audit within scope;
a focused review does not reset its reminder. `artifact-audit-status` retains five tab-separated
fields: status (`due` or `not-due`), approximate candidate count since the cutoff, configured
threshold, latest repository-audit ID (or `none`), and latest audit path (or `-`).

## Validation Boundary

Run `retro-state.rb validate` explicitly against live state. Repository CI and
`./scripts/validate-skills.sh` exercise only temporary fixtures through the
helper self-test; they never read `CODEX_WORKFLOWS_STATE_DIR`.
