# Skill Candidate Implementation

Use after a Skill Candidate Report has been accepted for `codex-workflows`.

For each candidate:

1. Re-read the cited existing skill, reference, prompt, or script before
   editing.
2. Create or update an accepted record under `retrospectives/accepted/` only
   after user acceptance. Use `retrospectives/templates/accepted-candidate.md`
   and summarize the report instead of storing raw transcripts, session logs,
   tool outputs, credentials, private repository contents, or unredacted
   machine-local evidence.
3. Persist these accepted-record fields:
   - stable `id` using `SCR-YYYYMMDD-short-slug`;
   - source-report summary;
   - expected behavior and observed behavior;
   - decisive evidence and materially distinct attempts;
   - trigger and non-trigger;
   - destination;
   - verification opportunity;
   - redaction review;
   - `disposition`: `accepted`, `implemented`, `no-change`, `superseded`, or
     `reverted`;
   - `verification`: `unverified`, `supported`, or `contradicted`;
   - `verification_basis`: `none`, `later-session`, or `deterministic-test`;
   - implementation commit when known.
4. Treat disposition and verification as independent. A deterministic validator
   can support directly executable behavior, but a static validation pass for a
   prose or routing change does not prove the rule worked in a later session.
5. Use `verification_basis: later-session` only for ordinary-session evidence
   that cites the observed task, decisive behavior or failure, affected skill
   or prompt, and why it supports or contradicts the rule. Model self-report
   alone is insufficient.
6. Do not create maintained prompt corpora, synthetic fixture repositories for
   model execution, `codex exec` benchmark runners, positive-control model
   calls, raw trace archives, or model-backed CI lanes merely to validate a
   skill edit.
7. Classify the smallest destination:
   - `SKILL.md`: routing, trigger boundaries, must-remember rules, or short
     checklists.
   - `references/`: detailed edge cases, command recipes, workflows, or
     examples.
   - `scripts/`: deterministic checks or repeated fragile commands.
   - `prompts/`: reusable instructions for another agent or model.
   - `maintenance-ledger.md`: threshold-based observations not ready for a
     direct change.
8. Write one atomic edit per missing delta.
9. Add or update validation when the lesson is about command behavior, schema,
   file shape, generated output, or fragile search patterns.
10. When frontmatter descriptions, trigger boundaries, or `agents/openai.yaml`
   change, run `./scripts/list-skills.rb` and inspect affected rows for
   description length, display text, and default prompt shape.
11. Run `./scripts/validate-retrospectives.rb --self-test` when accepted records
   or archive policy changed.
12. Run `./scripts/validate-skills.sh`.
13. If files under `skills/` changed and installed runtime parity matters, run
   `./install.sh` and confirm managed installed skills with:

```sh
./install.sh --check
```

14. In the final response, cite the candidate source, accepted-record status,
   files changed, validation run, install/check status, and any deferred items.
