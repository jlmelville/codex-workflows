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
Status: Monitoring, planning split acted.
Last reviewed: 2026-07-06.
Review trigger: Another cluster of skill-retro commits adds detailed command
recipes to one always-read `SKILL.md`, or a skill repository retrospective sees
repeated guidance that could move to `references/`.
Evidence: Roxygen markdown guidance grew in `r-docs-pkgdown/SKILL.md` during
R package cleanup triage. Commit `c7782cd` moved the detailed audit and
conversion workflow into `skills/r-docs-pkgdown/references/roxygen-markdown.md`.
The 2026-07-06 skill repository retrospective identified
`skills/planning-workflow/SKILL.md` as the next large always-read candidate:
its core routing is useful, but chunk-plan details, audit/review-packet
recipes, visibility edge cases, and handoff examples could move to references.
That split now lives under `skills/planning-workflow/references/`.
Next action: On the next repository retrospective, scan recently changed
always-read skills for another concrete split candidate before adding more
top-level detail.
Close when: Two consecutive skill repository retrospectives find no actionable
always-read density problem.

## Closed Entries

### action-pin-comment-tag-verification
Status: Closed by script.
Last reviewed: 2026-07-06.
Review trigger: Another non-Dependabot review questions whether GitHub Actions
version comments beside full-SHA pins match upstream tag refs, or an agent
manually repeats `git ls-remote` checks for several actions outside dependency
update PR validation.
Evidence: A follow-up review questioned comments such as `# v7.0.0`; manual
`git ls-remote` checks confirmed the pinned SHAs matched upstream tags for
`actions/checkout`, `actions/upload-artifact`, and
`actions/download-artifact`. Existing `dependabot-pr-maintenance` covers tag
verification for GitHub Actions dependency PRs, while
`github-actions-hardening` covers stale nearby version comments but did not
make remote comment verification a routine audit step.
Resolution: Added
`skills/github-actions-hardening/scripts/check-action-tag-comments.sh` with
offline parsing by default and an explicit `--verify-remote` mode for
`git ls-remote` checks.
Closed when: The script was added and documented in GitHub Actions hardening
guidance.

### roxygen-markdown-audit-helper-script
Status: Closed by script.
Last reviewed: 2026-07-06.
Review trigger: One more R package hits the same roxygen markdown audit command
set, or an agent again trips over regex/shell quoting while auditing markdown
conversion.
Evidence: Several triage reports converged on roxygen-only `rg` searches, odd
backtick detection, `tools::checkRd`, second `roxygenise()` idempotence, and
shell-safe `#\x27` matching.
Resolution: Added
`skills/r-docs-pkgdown/scripts/audit-roxygen-markdown.sh` and documented it in
`skills/r-docs-pkgdown/SKILL.md` and
`skills/r-docs-pkgdown/references/roxygen-markdown.md`.
Closed when: The script was added and documented.
