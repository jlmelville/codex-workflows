---
name: skill-retro
description: Produce and route mature skill candidates or verification proposals from completed work. Use for skill retrospectives, reusable workflow conclusions, verification evidence, external routing, or standing end-of-work evaluation. Not for low-cost papercuts.
---

# Skill Retro

Identify reusable knowledge for `codex-workflows`. Candidates propose source
decisions; verification proposals carry decisive later evidence for one
accepted outcome. Use `$papercut-capture` for low-cost friction. Operational
records never belong in a project or public skill repository.

Read [state-protocol.md](references/state-protocol.md) before writing external
state.

## Authority

Retrospective evaluation and a report in chat are read-only. Writing a
candidate or verification proposal requires one of these grants:

- the user explicitly accepts routing a proposed report;
- the user explicitly requests `auto` mode for the task or session; or
- applicable standing instructions explicitly authorize automatic routing.

Routing authority permits only sanitized new files beneath
`retrospectives/inbox` or `verifications/inbox` in the configured external
state root. It does not authorize project or source-repository edits, commits,
pushes, messages, proposal application, or changes to existing external state.
Explicit task instructions and closer repository privacy rules may narrow
standing authority.

## Routing Modes

- Default: show a compact candidate or verification summary in chat and write
  nothing.
- `route`: after the user explicitly accepts routing, write a detailed,
  sanitized candidate or verification proposal to its inbox beneath
  `CODEX_WORKFLOWS_STATE_DIR`.
- `auto`: when explicitly requested or enabled by applicable standing
  instructions, route high-confidence candidates with a concrete missing delta
  or verification proposals that exactly match a recorded opportunity.

Before writing, assemble the complete current-task candidate and verification
sets in memory or temporary scratch. Consolidate by missing delta and decision,
or by accepted identity and claim, then write one file per distinct result.

## Automatic Checkpoints

When standing instructions enable `auto`, evaluate after a substantive,
coherent work unit. Normally do this after validation and small review fixes,
before the final response or a fresh-agent handoff. Also evaluate when
substantial user redirection exposes missing guidance, or when the work reveals
reusable craft that a fresh agent would benefit from.

For the skills or destinations materially involved in the completed work, use
`verification-opportunities --destination TEXT` as a pull query. Route a
proposal only when the current task produced decisive evidence for the target's
exact recorded opportunity. A query hit alone creates no work, quota, or
record.

Err toward evaluating when the boundary is uncertain; a no-change evaluation
is cheap and should remain quiet. Fold minor follow-up fixes into the current
work unit. If evaluation already occurred, evaluate again only when continued
work materially changes the lesson or reveals a distinct one. Disclose
successfully routed candidates and verification proposals in the final
response; do not add a zero-count status line unless applicable instructions
require it.

Use the installed helper from arbitrary project repositories. Follow its
temporary-input, paste-ready fallback, and sandbox mechanics in
[state-protocol.md](references/state-protocol.md); do not depend on this source
checkout.

## Candidate Rules

- Keep the chat summary concise: observation, decisive evidence, reusable
  lesson, likely home, testability, confidence, and recommendation.
- Make a routed candidate self-contained because triage will not have the
  producing conversation.
- Prefer refinements over new skills. Before proposing a new skill, explain why
  no existing skill, reference, prompt, or script is a natural home.
- Consolidate same-task evidence for one missing delta, destination, and
  decision. Split materially distinct deltas into independently judgeable
  files.
- Preserve evidence at intake rather than forcing the producer to perform
  aggressive semantic compression. Triage and corpus review own distillation.
- When a corrected decision supersedes an earlier accepted outcome, add
  `supersedes_accepted_id` and state `now_false`. When later evidence merely
  supports or contradicts the same outcome and witness, route a verification
  proposal for that accepted identity instead of another candidate.
- Distinguish three same-topic outcomes before routing: later behavioral
  evidence updates verification without source work; implementation drift may
  require a public repair under the existing accepted identity; a changed
  decision uses supersession. For implementation drift, name the missed public
  surface and keep behavioral verification unchanged.
- For an existing destination, identify the missing delta: what current
  guidance did not cover and whether the smallest fix belongs in `SKILL.md`, a
  reference, script, prompt, or no action.
- Include a bounded exact failure signal when it is decisive. For commands,
  record whether they were exercised and whether quoting or sandbox caveats
  remain. Mark untested commands explicitly.
- Prefer a validator or bundled script for deterministic command behavior, file
  layout, metadata, generated output, or recurring fragile searches. If prose
  is better, explain why a script is not warranted.
- Harvest craft only when observed benefit justified its cost. Technically
  sound machinery inside owner-rejected, abandoned, or severely over-built
  work is not positive evidence without an independent successful use; expose
  that provenance so triage can narrow, remove, or park the lesson.
- When an existing skill materially influenced the work, check whether it made
  the task worse by misactivating, imposing unnecessary sequencing, displacing
  a simpler valid approach, relying on stale assumptions, or rewarding
  procedural compliance over the user's objective. Preserve that evidence for
  narrowing, qualification, decomposition, supersession, or removal.
- Split reusable kernels from repository-local wrappers. Route only the kernel;
  keep purely local conventions local.
- State the narrowest context directly supported by the evidence. Broaden the
  lesson only when a deterministic or otherwise credible mechanism justifies
  transfer beyond the observed context.
- Identify ownership when known: source-owned in `codex-workflows`, repo-local,
  external/plugin-owned, or unknown.
- For no-change recommendations, cite the existing section, numbered item,
  script, prompt, or local convention that already covers the lesson.

## Privacy Boundary

Treat third-party or synchronized state as potentially exposed. Exclude raw
transcripts, session logs, tool dumps, credentials, private source, raw runtime
history paths, unredacted user-home paths, and unnecessary private repository
names. Use generalized source scopes and bounded error fragments. Complete the
redaction-review field deliberately; the helper's pattern checks are guardrails,
not a secret scanner.

## Verification Discipline

For prose or trigger changes, do not claim behavioral verification from the
implementation itself. A later session can support or contradict a rule only
when it records the observed task, decisive behavior or failure, affected
guidance, and why the observation matters. Model self-report alone is
insufficient.

State exactly what the evidence establishes. A deterministic test normally
supports executable correctness; later-session evidence may support that the
guidance was followed or that the intended outcome occurred. Neither
establishes comparative improvement without an observed comparator.

A proposal must follow the typed fields and claim vocabulary in the state
protocol, match one eligible `SCR-*` opportunity, and include `what_is_false`
only for contradiction. `$skill-retro-triage` alone applies or rejects it.

Do not recommend maintained prompt corpora, synthetic model fixtures, repeated
model runs, `codex exec` benchmarks, raw trace archives, paid model-backed CI,
or public evidence records merely to validate a skill edit.

## Triage Rules

- Add a skill when the pattern is reusable, non-obvious, likely to recur, and
  lacks a natural existing home.
- Update an existing skill when the pattern is a small refinement.
- Add a script when deterministic command behavior matters.
- Add a prompt when the reusable asset is an instruction to ask another agent.
- Add nothing when it is ordinary engineering judgment, one project's local
  convention, or already covered.

When a candidate is ready for judgment or implementation, run the repository-
local `$skill-retro-triage` from the `codex-workflows` source checkout.
External deferrals, drafts, ledgers, accepted records, and audit history follow
the state protocol and must not be added to Git.

## Compact Chat Shape

For a candidate, report name, observation, decisive evidence, reusable lesson,
home, testability, confidence, and recommendation. For verification, report
target, exact opportunity match, proposed state and basis, claim, evidence, and
confidence.

If no change is warranted, say so directly and cite the specific existing
coverage instead of stretching ordinary project details into a candidate.
