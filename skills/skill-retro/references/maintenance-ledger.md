# Skill Maintenance Ledger

Use this ledger for observations about `codex-workflows` that should survive
context compaction and fresh-agent handoffs, but are not yet ready to become
direct skill guidance, a bundled script, or a prompt.

This is not a project plan. Keep entries short, evidence-based, and actionable.
Each open entry needs a review trigger and a next action.

## Review Cadence

Review this ledger:

- during `prompts/skill-repository-retrospective.md`;
- after several accepted skill-retro-driven commits in one area;
- when a candidate report says "no script needed" but command recipes are
  recurring;
- when a user asks how skill triage or this repository is shaping up.

When reviewing an entry, either close it, promote it to a concrete edit, or
refresh its trigger and next action. Do not let entries accumulate as generic
notes.

## Entry Template

```md
### short-entry-name
Status:
Last reviewed:
Review trigger:
Evidence:
Next action:
Close when:
```

## Open Entries

### always-read-skill-density
Status: Monitoring, partially acted.
Last reviewed: 2026-07-05.
Review trigger: Another cluster of skill-retro commits adds detailed command
recipes to one always-read `SKILL.md`, or a skill repository retrospective sees
repeated guidance that could move to `references/`.
Evidence: Roxygen markdown guidance grew in `r-docs-pkgdown/SKILL.md` during
R package cleanup triage. Commit `c7782cd` moved the detailed audit and
conversion workflow into `skills/r-docs-pkgdown/references/roxygen-markdown.md`.
Next action: On the next review, scan recent commits and large `SKILL.md`
files for detailed command blocks or repeated edge-case bullets. Move detail to
references when the top-level skill is no longer a routing/checklist layer.
Close when: Two consecutive skill repository retrospectives find no actionable
always-read density problem.

### roxygen-markdown-audit-helper-script
Status: Deferred script candidate.
Last reviewed: 2026-07-05.
Review trigger: One more R package hits the same roxygen markdown audit command
set, or an agent again trips over regex/shell quoting while auditing markdown
conversion.
Evidence: Several triage reports converged on roxygen-only `rg` searches, odd
backtick detection, `tools::checkRd`, second `roxygenise()` idempotence, and
shell-safe `#\x27` matching. The current guidance lives in
`skills/r-docs-pkgdown/references/roxygen-markdown.md`.
Next action: If the trigger fires, create
`skills/r-docs-pkgdown/scripts/audit-roxygen-markdown.sh` with modes or clear
output for global markdown config, `@md`/`@noMd`, raw roxygen macros, odd
backticks, and generated-doc drift checks. Validate with `bash -n`,
ShellCheck, `./scripts/validate-skills.sh`, and a representative run in an R
package.
Close when: The script is added and documented, or future retrospectives show
the commands are not recurring enough to justify a bundled script.
