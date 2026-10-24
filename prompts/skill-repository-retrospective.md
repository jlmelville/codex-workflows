# Skill Repository Retrospective Prompt

Audit this `codex-workflows` repository as a public skill system. Produce a report in chat;
source edits, commits, installation and PRs require authority from the invoking request.

Use this full-corpus route when requested or when cross-cutting findings justify it within the
current scope. A cadence reminder alone does not expand a review. For a focused question, use
[the public-review route](../skills/learning-process-review/SKILL.md#public-artifact-audit-route).

## Scope

Inspect skill triggers and core guidance, display metadata and default prompts, routed references,
bundled scripts, repository instructions, root validation and installer ownership, CI and dependency
updates, prompts and relevant source history. Check managed runtime parity when available. State
coverage limits rather than implying an unavailable surface was inspected.

Keep `CODEX_WORKFLOWS_STATE_DIR` out of this audit. Personal reports, verdicts, accepted evidence,
drafts, ledgers and audits belong to the separate learning-state review. Public structure and
validation do not establish downstream behavioral effectiveness.

## Judgment

Look for changes that would improve a real agent decision or remove avoidable work:

- duplicated or conflicting guidance, unclear triggers and inconsistent authority;
- default-path sequences or incident-specific rules without a distinct decision or failure boundary;
- local conventions presented as general guidance;
- stale, redundant or under-validated helpers, and CI or installer drift;
- missing routes to useful guidance, and cases where existing coverage already suffices.

Use [semantic authoring](../skills/codex-skill-repo/references/semantic-authoring.md) for admission,
placement and payload judgment. When duplication is suspected, compare the affected clauses by the
action, authority, required observation and success claim they produce. Inventory or group clauses
only as needed to judge the proposed consolidation; do not add a separate corpus-wide pass.
Preserve distinct conditions and constraints. Moving prose to a reference alone is not compression.

A grounded incident need not earn a new rule. Another occurrence of the same decision and witness
may add verification evidence instead. Optional cases should preserve a distinct plausible mistake
or observation boundary, not accumulate report narratives. Line counts and checked payload budgets
are review signals; neither proves bloat or justifies advancing a baseline to clear a finding.

Distinguish a decision that lacks evidence from a justified change whose later benefit is unknown.
The former may warrant deferral; the latter can be implemented and remain behaviorally unverified.
Do not require a new matcher, experiment or record merely to retain an uncertain recommendation.

## Report

Lead with the findings most likely to change a worthwhile decision. For each recommended edit,
give file and line evidence, the affected behavior, the smallest useful change, its payoff and
risk, and any authority or evidence still needed. Include justified retention or no-action findings
where they answer the review question. Choose a compact structure suited to the findings; empty
categories and a fixed report template are unnecessary.

Separate observations from inferred consequences and structural health from behavioral claims.
With public evidence alone, report behavioral effectiveness as unassessed rather than inferring it
from corpus organization, validation or commit history.

End with a prioritized proposed batch and distinguish agreed follow-ups needing tracking from
optional ideas and open questions. An agreed future action needs an owner, a concrete review
condition and check, a next action and a close condition. Reuse an existing record when suitable.
Leave unaccepted recommendations and inconclusive questions in the report.

Do not write external state from this report-only audit. `$learning-process-review` owns authorized
follow-up and completed-audit recording after a full audit actually finishes. A focused review
does not reset the full-audit reminder.
