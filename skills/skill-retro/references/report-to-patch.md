# Skill Candidate Implementation

Use after triage has judged external candidate evidence and the user has
accepted the proposed implementation batch.

## State Before Source

Read [state-protocol.md](state-protocol.md). Use the external helper to attach a
complete verdict and archive each processed candidate. A deferred decision must
name a review trigger, next action, and close condition. Split and merge
decisions must retain all originating opaque IDs.

Do not copy inbox, archive, accepted, draft, ledger, audit, or cadence documents
into the source repository. They are disposable operational state beneath
`CODEX_WORKFLOWS_STATE_DIR`.

## Public Change

For each accepted candidate:

1. Re-read the destination before editing.
2. Identify one atomic missing delta.
3. Choose the smallest destination:
   - `SKILL.md` for triggers, routing, must-remember rules, or short checklists;
   - `references/` for detailed edge cases, recipes, workflows, or examples;
   - `scripts/` for deterministic checks or repeated fragile commands;
   - `prompts/` for reusable instructions to ask another agent or model;
   - no public edit when existing coverage is sufficient or evidence remains
     local.
4. Add or update deterministic validation for command behavior, schema, file
   shape, generated output, or fragile searches.
5. Make the source change understandable without the external record. Do not
   leak private repository names, candidate evidence, or opaque state IDs into
   Git merely to preserve provenance.
6. When frontmatter descriptions, trigger boundaries, or `agents/openai.yaml`
   change, run `./scripts/list-skills.rb` and inspect the affected rows.
7. Run `./scripts/validate-skills.sh`.
8. If files under `skills/` changed, run `./install.sh` and
   `./install.sh --check`.
9. Inspect staged paths, commit only intended public source, and push when
   repository instructions require it.

## External Accepted Record

After the public commit exists, create or update a concise external accepted
record. Store plural `originating_candidate_ids`, sanitized evidence,
destination, trigger and non-trigger, verification opportunity, disposition,
verification state and basis, and known implementation commits.

Keep disposition and verification independent. A static validation pass for a
prose or routing edit does not prove the guidance worked later. Use
`later-session` only for an ordinary task that records the decisive behavior or
failure and explains why it supports or contradicts the guidance. Model
self-report alone is insufficient. Use `deterministic-test` only for executable
behavior actually exercised.

Finish by running the external helper's `validate` command. Failure to update
disposable state does not invalidate an otherwise correct public source commit;
repair the record later if it remains useful.
