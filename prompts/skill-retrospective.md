# Skill Retrospective Prompt

Use this at the end of a coding session when the work surfaced reusable
workflow knowledge that might belong in `codex-workflows`.

```text
Before we finish, do a skill retrospective. Identify any repeated workflow,
tool failure, repo convention, validation pattern, or decision process that
might deserve reusable Codex guidance.

Prefer refinements over new skills. Before proposing a new skill, explain why
no existing skill, reference, prompt, or script is a natural home.

Deduplicate related observations. If several events point to the same workflow,
merge them into one candidate with multiple evidence bullets.

For existing-skill updates, identify the missing delta: what current guidance
did not already cover, and whether the fix belongs in `SKILL.md`, a reference,
or a script.

Do not create files. Output a concise Skill Candidate Report with:
- Candidate name
- Trigger: when this would have helped
- Evidence from this session
- Exact failure signal: command, error text, or behavior, when applicable
- Proposed behavior
- Scope: generic, language-specific, or repo-specific
- Suggested home: new skill, existing skill update, script, reference, prompt,
  or no action
- Missing delta: what existing guidance did not already cover
- Why it is not just ordinary coding knowledge
```

Ask for this report in the project chat, then paste the useful candidates into a
`codex-workflows` chat for triage.

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
Trigger:
Evidence:
Exact failure signal:
Proposed behavior:
Scope:
Suggested home:
Missing delta:
Validation or script opportunity:
Risk if omitted:
Preliminary recommendation:
```
