---
name: skill-retro
description: Produce and route mature skill candidates or verification proposals from completed work. Use for skill retrospectives, reusable workflow conclusions, verification evidence, external routing, or standing end-of-work evaluation. Not for low-cost papercuts.
---

# Skill Retro

Identify reusable knowledge for `codex-workflows`. Candidates propose source
decisions; verification proposals carry decisive later evidence for one
accepted outcome. Use `$papercut-capture` for low-cost friction. Operational
records never belong in a project or public skill repository.

Run the checkpoint in this file first. Load record-construction and state
mechanics only when a possible record survives, as routed under Construct Or
Report.

## Authority

Retrospective evaluation and a report in chat are read-only. Writing a
candidate or verification proposal requires one of these grants:

- the user explicitly accepts routing a proposed report;
- the user explicitly requests `auto` mode for the task or session; or
- applicable standing instructions explicitly authorize automatic routing.

Routing authority permits only sanitized new inbox files beneath the configured
state root. It does not authorize project or source edits, commits, pushes,
messages, proposal application, or existing-state changes; closer instructions
may narrow it.

## Routing Modes

- Default: show a compact candidate or verification summary in chat and write
  nothing.
- `route`: after the user explicitly accepts routing, write a detailed,
  sanitized candidate or verification proposal to its inbox beneath
  `CODEX_WORKFLOWS_STATE_DIR`.
- `auto`: when explicitly requested or enabled by applicable standing
  instructions, route only high-confidence candidates with a concrete missing
  delta or verification proposals that exactly match a recorded opportunity.

## Automatic Checkpoints

When standing instructions enable `auto`, evaluate once after a substantive coherent work unit,
normally after validation and small fixes. Also evaluate when material user correction or a
distinct lesson appears. Fold minor follow-ups into that evaluation and reuse current context.

Start with the work's concrete observations: a reusable missing decision, a material failure, or
evidence that might establish something new about existing guidance. If none is plausible, stop
quietly. Using a skill alone does not require querying its verification opportunities.

For a possible verification observation, use the installed helper for bounded discovery:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" verification-context --destination TEXT --compact
```

Query the guidance involved in the observation;
include `skills/skill-retro/assets/global-agents-learning.md` for learning-state authority evidence.
Use optional text filters and pagination only as needed; literal filters limit coverage.
Expand selected accepted or proposal IDs with `verification-context --id ID` before judging the
exact opportunity, supported claims, remaining uncertainty and applied or pending evidence.

For observed failure or harm, first use `accepted-records --destination TEXT` or `--text TEXT`
to find the applicable identity across all dispositions, then expand it with `verification-context`.
Route contradiction only for evidence matching that record's claim and opportunity; use a candidate
when the decision itself changes. A query hit creates no task or quota.

Reuse still-current discovery and selected evidence within a continuous task. Refresh only when
the relevant guidance, state, observation or scope changes. Further support must materially add
to existing evidence for the same identity and opportunity, with a concrete `supplemental_reason`;
another conforming task or a different claim label alone is insufficient.

For an agreed future action, identify its owner and how it will be encountered. Route only admitted
records within authority; an inconclusive thought needs no record. Keep no-change evaluations quiet
and disclose routed records, blocked writes or paste-ready fallbacks.

## Detect And Admit A Result

Examine the method as well as the result. Use
[value-stream judgment](references/value-stream.md) when a concrete concern needs deeper inquiry;
reuse guidance already available. A successful deliverable does not establish that the method was
useful, and noticing a concern does not itself establish a missing rule.

Distinguish these outcomes before loading record-construction mechanics:

- A candidate captures a reusable, non-obvious decision or craft lesson that
  active guidance materially lacks and that is likely to recur. For an otherwise
  admissible owner-directed or upstream change already landed during the work,
  judge the missing delta against pre-change guidance; landing alone does not
  end admission.
- A verification proposal carries decisive later evidence for the exact claim
  and witness named by one recorded `SCR-*` opportunity.
- No change is the correct result for ordinary engineering judgment, a local
  convention, already-covered guidance, or inconclusive evidence.

Before admitting a candidate:

- Check the affected skill, reference, prompt, script, or local instruction.
  Name the concrete missing delta and prefer refining its natural home over
  creating a skill. If pre-existing coverage makes the decision clear, cite it
  and end candidate admission; for an observed failure or material correction,
  evaluate the accepted-record verification route above before concluding no
  change.
- Treat material human correction as a checkpoint, but separate the observed
  judgment from producer inference and do not infer success or comparative
  improvement from the selected alternative.
- When active guidance materially influenced the work, check whether it made
  the task worse through misactivation, unnecessary sequencing, stale
  assumptions, displacement of a simpler valid path, or procedural compliance
  that displaced the user's objective.
- Harvest craft only when observed benefit justified its cost. Owner-rejected,
  abandoned, or severely over-built work is not positive evidence without an
  independent successful use.
- Route only the reusable kernel, not a repository-local wrapper, and keep the
  claimed scope no broader than the evidence supports.

Before admitting verification evidence:

- Do not infer behavioral effectiveness from implementation, structure,
  validation, rule conformance, or model self-report alone.
- State only what the observation establishes. Deterministic tests normally
  support executable correctness; later-session evidence may support guidance
  conformance or an intended outcome. Comparative improvement requires an
  observed comparator.
- Use a candidate, not verification, for a changed decision. Use the existing
  accepted identity for implementation drift or further evidence about the same
  decision and witness.

## Privacy Boundary

Treat third-party or synchronized state as potentially exposed. Exclude raw
transcripts, session logs, tool dumps, credentials, private source, raw runtime
history paths, unredacted user-home paths, and unnecessary private repository
names. Use generalized source scopes and bounded error fragments. Complete the
redaction-review field deliberately; helper checks are guardrails, not a secret
scanner.

## Construct Or Report

If a possible record survives admission, read
[record-construction.md](references/record-construction.md) for evidence fields,
identity and supersession rules, destination choice, helper routing, fallbacks,
and the compact chat shape. Before a candidate write, read the state protocol's
[Installed Helper](references/state-protocol.md#installed-helper) and
[Candidate Intake](references/state-protocol.md#candidate-intake) sections.
Before a verification write, read
[Installed Helper](references/state-protocol.md#installed-helper) and
[Accepted Records And Verification](references/state-protocol.md#accepted-records-and-verification).
In default mode, use the chat shape without writing.

For an explicitly requested retrospective report, state a no-change conclusion
concisely and cite the relevant existing coverage. During standing automatic
evaluation, omit retrospective-specific output when nothing is routed unless
the user requests it. Always disclose routed records, blocked writes, and
paste-ready fallbacks.
