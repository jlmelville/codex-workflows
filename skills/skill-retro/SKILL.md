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
- When the lesson is about deterministic command behavior, file layout,
  metadata, generated output, or a recurring fragile search, prefer a validator
  or bundled script over prose-only guidance. If no script is warranted, explain
  why the rule should remain prose.
- Distinguish local files from remote service state when that changed the
  investigation.
- Identify ownership when known: source-owned in `codex-workflows`, repo-local,
  external/plugin-owned, or unknown.
- For no-change recommendations, cite the specific existing skill, reference,
  script, prompt, or local convention that already covers the lesson. Prefer a
  section name, heading, or numbered item such as
  `dependabot-pr-maintenance > Batch Merge item 2` over a broad skill name.

## Triage Rules

- Add a skill when the pattern is reusable, non-obvious, and likely to recur.
- Update an existing skill when the pattern is a small refinement.
- Add a script when deterministic command behavior matters.
- Add a prompt when the reusable asset is an instruction to ask another agent.
- Add nothing when it is ordinary engineering judgment or one project's local
  convention.

## Maintenance Ledger

For ordinary project retrospectives, output the report in chat and do not edit
files. When explicitly maintaining `codex-workflows` or triaging multiple
candidate reports for this repo, use
[maintenance-ledger.md](references/maintenance-ledger.md) for deferred,
threshold-based observations that are not ready to become skill text, scripts,
or prompts.

When a Skill Candidate Report has been accepted for `codex-workflows`, follow
[report-to-patch.md](references/report-to-patch.md) to convert it into scoped
repo edits, validation, and install/commit decisions.

Review the ledger after several accepted skill-retro updates, during a skill
repository retrospective, or when a user asks how the triage workflow is
shaping up. Close, promote, or refresh entries rather than letting them become
stale repo folklore.

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
Existing coverage:
Validation or script opportunity:
Executable check:
Prose-only rationale:
Risk if omitted:
Preliminary recommendation:
```

If no change is warranted, say that directly and explain which existing skill,
reference, script, prompt, or local convention already covers the lesson, with a
section or item citation when available.
