# Skill Repository Retrospective Prompt

Audit this `codex-workflows` repository as a skill system, not as an ordinary
codebase.

Use this periodically after several skill-retro-driven updates. Do not edit
files, create commits, sync installed skills, or open PRs unless explicitly
asked. Produce a report in chat.

Inspect:

- `skills/*/SKILL.md` trigger descriptions and core workflow guidance;
- `skills/*/references/` for duplicated or drifting detailed guidance;
- bundled scripts under `skills/*/scripts/`;
- `prompts/skill-retrospective.md` and recent prompt files;
- recent commits when available, especially clusters of skill-retro updates.

Focus on:

- duplicated guidance across skills;
- trigger overlap or unclear skill boundaries;
- skill bloat, including one-off bullets without concrete failure signals;
- local conventions leaking into general-purpose skills;
- guidance that should move from `SKILL.md` into `references/`;
- guidance that should become a deterministic script;
- bundled scripts that are stale, too narrow, duplicated, or under-validated;
- missing cross-links between related skills;
- no-action findings where existing guidance is already enough.

Report using this shape:

```md
## Skill Repository Retrospective

### High-Value Consolidations
### Bloat Or Drift Risks
### Trigger Boundary Issues
### Script Opportunities
### Reference/Structure Improvements
### No-Action Findings
### Recommended Edits
```

For each recommended edit, include:

- file and line evidence for the current state;
- current location;
- proposed destination;
- reason;
- risk if omitted;
- whether it should be done now or deferred.

Prefer pruning, consolidating, or clarifying existing skills over creating new
skills. Recommend a new skill only when no existing skill, reference, prompt, or
script is a natural home.
