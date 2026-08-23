---
name: papercut-capture
description: Capture sanitized observations of unexpected, avoidable workflow friction during substantive repository work. Use when standing instructions enable capture or the user asks to record a papercut. Exclude ordinary debugging and expected failures; do not review or promote papercuts.
---

# Papercut Capture

Preserve workflow friction while its evidence is fresh, before deciding whether
it warrants a local fix, an external-owner action, or a reusable skill change.
Read the shared [state protocol](../skill-retro/references/state-protocol.md)
before writing external state.

## Authority

Write a papercut only when one of these grants capture authority:

- applicable standing instructions explicitly enable `$papercut-capture`;
- the user enables capture for the current task or session;
- the user asks to record one specific event.

Implicit skill activation alone does not authorize a write. Capture authority
permits only new files beneath `papercuts/inbox` in the configured external
state root. It does not authorize closing or editing observations, creating or
promoting candidates, changing repositories, committing, pushing, or sending
messages. Explicit task instructions and closer repository instructions may
narrow or disable standing authority.

## Qualification

Record an observation when most of these are true:

- available instructions and repository context did not make the behavior
  reasonably predictable;
- tooling, documentation, environment, or repository behavior caused an
  avoidable retry, dead end, block, ambiguity, or substantial noise;
- clearer guidance, commands, links, validation order, version policy, or a
  deterministic mechanism could plausibly prevent it;
- the observation and any workaround can be stated briefly and safely.

Do not record:

- the test or ordinary code defect being repaired by the current task;
- expected compiler, linter, or test failures during normal iteration;
- deliberate exploratory hypotheses that simply proved false;
- syntax mistakes or typos caught normally by tooling;
- ordinary uncertainty while learning unfamiliar code.

A documented focused-test command that fails unexpectedly from a clean session
may qualify. The new regression test for the feature currently being built does
not.

## Capture

Record a qualifying observation near the event, then continue the task without
asking the user to classify, close, or promote it. Generate the current schema
and submit the completed document with the installed helper:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" template papercut
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" record-papercut --file PAPERCUT_FILE
```

Create input in a temporary file and remove it when practical.
`record-papercut --file -` also accepts a complete papercut document on
standard input. Do not discover or depend on the location of the
`codex-workflows` source checkout.

If `CODEX_WORKFLOWS_STATE_DIR` is unset or invalid, the helper prints a
validated paste-ready record and writes no state. Preserve that record for the
final response. If the configured root is blocked only by the sandbox, retry
through the platform's narrowly scoped approval path when available; otherwise
return the paste-ready record. Neither fallback broadens capture authority.

## Privacy

Treat external or synchronized state as potentially exposed. Exclude raw
transcripts, session logs, tool dumps, credentials, private source, raw runtime
history paths, unredacted user-home paths, and unnecessary private repository
names. Use generalized source scopes and bounded error fragments. Complete the
redaction-review field deliberately; helper checks are guardrails, not a secret
scanner.

## Disclosure And Pilot

Track the number of papercuts successfully recorded during the task. When
standing instructions mark the initial pilot active, end with
`Papercuts recorded: N`, including when `N` is zero. Treat that line as a
compliance signal, not proof that no event was missed. Outside the pilot,
disclose nonzero records and any paste-ready fallback; follow stricter
applicable instructions when present.

Do not turn a papercut into a mature conclusion during project work. Review
open observations later from the `codex-workflows` source checkout with its
repository-local `$learning-process-review`. Use `$skill-retro` during work;
the review routes mature reusable candidates to the repository-local
`$skill-retro-triage` consumer.
