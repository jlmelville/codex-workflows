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
"${CODEX_HOME:-$HOME/.codex}/skills/skill-retro/scripts/retro-state.rb" --help
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
template accepted
record-accepted --file PATH
template draft
record-draft --file PATH
template ledger
record-ledger --file PATH
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

## Triage And Archive

Triage reads `pending`, re-reads the named destination, and judges every
candidate independently. Verdicts are `accept`, `defer`, `reject`, `split`,
`merge`, or `no-change`. By default, present verdicts and the proposed public
implementation batch before editing source.

Use `template decision`, fill the verdict and rationale, then use `process` to
attach the decision and move the record from inbox to archive. The intake
digest and original intake fields remain in the archived document. For a
deferred verdict, `review_trigger`, `next_action`, and `close_condition` are
required. Use `review-queue` to list open archived deferrals, drafts, and ledger
actions; triage decides which event-based triggers have fired rather than merely
refreshing their dates.

After user acceptance, implement the smallest reusable public change. The
source commit must stand on its own without access to external state and need
not expose the candidate ID. After the commit exists, create or update an
external accepted record with its implementation commit when useful.

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

This state is deliberately disposable. Delete closed papercuts, rejected
history, stale audit material, discharged ledger entries, and superseded drafts
whenever they no longer help future judgment. The public repository must not
rely on retention.

## Validation Boundary

Run `retro-state.rb validate` explicitly against live state. Repository CI and
`./scripts/validate-skills.sh` exercise only temporary fixtures through the
helper self-test; they never read `CODEX_WORKFLOWS_STATE_DIR`.
