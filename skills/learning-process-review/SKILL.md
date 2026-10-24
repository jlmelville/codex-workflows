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

For a full public artifact audit, follow
[the repository-root artifact-audit prompt](../../prompts/skill-repository-retrospective.md).
Keep private learning state out of both review routes. For full audits, defer
cadence or completed-audit state access until after the report and applicable
mutation gate. In a broader process review, run the same prompt as a separate
due-cadence report and keep private state out of its findings.

## Private Learning-State Review

For a focused question about process effects on ordinary work, or an exploratory
investigation of a machine's downstream evidence, follow
[`prompts/learning-process-investigation.md`](../../prompts/learning-process-investigation.md).
This is a report-only route unless the invoking request authorizes follow-up;
it does not complete a full review or reset cadence. Broader reviews use the
same investigation guidance for their existing downstream coverage, as scoped
by the private-review reference below, and fold findings into their existing
report without adding another pass.

For papercut closure, candidate or verification health, drain decisions, or a
broader process retrospective, read
[private-learning-state-review.md](references/private-learning-state-review.md).
It owns the state context, judgment, report, drain, and next-review mechanics
that are not needed for a direct public artifact audit.

When proposing or reviewing a material learning-loop change with uncertain
benefit, use [loop experiments](references/loop-experiments.md) for a bounded
observation using existing ledgers and review routes.

## Completed Artifact Audit

After the applicable mutation gate, handle every unresolved executable
consequence through the typed state protocol. Record the completed audit with
`audit_kind: skill-repository` only after the full report-only audit finishes.
Its completion time becomes the cutoff for the approximate candidate-count reminder. Record only
completed audits; after a lost write response, inspect existing audits before recording another.

Read `${HOME}/.agents/skills/skill-retro/references/state-protocol.md` before
mutating state, finish with:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" validate
```

Report state changes, records left open, validation status, public publication
status, and the next event-based review trigger.
