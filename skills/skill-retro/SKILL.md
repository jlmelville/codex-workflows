---
name: skill-retro
description: Produce and optionally route sanitized Skill Candidate Reports for reusable Codex workflow knowledge. Use at the end of coding sessions, investigations, cleanups, CI debugging, or multi-agent work when the user asks for a skill retrospective, candidate report, or external retro inbox routing.
---

# Skill Retro

Use this to identify reusable workflow knowledge that might belong in
`codex-workflows`. The default retrospective is chat-only. Operational reports
and housekeeping state never belong in a project repository or the public skill
source repository.

Read [state-protocol.md](references/state-protocol.md) before routing a report.

## Output Modes

- Default: show a compact candidate summary in chat and write nothing.
- `route`: after the user explicitly accepts routing, write a detailed,
  sanitized candidate to the inbox beneath `CODEX_WORKFLOWS_STATE_DIR`.
- `auto`: only when the user explicitly requests this mode, route candidates
  with high confidence, concrete evidence, a clear missing delta, and a named
  destination or well-justified new home. Its only authorized mutation is an
  external inbox record.

Neither routing mode authorizes project edits, source-repository edits,
commits, pushes, messages, or changes to other external state.

Use the installed helper from an arbitrary project repository:

```sh
"${CODEX_HOME:-$HOME/.codex}/skills/skill-retro/scripts/retro-state.rb" template candidate
"${CODEX_HOME:-$HOME/.codex}/skills/skill-retro/scripts/retro-state.rb" route --file CANDIDATE_FILE
```

Create the candidate in a temporary file, route it, and remove the temporary
file when practical. Do not discover or depend on the location of the
`codex-workflows` source checkout. If `CODEX_WORKFLOWS_STATE_DIR` is unset or
unwritable, the helper prints a validated paste-ready report and writes no
state.

## Candidate Rules

- Keep the chat summary concise: observation, decisive evidence, reusable
  lesson, likely home, testability, confidence, and recommendation.
- Make a routed candidate self-contained because triage will not have the
  producing conversation.
- Prefer refinements over new skills. Before proposing a new skill, explain why
  no existing skill, reference, prompt, or script is a natural home.
- Deduplicate related observations. Route one candidate per external Markdown
  file so each can be judged independently.
- For an existing destination, identify the missing delta: what current
  guidance did not cover and whether the smallest fix belongs in `SKILL.md`, a
  reference, script, prompt, or no action.
- Include a bounded exact failure signal when it is decisive. For commands,
  record whether they were exercised and whether quoting or sandbox caveats
  remain. Mark untested commands explicitly.
- Prefer a validator or bundled script for deterministic command behavior, file
  layout, metadata, generated output, or recurring fragile searches. If prose
  is better, explain why a script is not warranted.
- Harvest reusable craft that worked well, not only failures. The test is
  whether a fresh agent doing similar work would reuse the convention.
- Split reusable kernels from repository-local wrappers. Route only the kernel;
  keep purely local conventions local.
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

When a candidate is ready for judgment or implementation, use
`$skill-retro-triage`. External deferrals, drafts, ledgers, accepted records,
and audit history follow the state protocol and must not be added to Git.

## Compact Chat Shape

```md
## Skill Candidate Report

### candidate-name
Observation or surprise:
Decisive evidence:
Reusable lesson:
Suggested home:
Testability:
Confidence:
Preliminary recommendation:
```

If no change is warranted, say so directly and cite the specific existing
coverage instead of stretching ordinary project details into a candidate.
