---
name: skill-retro-triage
description: Review workflow observations and existing learning records, decide remedies or verification, and complete authorized changes in codex-workflows.
---

# Observation Review

Review the shared observation stream. Decide what an observation warrants without treating its
suggested explanation as an instruction. Existing papercuts, candidates and verification proposals
remain valid input. Operational evidence stays outside Git; public source must stand on its own.

## Authority And Completion

For review requests, report judgments and the proposed batch without changing source or state.
When the user authorizes processing or implementation, describe the concrete actions and continue
within that scope through validation and applicable publication. Carry existing acceptance forward.
Capture authority permits new observations only; it grants no processing, source or messaging
rights.

## Select Context

When public source may change, apply `$repo-update-preflight`, then `$codex-skill-repo`'s
source-reconciliation overlay. Re-read changed guidance. Use the reconciled source helper here and
the installed helper elsewhere; resolve state compatibility before judging or mutating records.

For live intake, validate and inspect the shared queue from the source repository root:

```sh
./skills/skill-retro/scripts/retro-state.rb validate
./skills/skill-retro/scripts/retro-state.rb review-queue
```

Select records relevant to the requested review. The queue includes observations, legacy intake,
deferrals, verification proposals, publication gaps, contradictions, follow-ups and reminders.
It creates no obligation to drain unrelated work. There is no separate papercut co-review pass.
If state is unavailable, report that limit and review supplied evidence without inventing a root.

Read selected records with `show --id ID` and the guidance needed to judge them. Load only the route
needed for the decision:

- Observations, existing candidates, deferrals and shared changes:
  [candidate-judgment.md](references/candidate-judgment.md).
- Evidence about an accepted outcome, proposals or contradictions:
  [verification-judgment.md](references/verification-judgment.md).
- Existing `PC-*` closure: [papercut-drain.md](references/papercut-drain.md).
- Authorized public implementation or publication-gap repair:
  [report-to-patch.md](../skill-retro/references/report-to-patch.md).

Before mutations, read the protocol's
[Installed Helper](../skill-retro/references/state-protocol.md#installed-helper) and the operation's
section. New observations retain their original `RC-*` identity throughout review; do not copy them
into a second candidate merely because a shared change becomes justified.

## Shared Evidence Rules

Judge lineage before recurrence or transfer claims. Known active guidance may have shaped the work
or its report; missing context remains unknown. Grounded descendant observations can establish a
source gap, conformance or intended outcome, but repetition does not establish independent
recurrence,
transfer or comparative improvement. For new accepted or split observations, complete the review's
`evidence_lineage` and `evidence_lineage_note`; preparation leaves these judgments blank.

Treat owner-rejected, abandoned, over-built or disproved work as evidence for diagnosis, narrowing,
removal or bounded evaluation until independent success supports a positive lesson. Static checks,
conformance and model self-report alone do not prove behavioral benefit. Comparative improvement
requires an observed comparator. Unverified age alone neither requires deletion nor earns retention.

## Public Changes And Output

Use `$codex-skill-repo` for authoring and validation. Run the advisory drift audit before proposing
public prose; inspect skill discovery when metadata or triggers change. Payload limits require
judgment, not unrelated compression. Optional forward testing remains available for risky changes.

Preserve both ordering gates in `report-to-patch.md`: archive the review decision before source
implementation, then create commit-linked accepted metadata after the public commit exists.
A local-fix or external-owner classification grants no authority over that repository or owner.
Track an agreed action needing later work in an authorized ledger rather than silently dropping it.

Report the proposed batch with evidence, recommended action and any authority still needed. Ask
only for unresolved decisions outside existing authorization; silence grants no permission.
Finish with changes made, records left open, applicable validation and publication status. For a
read-only review, omit mutation-only reporting. Completed observation review need not create a
skill,
accepted record, verification proposal or follow-up.
