# Private Learning-State Review

Use only for external learning-state or broader process retrospectives. Direct
public artifact audits use the parent route and no private-state evidence.

## Context

1. Confirm `CODEX_WORKFLOWS_STATE_DIR` is set and available. Stop rather than
   inventing a state location.
2. Read
   `${HOME}/.agents/skills/skill-retro/references/state-protocol.md` before any
   state mutation.
3. Start with the installed helper; use `show --id ID` for record contents:

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

For a ledger's fixed cohort of fresh completed sessions, use this source repository's
[select-session-sample.py](../scripts/select-session-sample.py) with its catalog,
workspace, cutoff, and count; use repeatable `--explain-id ID` for eligibility
explanations. See `--help`; freeze its private manifest outside Git and learning
state before reading outcomes, retaining its completion boundaries.

For local message searches or bounded excerpts, use this source repository's
[search-session-messages.py](../scripts/search-session-messages.py); see `--help`.
For frozen cohorts, pass each session's completion boundary with `--before`.
Keep raw excerpt output private, outside Git and learning state; sanitize saved evidence.

Treat synchronized state as potentially exposed. Exclude credentials, private
source, raw transcripts, unredacted paths, and unnecessary repository names.

## Judgment

Use the shared [papercut review and drain](../../skill-retro-triage/references/papercut-drain.md)
for classification and authorized closure. Review the full open inbox here,
including clusters left outside bounded triage batches and the pilot's benefit
and review cost.

Evaluate verdict distributions, repeated construction mistakes, undrained
deferrals, fired drafts or ledgers, stale or rejected verification proposals,
implemented-but-unverified or contradicted guidance, and missing active domains.
Unequal report volume is not itself a defect.

Inspect a high-information sample of rejected or simplified plans, excessive
review growth, abandoned plans, replaced proven implementations, and owner
praise or blame. Prefer artifacts, timestamps, and owner corrections. Record:

```text
Downstream artifacts inspected:
Observed effect: helpful, neutral, harmful, or unknown
Observed cost: negligible, material, severe, or unknown
Evidence limitations:
Behavioral conclusion:
```

Plan-to-diff size may identify an anomaly but is never a target or sufficient
verdict. Do not infer utility from conformance or successful completion alone.

Within an already-due review, select a few learned rules relevant to the evidence
and use the [canonical investigation prompt](../../../prompts/learning-process-investigation.md)
for their decision, value, and cost assessment. When task evidence is available,
trace one selected lesson using the same guidance. Fold findings into the
existing review note; this supplies the downstream investigation required here
without adding a review pass or report.

Aggregate evidence of harmful guidance and route repeated or decisive findings
toward narrowing, qualification, decomposition, supersession, or removal; the
public audit may report risk, not unobserved behavioral incidents.

Supervise whether triage adds incident-shaped rules without changing a decision,
retrospectives find compressible clusters, accepted compression lands, casebooks
become provenance dumps, and contradicted guidance reaches correction, removal,
or an executable residual ledger.

Inspect the artifact-audit report and actions without repeating its item-level
work. When `artifact-audit-status` is due, use the parent route under the
invoking task's authority; cadence never authorizes source edits.

For a candidate deferral, name the decision current evidence cannot justify.
Later behavioral uncertainty belongs in an unverified accepted outcome. Every
deferral, draft, or ledger needs a trigger predicate, observer, `review-queue`
route, executable probe, next action, and close condition.

Review due [loop experiments](loop-experiments.md) alongside other ledger
actions. Report their benefit, operating cost, evidence limits and outcome;
source conformance or more records alone does not establish effectiveness.

## External Orientation

During every full learning-process review, use `https://mattwood.fyi/` as a
bounded source of outside arguments, never as authority or ordinary task
context. Check `https://mattwood.fyi/feed.json` since the last completed review;
without a date, inspect only the newest items.

Select at most three: a direct match for local evidence, a credible challenge to
a decision, and an adjacent surprise suggesting another cause or owner. Fewer,
including zero, is valid. Read original sources; summaries and graph edges are
retrieval hints only.

For each, report the local question and evidence, external claim, strongest
limitation, decision delta, and `ignore`, `probe`, or `candidate` disposition.
Default to `ignore`. Novelty is not local evidence; a probe must distinguish
expected benefit from cost, and a candidate still needs local admission
evidence. Create no feed cursor, registry, job, or ordinary task-agent context.

Between reviews, consult it only for an unresolved choice or a large,
settled-looking addition.

## Report

When proposing or assessing a material learning-loop change, lead with a
compact cost summary for a stated observation window. Reuse available state
counts, source diffs, drift results, and evidence of agent work and owner
attention. Distinguish inherited cost from the change's delta and mark
unavailable measures unknown; use existing outputs without new counters,
fields, or a separate collection pass.
Where relevant, separate growth in default instructions, routed references,
and tests/fixtures, and include already-available comparable validation
timings; treat counts as review leads.

```md
## Learning Process Retrospective

### Intake Quality
### Papercut Clusters And Drains
### Verdict And Deferral Patterns
### Draft And Ledger Drains
### Loop Experiment Outcomes
### Verification Health
### Downstream Outcome Evidence
### External Orientation
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

Only downstream artifacts support the second conclusion; otherwise write
`Insufficient downstream evidence to assess behavioral effectiveness.` Add no
telemetry or quotas; zero counts do not prove capture. In the pilot, review
after 10 papercuts or 14 days.

## Drain And Validate

After acceptance, create candidate or duplicate targets before closing their
papercuts with typed outcomes. Route reusable changes through
`$skill-retro-triage`, keep local fixes local, and delete disposable history
when it no longer improves judgment.

After the mutation gate, record the sanitized diagnosis as `template audit`
with `audit_kind: learning-process`. First create each unresolved consequence as
a deferral, draft, or ledger and list its ID in `unresolved_action_ids`. Keep the
diagnosis cold; only actors passing the trigger contract enter `review-queue`.

Finish with:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" validate
```

Report state changes, open records, validation and publication status, and the
next trigger. After the pilot, review after five papercuts or 14 days unless an
open drain or verification opportunity gives an earlier meaningful trigger.
