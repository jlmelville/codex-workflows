# Skill Maintenance Ledger

Use this ledger for observations about `codex-workflows` that should survive
context compaction and fresh-agent handoffs, but are not yet ready to become
direct skill guidance, a bundled script, or a prompt.

This is not a project plan. Keep entries short, evidence-based, and actionable.
Each open entry needs a review trigger and a next action.

## Review Cadence

Review this ledger:

- during `prompts/skill-repository-retrospective.md`;
- when using `$skill-retro-triage` on accepted reports;
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
Status: Monitoring after two repository retrospectives; one deferred planning
reference split candidate recorded.
Last reviewed: 2026-07-08.
Review trigger: Another cluster of skill-retro commits adds detailed command
recipes to one always-read `SKILL.md`, the deferred `planning-workflow`
ExecPlan split is touched, or a skill repository retrospective sees repeated
guidance that could move to `references/`.
Evidence: Earlier triage moved detailed roxygen markdown, planning, coverage
ROI, numerical contract, and testthat edition migration guidance into
references instead of growing always-read `SKILL.md` files. Later accepted
triages mostly added concise top-level routing rules where immediacy mattered
or placed details in existing references. The 2026-07-07 repository
retrospective found no urgent broad cleanup beyond completed planning and R test
reference moves. The 2026-07-08 repository retrospective again found no broad
merge or immediate split, but noted `skills/planning-workflow/SKILL.md` remains
the largest always-read skill and deferred a possible ExecPlan reference split.
Next action: When `planning-workflow` is next edited for ExecPlan guidance,
consider moving the detailed ExecPlan skeleton and decision-entry template into
a new reference; otherwise review again after another cluster of top-level
skill-retro additions.
Close when: Two consecutive skill repository retrospectives find no actionable
always-read density problem.

### quiet-r-parse-checks
Status: Monitoring after one noisy ad hoc parse-check transcript.
Last reviewed: 2026-07-08.
Review trigger: Another R package session uses `R -q -e 'parse(...)'` or a
similar ad hoc syntax check and prints parsed expressions or truncates tool
output.
Evidence: A 2026-07-07 R package cleanup used `R -q -e 'parse(...)'`; the
syntax check succeeded but printed parsed expressions and produced a truncated
transcript with original token count 24921. The 2026-07-08 repository
retrospective saw no recurrence.
Next action: If this recurs, smoke-test a quiet command such as
`invisible(lapply(files, parse)); cat("parse OK\n")`, then add a short note to
`skills/r-package-workflow/references/checks.md`.
Close when: The quiet parse-check note is added after recurrence, or two skill
repository retrospectives find no repeated parse-check noise.

## Closed Entries

### plugin-gh-fix-ci-public-run-fallback
Status: Closed by source-owned GitHub Actions guidance.
Last reviewed: 2026-07-07.
Review trigger: Another CI debugging session hits invalid `gh` auth while a
public repo's push workflow run is missing from connector or PR-oriented lookup,
or the GitHub plugin source becomes editable through an upstream path.
Evidence: A pkgdown CI investigation had invalid local `gh` auth, connector
lookup returned no PR-triggered runs for the target head, and the public GitHub
Actions REST run list identified the failing push run. A later repository
retrospective found that `skills/github-actions-hardening/SKILL.md` now carries
a source-owned public CI triage fallback for invalid `gh` auth and public
Actions metadata.
Resolution: Closed the external/plugin-owned advisory instead of editing the
plugin cache; use the source-owned `github-actions-hardening` fallback unless
upstream plugin maintenance is explicitly in scope.
Closed when: Source-owned GitHub CI debugging guidance covered the public
unauthenticated metadata fallback.

### action-pin-comment-tag-verification
Status: Closed by routine audit and optional remote script.
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
offline nearby-comment parsing in routine `audit-actions.sh`, plus explicit
`--require-tag --verify-remote` mode for `git ls-remote` checks.
Closed when: Routine workflow audits check nearby pin comments, and stricter
remote tag verification remains available for targeted reviews.

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
