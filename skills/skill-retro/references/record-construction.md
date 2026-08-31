# Retrospective Record Construction

Read this only after `SKILL.md` identifies a possible candidate or verification proposal. Admission, authority, privacy, and quiet no-change remain there.

## Shared Construction

- Keep chat concise and a routed record self-contained; triage lacks the producing conversation.
- Consolidate by missing delta and decision, or by accepted identity and claim. Write one file per
  distinct result and split materially different deltas into independently judgeable records.
- Recheck privacy and preserve only evidence needed to judge the decision or claim.

## Candidate Evidence

- Classify `evidence_lineage` against affected guidance and explain how it may have shaped what was
  attempted, noticed, or reported. Use `unknown`; descendant reports do not prove recurrence or transfer.
- For material human feedback, preserve a bounded sanitized pairing of judged behavior, the judgment and
  stated rationale or constraints, and any alternative or outcome. Leave unstated rationale absent and separate producer inference from evidence.
- Name the missing delta and its smallest natural home: `SKILL.md`, reference, script, prompt, local
  instruction, external/plugin-owned surface, or no action. Mark ownership unknown if necessary.
- Include a bounded exact failure signal when decisive. For commands, record whether they were exercised,
  whether quoting or sandbox caveats remain, and which commands are untested.
- Prefer a validator or bundled script for deterministic command behavior, layout, metadata, generated
  output, or fragile recurring searches. If prose is the right control, explain why a script is unwarranted.
- State the narrowest supported context; broaden only with a credible transfer mechanism.

When a corrected decision makes an accepted outcome false, name `supersedes_accepted_id` and state
`now_false`. For the same outcome and witness, use verification. For implementation drift, name the missed
public surface under the existing accepted identity and leave behavioral verification unchanged.

## Destination Choice

- Add a skill only for a reusable, non-obvious, recurring pattern with no natural existing home.
- Update an existing skill for a focused refinement; add a script when deterministic behavior matters;
  add a prompt when the asset is an instruction to ask another agent.
- Add nothing for ordinary judgment, a local convention, or an already-covered decision. Cite the
  section, item, script, prompt, or convention that covers it.

## Verification Evidence

Use the typed fields and claim vocabulary in the [state protocol](state-protocol.md), match one eligible
`SCR-*` opportunity, and use `what_is_false` only for contradiction. Record the task, decisive behavior or
failure, affected guidance, and why it matters. `$skill-retro-triage` alone applies or rejects a proposal.

Do not recommend maintained prompt corpora, synthetic model fixtures, repeated model runs, `codex exec`
benchmarks, raw trace archives, paid model-backed CI, or public evidence records merely to validate prose.

## Helper, Routing, And Chat

Before writing, follow the [state protocol](state-protocol.md) for templates, identity, temporary input,
fallback, and sandbox recovery. Use the installed helper from project repositories; do not depend on this
source checkout. Triage ready records with repository-local `$skill-retro-triage`; external state never
belongs in Git.

For a candidate, report name, observation, decisive evidence, lesson, home, testability, confidence, and
recommendation. For verification, report target, exact opportunity match, proposed state and basis, claim,
evidence, and confidence.
