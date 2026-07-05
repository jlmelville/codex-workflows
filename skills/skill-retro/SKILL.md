---
name: skill-retro
description: Produce concise skill retrospective reports for reusable Codex workflow knowledge. Use at the end of coding sessions, investigations, cleanups, CI debugging, or multi-agent work when the user asks for a skill retrospective, Skill Candidate Report, or guidance that might belong in codex-workflows.
---

# Skill Retro

Use this to identify reusable workflow knowledge that might belong in
`codex-workflows`. Do not create files or make repo changes for the
retrospective itself; output the report in chat.

## Report Rules

- Start each candidate with a `Triage intent` line: `update existing skill`,
  `no change`, `new skill`, `new script`, `new prompt`, or `uncertain`.
- Prefer refinements over new skills. Before proposing a new skill, explain why
  no existing skill, reference, prompt, or script is a natural home.
- Deduplicate related observations. If several events point to the same
  workflow, merge them into one candidate with multiple evidence bullets.
- For existing-skill updates, identify the missing delta: what current guidance
  did not already cover, and whether the fix belongs in `SKILL.md`, a
  reference, script, prompt, or no action.
- Include exact failure signals when available: command, error text, annotation,
  API response, warning, or behavior.
- For command or shell-pattern suggestions, say whether the command was
  smoke-tested and whether any quoting or sandbox caveat remains. Mark untested
  commands explicitly.
- Distinguish local files from remote service state when that changed the
  investigation.
- Identify ownership when known: source-owned in `codex-workflows`, repo-local,
  external/plugin-owned, or unknown.
- For no-change recommendations, cite the existing skill, reference, script,
  prompt, or local convention that already covers the lesson.

## Triage Rules

- Add a skill when the pattern is reusable, non-obvious, and likely to recur.
- Update an existing skill when the pattern is a small refinement.
- Add a script when deterministic command behavior matters.
- Add a prompt when the reusable asset is an instruction to ask another agent.
- Add nothing when it is ordinary engineering judgment or one project's local
  convention.

## Report Shape

```md
## Skill Candidate Report

### candidate-name
Triage intent:
Trigger:
Evidence:
Exact failure signal:
Proposed behavior:
Scope:
Suggested home:
Suggested destination path:
Ownership:
State surface:
Missing delta:
Validation or script opportunity:
Risk if omitted:
Preliminary recommendation:
```

If no change is warranted, say that directly and explain which existing skill,
reference, script, prompt, or local convention already covers the lesson.
