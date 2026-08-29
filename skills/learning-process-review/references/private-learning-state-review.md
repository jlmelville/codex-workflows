# Private Learning-State Review

Use this only for a review of external learning state or a broader process
retrospective. A direct public artifact audit uses the route in the parent
skill and does not inspect private state as evidence.

## Context

1. Confirm `CODEX_WORKFLOWS_STATE_DIR` is set and available. Stop rather than
   inventing a state location.
2. Read
   `${HOME}/.agents/skills/skill-retro/references/state-protocol.md` before any
   state mutation.
3. Start with the installed helper:

   ```sh
   "${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" papercuts
   "${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" pending
   "${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" pending-verifications
   "${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" review-queue
   "${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" artifact-audit-status
   ```

4. Read every open papercut. Read archived papercuts only when recurrence,
   prior closure, cleanup, or pilot metrics require them.
5. Inspect only the processed candidates, accepted records, drafts, ledgers,
   and audits needed to judge verdict patterns, fired triggers, verification,
   producer quality, or cleanup.

Treat synchronized state as potentially exposed. Do not reproduce credentials,
private source, raw transcripts, unredacted local paths, or unnecessary private
repository names in the report.

## Judgment

Classify each reviewed papercut as one of:

- `no-action`: useful observation, but no remedy is warranted;
- `local-fix`: the remedy belongs only to the originating repository;
- `candidate`: a reusable, materially missing kernel is ready for
  `$skill-retro` and later `$skill-retro-triage`;
- `external-owner`: another owner must act;
- `duplicate`: an existing papercut owns the same evidence and drain.

Do not promote mechanically. Name the exact missing delta and smallest owner.
Keep repository-local wrappers out of reusable candidates. For a candidate
closure, create the formal candidate first so the typed reference exists. For
duplicates, identify the surviving papercut first.

Evaluate candidate verdict distributions, repeated construction mistakes,
deferrals without drains, fired drafts or ledgers, stale or repeatedly rejected
verification proposals, implemented-but-unverified guidance, contradicted
guidance, and missing active domains without treating unequal report volume as
a defect by itself.

Inspect a small, high-information sample of downstream work: owner-rejected or
radically simplified plans, review growth above its scope threshold, abandoned
plans, replacements of proven implementations, and explicit owner praise or
blame. Prefer actual plans, diffs, timestamps, and owner corrections over agent
self-report. For each affected skill record:

```text
Downstream artifacts inspected:
Observed effect: helpful, neutral, harmful, or unknown
Observed cost: negligible, material, severe, or unknown
Evidence limitations:
Behavioral conclusion:
```

Plan-to-diff size may identify an anomaly but is never a target or sufficient
verdict. Do not infer utility from conformance or successful completion alone.

Aggregate behavioral evidence that an existing skill made ordinary work worse,
including misactivation, unnecessary sequencing, displaced simpler approaches,
stale assumptions, or procedural compliance that missed the user's objective.
Route repeated or decisive evidence toward trigger narrowing, qualification,
decomposition, supersession, or removal. Leave the provenance-blind artifact
audit to identify structural risk factors rather than claiming behavioral
incidents it cannot observe.

Supervise semantic curation at the process level:

- whether triage keeps adding incident-shaped default rules instead of changing
  a distinguishable decision;
- whether repository retrospectives detect compressible decision clusters;
- whether accepted compression recommendations land or remain undrained;
- whether optional casebooks become provenance-organized dumps; and
- whether contradicted guidance reaches correction, removal, or an executable
  residual ledger.

Inspect the artifact-audit report and its actions; do not repeat its
artifact-by-artifact compression work inside this review. When
`artifact-audit-status` is due, use the parent skill's public artifact-audit
route under the authority of the invoking task. Due cadence never authorizes
source edits.

For every proposed candidate deferral, first name the decision that current
evidence cannot justify. Later behavioral uncertainty after a justified
implementation belongs in an unverified accepted outcome, not a deferral.
Candidate deferrals, open drafts, and open ledgers must each name their trigger
predicate, observer, `review-queue` route, executable probe, next action, and
close condition. Reject a durable description without a liveness path.

## Report

Use these sections:

```md
## Learning Process Retrospective

### Intake Quality
### Papercut Clusters And Drains
### Verdict And Deferral Patterns
### Draft And Ledger Drains
### Verification Health
### Downstream Outcome Evidence
### Artifact Audit Supervision
### Producer Feedback Candidates
### Cleanup Candidates
### No-Action Findings
### Complete Proposed Drain Batch
### Proposed Next Review Trigger
```

Report control-plane counts only as control-plane evidence. End with separate
conclusions:

```text
Structural status: healthy or findings present
Behavioral effectiveness: supported, mixed, harmful mode observed, or unknown
```

Only downstream artifacts can support the second conclusion. Otherwise write:
`Insufficient downstream evidence to assess behavioral effectiveness.` Do not
add per-task telemetry, success quotas, or verdict quotas; zero counts do not
establish complete capture. Review after 10 papercuts or 14 days during the
pilot.

## Drain And Validate

After acceptance, create required candidate or duplicate targets before closing
their papercuts. Close each record with the helper's typed outcome and rationale.
Route reusable public changes through `$skill-retro-triage`; implement purely
local fixes only within their repository and authorized scope. Delete disposable
history when it no longer improves future judgment.

After the applicable mutation gate, record the complete sanitized diagnosis as
`template audit` with `audit_kind: learning-process`. First create every
unresolved executable consequence as a candidate deferral, draft, or ledger and
list those IDs in `unresolved_action_ids`. Create no unresolved actor until it
passes the shared structured trigger contract. A completed diagnosis stays cold
in audit history; only its unresolved actors remain in `review-queue`.

Finish with:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" validate
```

Report state changes, records left open, validation status, public publication
status, and the next event-based review trigger. After the initial pilot,
default to another review after five new papercuts or 14 days unless an open
drain or verification opportunity provides an earlier meaningful trigger.
