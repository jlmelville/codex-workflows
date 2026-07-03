# Skill Retrospective Prompt

Use this at the end of a coding session when the work surfaced reusable
workflow knowledge that might belong in `codex-workflows`.

```text
Before we finish, do a skill retrospective. Identify any repeated workflow,
tool failure, repo convention, validation pattern, or decision process that
might deserve a reusable Codex skill.

Do not create files. Output a concise Skill Candidate Report with:
- Candidate name
- Trigger: when this would have helped
- Evidence from this session
- Proposed behavior
- Scope: generic, language-specific, or repo-specific
- Suggested home: new skill, existing skill update, script, reference, prompt,
  or no action
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
Proposed behavior:
Scope:
Suggested home:
Validation or script opportunity:
Risk if omitted:
Decision:
```
