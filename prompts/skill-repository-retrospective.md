# Skill Repository Retrospective Prompt

Audit this `codex-workflows` repository as a public skill system, not as an
ordinary codebase and not as a review of personal retrospective state.

Use this periodically after several skill-driven updates. Do not edit files,
create commits, sync installed skills, or open PRs unless explicitly asked.
Produce a report in chat.

Inspect:

- `skills/*/SKILL.md` trigger descriptions and core workflow guidance;
- `skills/*/agents/openai.yaml` display metadata and default prompts;
- `skills/*/references/` for duplicated or drifting detailed guidance;
- bundled scripts under `skills/*/scripts/`;
- root scripts and the installer ownership contract in `install.sh`;
- repository instructions in `AGENTS.md`;
- `.github/workflows/` and `.github/dependabot.yml`, including pinned tool
  acquisition and update ownership;
- prompts and recent source commits;
- managed runtime parity, when the installed runtime is available.

Do not require or inspect `CODEX_WORKFLOWS_STATE_DIR` for this artifact audit.
Inbox reports, verdict history, accepted evidence, drafts, ledgers, learning
audits, and cadence are disposable external state owned by the separate
learning-process retrospective.

Focus on:

- duplicated guidance across skills;
- trigger overlap or unclear skill boundaries;
- skill bloat, including one-off bullets without concrete failure signals;
- local conventions leaking into general-purpose skills;
- guidance that should move from `SKILL.md` into references;
- deterministic behavior that should become a script or validator;
- bundled scripts that are stale, too narrow, duplicated, or under-validated;
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
### Reference/Structure Improvements
### No-Action Findings
### Recommended Edits
```

For each recommended edit, include file and line evidence, current location,
proposed destination, reason, risk if omitted, and whether it should be done now
or deferred externally. Prefer pruning, consolidating, or clarifying existing
skills over creating new skills.
