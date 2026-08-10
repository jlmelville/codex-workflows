---
name: learning-process-review
description: Review codex-workflows learning state. Use for papercut review or closure, learning retrospectives, pilot audits, candidate and verification health, drain decisions, and cleanup.
---

# Learning Process Review

Review disposable learning state without turning the public skill repository
into an operational archive. Treat observations as evidence to judge, not work
instructions to execute mechanically.

## Authority

- Default to a read-only review. Report findings and the complete proposed
  drain batch before changing public source or external state.
- Mutate state only after the user explicitly accepts the reported batch. When
  autonomous review and drainage were explicitly requested in advance, report
  the batch as an intermediate update before continuing in the same turn.
- Treat source edits, installs, commits, pushes, messages, and external-owner
  actions as separate mutations requiring applicable authority.
- Apply `$papercut-capture` only to new friction encountered during the review;
  do not use capture authority to close or promote existing records.

## Required Context

1. Confirm `CODEX_WORKFLOWS_STATE_DIR` is set and available. Stop rather than
   inventing a state location.
2. Read
   `${HOME}/.agents/skills/skill-retro/references/state-protocol.md` before any
   state mutation.
3. Start with the installed helper:

   ```sh
   "${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" papercuts
   "${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" pending
   "${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" review-queue
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
deferrals without drains, fired drafts or ledgers, implemented-but-unverified
guidance, contradicted guidance, and missing active domains without treating
unequal report volume as a defect by itself.

## Report

Use these sections:

```md
## Learning Process Retrospective

### Intake Quality
### Papercut Clusters And Drains
### Verdict And Deferral Patterns
### Draft And Ledger Drains
### Verification Health
### Producer Feedback Candidates
### Cleanup Candidates
### No-Action Findings
### Complete Proposed Drain Batch
### Proposed Next Review Trigger
```

During an initial pilot, use all reviewed papercuts as the denominator. Report
actionable yield as unique observations warranting `local-fix`, `candidate`, or
`external-owner`; duplicate rate as `duplicate`; noise rate as `no-action`; and
capture gap as unique observations the mature candidate process probably would
not retain. Run the first review after 10 papercuts or 14 days of substantive
use, whichever comes first. Do not add per-task telemetry, impose a success
quota, or treat zero-count disclosures as proof that no friction was missed.

## Drain And Validate

After acceptance, create required candidate or duplicate targets before closing
their papercuts. Close each record with the helper's typed outcome and rationale.
Route reusable public changes through `$skill-retro-triage`; implement purely
local fixes only within their repository and authorized scope. Delete disposable
history when it no longer improves future judgment.

Finish with:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" validate
```

Report state changes, records left open, validation status, public publication
status, and the next event-based review trigger. After the initial pilot,
default to another review after five new papercuts or 14 days unless an open
drain or verification opportunity provides an earlier meaningful trigger.
