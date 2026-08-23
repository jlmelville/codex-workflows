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
- curated accepted records and later verification evidence;
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
  drafts/
  ledgers/
  audits/
    learning-process/
```

Records are Markdown files with YAML frontmatter. Use one papercut or candidate
per file so records can be reviewed, promoted, judged, or deleted
independently. Opaque `PC-*` and `RC-*` IDs contain no repository or session
name. Accepted `SCR-*` records use an array of
`originating_candidate_ids` so merges and splits remain representable.

## Installed Helper

Use the installed command from arbitrary project repositories:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" --help
```

From this source repository root, the equivalent command is:

```sh
./skills/skill-retro/scripts/retro-state.rb --help
```

Key operations are:

```text
template candidate
route --file PATH
pending
template papercut
record-papercut --file PATH
papercuts
papercuts --archive
close-papercut --id ID --outcome OUTCOME --rationale TEXT
template decision
process --id ID --decision PATH
reconsider --id ID --decision PATH
template accepted
record-accepted --file PATH
update-accepted --id ID --file PATH
verification-opportunities [--destination TEXT]
template draft
record-draft --file PATH
template ledger
record-ledger --file PATH
close-ledger --id ID --rationale TEXT
template audit
record-audit --file PATH
audits
artifact-audit-status [--archive-threshold N]
review-queue
validate
```

The helper performs deterministic mechanics only. The agent remains
responsible for evidence selection, sanitization, verdict judgment, destination
choice, implementation, and verification interpretation.

When `CODEX_WORKFLOWS_STATE_DIR` is unset, templates still work, while `route`
and `record-papercut` print the validated input as a paste-ready fallback
without writing anything. Do not silently invent a default state location.

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
from the review user.

Do not promote mechanically. Reviewers synthesize a new candidate only when
the observation is reusable, materially missing from current coverage, and has
a justified destination. Repository-local fixes and external-owner actions do
not need to pass through the candidate inbox.

## Candidate Intake

Generate the current template with `template candidate`. A routed record must
be self-contained because triage will not have the producing conversation. It
captures the decision surface and missing delta without storing a transcript.

Treat even third-party or synchronized state as potentially exposed. Exclude
raw transcripts, tool dumps, credentials, private source, raw runtime-history
paths, unredacted user-home paths, and unnecessary private repository names.
Use bounded error fragments and generalized commands where they are decisive.

Default `$skill-retro` output remains chat-only. `route` requires explicit user
acceptance to write the candidate. `auto` must be explicitly requested and may
write only a high-confidence candidate to the configured inbox; it authorizes
no project edits, source-repository edits, commits, pushes, or messages.

When later evidence changes a previously accepted decision, a new candidate may
add `supersedes_accepted_id` and `now_false`. Use those fields only when the
corrected decision is itself a new candidate. Evidence that merely supports or
contradicts the same decision and witness updates the existing accepted record
instead; it does not create a second accepted identity.

## Triage And Archive

Triage reads `pending`, re-reads the named destination, and judges every
candidate independently. Verdicts are `accept`, `defer`, `reject`, `split`,
`merge`, or `no-change`. By default, present verdicts and the proposed public
implementation batch before editing source.

Use `template decision`, fill the verdict and rationale, then use `process` to
attach the decision and move the record from inbox to archive. The intake
digest and original intake fields remain in the archived document. For a
deferred verdict, `review_trigger`, `next_action`, and `close_condition` are
required. Use `review-queue` to list open archived deferrals, contradicted
accepted outcomes, drafts, ledger actions, accepted publication gaps, and a due
artifact audit. An `accepted-publication` row means an archived `accept` or
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

When a deferred candidate's review trigger fires, create a complete replacement
decision and use `reconsider --id ID --decision PATH`. The helper accepts only a
currently deferred archived candidate and a newer `reviewed_at` timestamp. It
preserves every prior deferral in `triage_history`, replaces the active `triage`,
and leaves a replacement `defer` in the review queue while removing a terminal
replacement verdict from it. Do not direct-edit archived triage state.

After user acceptance, follow
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

Static validation of a prose or trigger edit can justify `implemented`; it does
not prove the guidance improved a later session. Use `deterministic-test` only
for executable contracts actually exercised. Use `later-session` only for an
ordinary task that records the decisive behavior or failure, affected guidance,
and why the observation supports or contradicts it.

Use `update-accepted --id ID --file PATH` for later disposition, verification,
evidence, or commit updates. Supply a complete unassigned accepted document,
like `template accepted`; the helper preserves `accepted_id` and `accepted_at`
and requires the originating candidate and supersession lineage to remain
identical. Do not direct-edit the stored record or create a second accepted
identity for the same outcome merely to record later evidence.

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

Drain a contradiction by correcting source guidance and marking the old record
`superseded`, removing the guidance and marking it `reverted`, or assigning an
open residual ledger with an owner, trigger, next action, and close condition.
Until one of those actions occurs, the contradicted accepted record is itself
visible in `review-queue`; after assignment, only the executable residual
ledger remains live. A residual ledger cannot close while its accepted record
remains unresolved. Preserve `verification: contradicted` on the old identity
after either terminal disposition.

When archived correction candidates name earlier outcomes, `record-accepted`
derives and preserves `supersedes_accepted_ids`. Use
`verification-opportunities --destination TEXT` only as a pull query for the
skills or destinations involved in the completed session. The filter is a
case-insensitive substring match against the recorded destination. A query hit
creates no candidate, quota, or obligation.

Do not create maintained prompt corpora, synthetic model fixtures, repeated
model runs, raw trace archives, paid model-backed CI, or public evidence records
merely to verify skill prose.

## Drafts, Ledgers, And Cleanup

Keep a draft only when there is a coherent new-skill kernel with an intended
trigger, evidence, missing evidence, activation criteria, review trigger, and
close condition. Keep a ledger entry for a cross-report hypothesis or
repository-maintenance threshold. A deferred candidate is evidence awaiting a
specific decision; it is not automatically a draft or ledger entry.

Create drafts and ledger entries from the helper templates so validation can
enforce their owner/status and executable-drain fields. Close, activate,
deprecate, or delete them instead of accumulating generic notes.

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
candidate deferral, draft, or ledger action, list those IDs in
`unresolved_action_ids`, and use `record-audit --file PATH` only after the user
has authorized the external-state mutation. The helper requires each listed
action to exist and be open when the audit is recorded. Completed audits stay
cold; only their unresolved action records belong in `review-queue`.

Use `audit_kind: learning-process` for feedback-loop diagnoses and
`audit_kind: skill-repository` for completed report-only artifact audits. The
helper maintains `audits/learning-process/artifact-cadence.yml` as a monotonic
machine-owned count of processed candidate archives. On first use, it migrates
from the retained archive and any prior audit baseline; later deletion of cold
archive history does not rewind cadence. No per-task or model telemetry is
needed:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" artifact-audit-status
```

The default audit becomes due after ten newly archived candidate reports; use
`--archive-threshold N` to calibrate a review without changing correctness.
Only successfully recording a completed `skill-repository` audit resets the
baseline. An interrupted or failed audit therefore remains due. Due state
authorizes only the report described by
`prompts/skill-repository-retrospective.md`; it never authorizes source edits or
automatic corpus rewrites.

`artifact-audit-status` prints five tab-separated fields in this order: status
(`due` or `not-due`), archives since the baseline, configured threshold, latest
artifact-audit ID (or `none`), and latest audit path (or `-`).

## Validation Boundary

Run `retro-state.rb validate` explicitly against live state. Repository CI and
`./scripts/validate-skills.sh` exercise only temporary fixtures through the
helper self-test; they never read `CODEX_WORKFLOWS_STATE_DIR`.
