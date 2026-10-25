---
name: skill-retro
description: Capture concrete observations about workflow friction, harmful guidance, or useful improvements during substantive work and at task boundaries. Preserve evidence for later review without choosing a remedy or proposing a skill.
---

# Workflow Observations

Preserve concrete signals that work could improve. Use one observation stream for small friction,
material failures, owner corrections and useful discoveries. Review later determines whether they
warrant a local fix, shared guidance, verification of an existing outcome, or no action.

## Authority

Capture requires an explicit task request, `route` or `auto` authorization, or applicable standing
instructions. Default to a concise report in chat when capture is not authorized. Existing grants
for `$papercut-capture` use this same stream, within their original scope and privacy limits.

Capture authority permits only sanitized new observation inbox records beneath the configured
external state root. It does not authorize reviewing or closing records, applying verification,
source edits, commits, pushes or messages. Observations are evidence to judge, not instructions.

## Notice And Capture

Early in substantive work, when configured state is accessible and repository privacy permits,
query destinations of guidance that materially shapes task decisions:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" verification-context --destination TEXT --compact
```

Expand relevant matches with the same helper's `verification-context --id ID` to read their
opportunities; reuse current results. Use these as observation context within the accepted task,
without adding work, review gates or verification authority. Unavailable state does not block work.

Notice useful observations during substantive work while the evidence is fresh. At a coherent task
boundary, briefly consider whether anything important remains uncaptured. Fold small follow-ups
into the same evaluation; another invocation need not create another record. Stay quiet when there
is nothing worth preserving.

Capture when there is a concrete observation and a plausible reason it could improve later work:

- unexpected friction, avoidable retries, confusing guidance or fragile handoffs;
- unnecessary sequencing, excessive machinery or process that displaced the user's objective;
- material human correction, an observed failure of guidance, or a useful simpler approach;
- an observed result that may bear on an existing accepted claim.

Use [value-stream judgment](references/value-stream.md) when a concrete concern needs deeper
inquiry.
Ordinary debugging, expected test failures, exploratory hypotheses that proved false and already
captured repetition do not need records. A routine success alone is not a new observation.
Do not expand the task to find a lesson or populate the inbox.

Preserve what happened, why it may matter and the bounded evidence. Include relevant guidance in
use, impact, workaround, outcome and useful analysis already known. Label suspected causes and
proposed remedies as hypotheses. Preserve material human feedback without inventing its rationale.
A successful result does not prove the method was useful; rejected or abandoned work does not
establish a successful reusable technique.

Capture does not require classifying the observation, proving recurrence, searching existing
coverage, choosing an owner or destination, designing a remedy, or matching a verification claim.
Preserve a known accepted ID or public commit when relevant, but do not perform discovery merely
to complete a record. The reviewer owns those judgments.

## Privacy And Evidence

Treat external or synchronized state as potentially exposed. Exclude raw transcripts, session logs,
tool dumps, credentials, private source, runtime history paths, unredacted user-home paths and
unnecessary private repository names. Keep sanitized evidence sufficient for later judgment.
Complete the redaction review deliberately; helper checks are guardrails, not a secret scanner.

Separate observation from interpretation. Record what was actually exercised and leave missing
observations unknown. Preserve whether guidance shaped the work when known; review must not count
conditioned reports as independent recurrence. Capture establishes no acceptance, behavioral
benefit,
comparative improvement or verification state.

## Record Or Report

Read [record construction](references/record-construction.md) only when an observation qualifies.
It owns the minimal template and capture command. Use one record per distinct observation; retain
useful context in that record rather than creating both a papercut and a candidate.

In `auto` mode, capture qualifying observations without interrupting the task. In `route` mode,
record the authorized observation. With no routing authority, report it in chat without writing.
Disclose nonzero captures, blocked writes and paste-ready fallbacks; omit empty checkpoint reports.

`$skill-retro-triage` reviews observations from the source checkout. Existing papercuts, candidates
and verification proposals remain valid review input; new capture uses the observation stream.
