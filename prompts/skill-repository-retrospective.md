# Skill Repository Retrospective Prompt

Audit this `codex-workflows` repository as a skill system, not as an ordinary
codebase.

Use this periodically after several skill-retro-driven updates. Do not edit
files, create commits, sync installed skills, or open PRs unless explicitly
asked. Produce a report in chat.

Inspect:

- `skills/*/SKILL.md` trigger descriptions and core workflow guidance;
- `skills/*/agents/openai.yaml` display metadata and default prompts;
- `skills/*/references/` for duplicated or drifting detailed guidance;
- `skills/skill-retro/references/maintenance-ledger.md` for deferred
  observations, review triggers, and script/consolidation thresholds;
- bundled scripts under `skills/*/scripts/`;
- root scripts under `scripts/` and the installer ownership contract in
  `install.sh`;
- repository instructions in `AGENTS.md`;
- `.github/workflows/` and `.github/dependabot.yml`, including pinned tool
  acquisition and update ownership;
- accepted retrospective records under `retrospectives/accepted/`, especially
  disposition, verification state, and later-session evidence;
- managed runtime parity checks, when the installed runtime is available;
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
- accepted candidate evidence that overstates verification or lacks a clear
  redaction/implementation state;
- CI or installer drift that can change validation without a repository diff;
- missing cross-links between related skills;
- no-action findings where existing guidance is already enough.

Report using this shape:

```md
## Skill Repository Retrospective

### High-Value Consolidations
### Bloat Or Drift Risks
### Trigger Boundary Issues
### Script Opportunities
### Deferred Maintenance Ledger
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

When a deferred ledger item is no longer useful, recommend closing it. When its
trigger has fired, recommend the concrete skill, reference, script, or prompt
change and cite the evidence.
