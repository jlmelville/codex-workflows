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
4. Read `retrospectives/README.md` and
   `retrospectives/templates/accepted-candidate.md` when persisting or updating
   accepted candidate records.
5. Read each cited destination skill, reference, prompt, or script.
6. Run `./scripts/audit-skill-drift.rb` when bloat, trigger overlap,
   duplicate helpers, command repetition, machine paths, or installed-path
   drift might be relevant.
7. Run `./scripts/list-skills.rb` when frontmatter descriptions,
   trigger boundaries, or `agents/openai.yaml` may change.

## Triage Workflow

For each accepted candidate:

1. Classify the smallest outcome: direct edit, validation/script, ledger
   refresh, or no change.
2. Create or update a concise accepted record under
   `retrospectives/accepted/` using the archive template. Summarize accepted
   evidence; do not store raw transcripts, session logs, tool dumps, secrets,
   private repository contents, or unredacted machine-local paths.
3. Track `disposition`, `verification`, and `verification_basis` separately.
   Static validation of a prose or trigger change can justify `implemented`,
   but it does not by itself justify `verification: supported`.
   `verification_basis: later-session` requires a concrete ordinary-session
   observation: task, decisive behavior or failure, affected skill or prompt,
   and why it supports or contradicts the rule. Model self-report alone is
   insufficient.
4. Compare the candidate against open ledger entries. If the review trigger has
   fired or evidence has accumulated, promote the entry into a concrete change
   or close it. If not, refresh `Last reviewed`, `Evidence`, and `Next action`.
5. Look across all pasted candidates for repeated "no script needed" rationales,
   repeated command recipes, recurring drift findings, or several reports
   touching the same consistency surface.
6. Prefer validator or script changes for deterministic command behavior, file
   shape, schema, generated output, or fragile searches.
7. Do not add maintained prompt corpora, synthetic model fixtures, repeated
   model runs, `codex exec` benchmarks, raw trace archives, or model-backed CI
   merely to verify a skill edit.
8. Keep edits scoped, validate with `./scripts/validate-skills.sh`, and install
   plus `./install.sh --check` when files under `skills/` changed.

## Output

In the final response, report:

- candidates accepted and implemented;
- accepted records created or updated, including disposition and verification
  state;
- ledger entries reviewed, promoted, refreshed, or closed;
- validation and install/check status;
- any findings deliberately left as advisory with the next review trigger.
