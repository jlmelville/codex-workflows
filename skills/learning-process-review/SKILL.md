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
- Mutate state only after the user explicitly accepts the reported batch. When
  autonomous review and drainage were explicitly requested in advance, report
  the batch as an intermediate update before continuing in the same turn.
- Treat source edits, installs, commits, pushes, messages, and external-owner
  actions as separate mutations requiring applicable authority.
- Apply `$papercut-capture` only to new friction encountered during the review;
  do not use capture authority to close or promote existing records.

## Public Artifact Audit Route

For a direct public-only audit, follow
[the repository-root artifact-audit prompt](../../prompts/skill-repository-retrospective.md).
Do not require or inspect private learning state as audit evidence. Defer cadence
or completed-audit state access until after the report and applicable mutation
gate. In a broader process review, run the same prompt as a separate due-cadence
report and keep private state out of its findings.

## Private Learning-State Review

For papercut closure, candidate or verification health, drain decisions, or a
broader process retrospective, read
[private-learning-state-review.md](references/private-learning-state-review.md).
It owns the state context, judgment, report, drain, and next-review mechanics
that are not needed for a direct public artifact audit.

## Completed Artifact Audit

After the applicable mutation gate, handle every unresolved executable
consequence through the typed state protocol. Record the completed audit with
`audit_kind: skill-repository` only after the full report-only audit finishes.
That successful record resets machine-owned cadence. If the audit fails or is
interrupted, record nothing so it remains due.

Read `${HOME}/.agents/skills/skill-retro/references/state-protocol.md` before
mutating state, finish with:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" validate
```

Report state changes, records left open, validation status, public publication
status, and the next event-based review trigger.
