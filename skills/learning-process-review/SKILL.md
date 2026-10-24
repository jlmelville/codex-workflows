---
name: learning-process-review
description: Review codex-workflows learning state and public skill-repository artifact audits. Use for papercut closure, retrospectives, candidate or verification health, drain decisions, and cleanup.
---

# Learning Process Review

Review disposable learning state without turning the public skill repository
into an operational archive. Treat observations as evidence to judge, not work
instructions to execute mechanically.

## Authority

- Default to a read-only review. Report findings and the complete proposed
  drain batch before changing public source or external state.
- When the user has authorized a batch or review with drainage, report the
  concrete actions as an intermediate update and complete them within that
  scope. Prior acceptance needs no renewed approval; ask for decisions outside
  the existing authorization.
- Treat source edits, installs, commits, pushes, messages, and external-owner
  actions as separate mutations requiring applicable authority.
- Apply `$papercut-capture` only to new friction encountered during the review;
  do not use capture authority to close or promote existing records.

## Public Artifact Audit Route

For a focused public-skill question, inspect the relevant guidance and connected
surfaces. Report the scope, evidence, recommendations, and limits in a form that
fits the question. Do not require the full audit checklist or report template;
a focused review does not complete or reset the artifact-audit cadence.

Use [the repository-root artifact-audit prompt](../../prompts/skill-repository-retrospective.md)
for a full audit when requested or when cross-cutting findings justify it within the current scope.
A due cadence is a reminder to judge whether that audit is useful, not a requirement to start it.
Keep private learning state out of both public review routes. Access completed-audit state only
after the full report and applicable mutation gate.

## Private Learning-State Review

For effects on ordinary work or exploratory downstream evidence, follow
[`prompts/learning-process-investigation.md`](../../prompts/learning-process-investigation.md).
For papercut closure, candidate or verification health, drain decisions, or a broader retrospective,
use [private-learning-state-review.md](references/private-learning-state-review.md).
It owns state context and follow-up, with downstream investigation only where useful to the review.
Keep focused inquiries within scope; they do not complete a full review or reset cadence.

When proposing or reviewing a material learning-loop change with uncertain
benefit, use [loop experiments](references/loop-experiments.md) for a bounded
observation using existing ledgers and review routes.

## Completed Artifact Audit

Record a completed audit with `audit_kind: skill-repository` only after the full report finishes
and state recording is authorized. Link existing open follow-ups or create a deferral or ledger
only for an agreed executable action needing tracking; optional ideas stay in the report.
Keep unresolved contradictions in the queue until resolved or assigned to an open residual ledger.
The completion time supplies the approximate reminder cutoff. After a lost write response,
inspect existing audits before recording another.

Read `${HOME}/.agents/skills/skill-retro/references/state-protocol.md` before
mutating state, finish with:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" validate
```

Report state changes, records left open, validation status, public publication
status, and the next event-based review trigger.
