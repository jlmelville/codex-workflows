---
name: skill-retro-triage
description: Triage accepted Skill Candidate Reports and maintenance-ledger items in codex-workflows. Use when Codex is asked to turn pasted retrospectives into repo changes, review deferred skill maintenance, decide whether ledger evidence now justifies action, or consolidate repeated skill-retro recommendations.
---

# Skill Retro Triage

Use this for implementation triage after `$skill-retro` reports are accepted.
Do not use it for generating the original retrospective report.

## Required Context

Before editing:

1. Re-read the accepted candidate text.
2. Read `skills/skill-retro/references/report-to-patch.md`.
3. Read `skills/skill-retro/references/maintenance-ledger.md`.
4. Read each cited destination skill, reference, prompt, or script.
5. Run `./scripts/audit-skill-drift.rb` when bloat, trigger overlap,
   duplicate helpers, command repetition, machine paths, or installed-path
   drift might be relevant.
6. Run `./scripts/list-skills.rb` when frontmatter descriptions,
   trigger boundaries, or `agents/openai.yaml` may change.

## Triage Workflow

For each accepted candidate:

1. Classify the smallest outcome: direct edit, validation/script, ledger
   refresh, or no change.
2. Compare the candidate against open ledger entries. If the review trigger has
   fired or evidence has accumulated, promote the entry into a concrete change
   or close it. If not, refresh `Last reviewed`, `Evidence`, and `Next action`.
3. Look across all pasted candidates for repeated "no script needed" rationales,
   repeated command recipes, recurring drift findings, or several reports
   touching the same consistency surface.
4. Prefer validator or script changes for deterministic command behavior, file
   shape, schema, generated output, or fragile searches.
5. Keep edits scoped, validate with `./scripts/validate-skills.sh`, and install
   plus diff source versus runtime skills when files under `skills/` changed.

## Output

In the final response, report:

- candidates accepted and implemented;
- ledger entries reviewed, promoted, refreshed, or closed;
- validation and install/diff status;
- any findings deliberately left as advisory with the next review trigger.
