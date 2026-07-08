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
Status: Monitoring, one no-action repository retrospective recorded.
Last reviewed: 2026-07-07.
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
That split now lives under `skills/planning-workflow/references/`. A 2026-07-06
`r-test-hygiene` triage added one focused coverage command and a short local
download fixture note, but did not show enough repeated detail to split another
reference. A 2026-07-06 `r-performance-workflow` triage added one adjacent-docs
rule for permanent benchmark harnesses, also below the split threshold. Another
2026-07-06 `r-test-hygiene` triage added concise visualization-output testing
guidance; the accumulated R test patterns should be reviewed together before
adding much more top-level detail. A later 2026-07-06 R test triage promoted
coverage details into `skills/r-test-hygiene/references/coverage-roi.md` while
keeping the obsolete-helper cleanup rule visible in `SKILL.md`. Another
2026-07-06 numerical-package triage added
`skills/r-test-hygiene/references/numerical-contracts.md` rather than growing
the always-read file with derivative and metadata testing details. A later
2026-07-06 skill repository retrospective found no urgent broad cleanup after
those moves, and promoted the remaining `r-test-hygiene` testthat edition
migration block into
`skills/r-test-hygiene/references/testthat-edition-migrations.md`. A 2026-07-07
triage added concise lifecycle/state refactor contract-test guidance to
`skills/r-test-hygiene/SKILL.md`; it stayed top-level because it is a routing
rule for when internal synthetic tests are justified, not a command recipe or
long example. A later 2026-07-07 autodiff-oracle triage put separate AD oracle
repo guidance in `skills/r-test-hygiene/references/numerical-contracts.md`,
avoiding another top-level `r-test-hygiene` section. A 2026-07-07 pkgdown
strict-reference-index triage added one short
`skills/r-docs-pkgdown/SKILL.md` bullet for a terse pkgdown failure, below the
threshold for another reference split. A later 2026-07-07 Python CLI triage
added one short numeric-vector parser smoke-test note to
`skills/python-uv-project-workflow/SKILL.md`, also below the split threshold. A
later 2026-07-07 numeric-oracle triage added one short cross-language tolerance
note to `skills/python-uv-project-workflow/SKILL.md`; the repeated Python
workflow additions remain concise and below a reference-split threshold. A
later 2026-07-07 derivative-oracle triage added one scalar-first sequencing
sentence to the same paragraph, still below the split threshold. A
later 2026-07-07 performance triage added one short benchmark-gated public
method graduation rule to `skills/r-performance-workflow/SKILL.md`. A
2026-07-07 skill repository retrospective reviewed the recent cluster, drift
audit output, and current always-read file sizes; it found no new split
candidate beyond the already completed planning and R test reference moves. A
later 2026-07-07 coverage-blind semantic-probe triage added focused guidance
to `skills/r-test-hygiene/references/coverage-roi.md`, keeping another R test
lesson out of the always-read `SKILL.md`. A later 2026-07-07 symmetric
validation diagnostic triage added one short `r-test-hygiene/SKILL.md` section
because paired validation branches are a test-design rule rather than a command
recipe. A later 2026-07-07 planning triage added concise top-level
`planning-workflow/SKILL.md` notes for filtered artifact discovery,
self-referential commit hashes in plans, and managed-sandbox `git -C` fallback;
the cluster was reviewed against the existing planning reference split and did
not justify another reference yet. A later 2026-07-07 numerical optimizer
variant triage added trace-level recipe-equivalence invariant guidance to
`skills/r-test-hygiene/references/numerical-contracts.md`, again keeping the
R test always-read file from growing.
Next action: On the next repository retrospective, scan recently changed
always-read skills for another concrete split candidate before adding more
top-level detail.
Close when: Two consecutive skill repository retrospectives find no actionable
always-read density problem.

### quiet-r-parse-checks
Status: Monitoring after one noisy ad hoc parse-check transcript.
Last reviewed: 2026-07-07.
Review trigger: Another R package session uses `R -q -e 'parse(...)'` or a
similar ad hoc syntax check and prints parsed expressions or truncates tool
output.
Evidence: A 2026-07-07 R package cleanup used `R -q -e 'parse(...)'`; the
syntax check succeeded but printed parsed expressions and produced a truncated
transcript with original token count 24921.
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
