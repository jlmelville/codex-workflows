# Skill Candidate Implementation

Use after triage has judged external candidate evidence and the user has
accepted the proposed implementation batch.

## State Before Source

Read [state-protocol.md](state-protocol.md). Use the external helper to attach a
complete verdict and archive each processed candidate. A deferred decision must
name the unresolved decision and use the structured trigger contract: durable
predicate, observer, `review-queue` route, probe, next action, and close
condition. Later behavioral uncertainty after a justified implementation uses
an unverified accepted outcome instead. Split and merge decisions must retain
all originating opaque IDs. When a deferred trigger later fires, use
`reconsider --id ID --decision PATH` so the replacement verdict keeps the
original triage lineage. Adjudicate each verification proposal separately with
`process-verification`; an applied proposal updates its existing accepted
identity and a rejected proposal does not.

Do not copy candidate or verification inbox, archive, accepted, draft, ledger,
audit, or cadence documents into the source repository. They are disposable
operational state beneath `CODEX_WORKFLOWS_STATE_DIR`.

## Batch Review

Before editing source, compare accepted candidates across the batch for repeated
producer mistakes, command recipes, drift findings, or shared consistency
surfaces. Recommend producer feedback immediately, but edit `$skill-retro` only
after recurrence across batches or especially decisive evidence accepted by the
user.

## Public Change

For each accepted candidate:

1. Re-read the destination before editing.
2. Identify the decision, authority boundary, required observation, or success
   condition changed by the missing delta.
3. Implement the semantic role selected during triage:
   - keep compact default judgment in `SKILL.md` when it must be available as
     soon as the skill triggers;
   - put exact commands, APIs, tool behavior, environment requirements, file
     formats, and conditional recipes in a routed reference or deterministic
     script;
   - keep a sanitized case capsule in an optional skill-local casebook only
     when its plausible wrong implementation or observation boundary is
     distinct;
   - process a typed external verification proposal without a public edit when
     the evidence is another occurrence of an existing decision and witness.
4. Treat `references/` as a loading mechanism, not a semantic category. A
   reference may need restructuring when it mixes default judgment, mechanics,
   and cases that should load under different conditions.
5. Reject an incident-shaped default rule when an existing principle, routed
   mechanic, optional case, or verification record is the truthful home. Add a
   new clause only when the condition changes the action, constraint, required
   witness, or success claim.
6. For same-decision implementation drift, repair the missed or stale public
   surface under the existing accepted outcome even though the candidate's
   semantic verdict is `no-change`.
7. Add or update deterministic validation for command behavior, schema, file
   shape, generated output, or fragile searches.
8. Make the source change understandable without the external record. Do not
   leak private repository names, candidate evidence, or opaque state IDs into
   Git merely to preserve provenance.
9. When frontmatter descriptions, trigger boundaries, or `agents/openai.yaml`
   change, run `./scripts/list-skills.rb` and inspect the affected rows.
10. Run `./scripts/validate-skills.sh`.
11. If files under `skills/` changed, run `./install.sh` and
   `./install.sh --check`.
12. Inspect staged paths, commit only intended public source, and push when
   repository instructions require it.

Execute fired non-skill ledger actions rather than refreshing them indefinitely.
Activate, revise, or deprecate fired drafts.

## External Accepted Record

After the public commit exists, create or update a concise external accepted
record. Store plural `originating_candidate_ids`, sanitized evidence,
destination, trigger and non-trigger, verification opportunity, disposition,
verification state and basis, applied proposal provenance, and known
implementation commits.

Keep disposition and verification independent. A static validation pass for a
prose or routing edit does not prove the guidance worked later. Use
`later-session` only for an ordinary task that records the decisive behavior or
failure and explains why it supports or contradicts the guidance. Model
self-report alone is insufficient. Use `deterministic-test` only for executable
behavior actually exercised.

State the claim that evidence supports: executable correctness, conformance to
guidance, or occurrence of the intended outcome. Do not claim comparative
improvement unless the observation includes an actual comparator.

For a correction, keep recurrence and replacement separate. Update the existing
accepted identity with preserved contradiction evidence. Create a new accepted
identity only when the correction candidate changes the decision; let
`record-accepted` derive its `supersedes_accepted_ids` from the archived
candidate. Do not close a residual contradiction ledger until the old accepted
record is marked `superseded` or `reverted`.

For implementation drift under a still-valid decision, update the existing
accepted record after publication with the repaired destination and commit.
Preserve its verification state and basis unless independent later-session or
deterministic evidence changes them.

Finish by running the external helper's `validate` command. Failure to update
disposable state does not invalidate an otherwise correct public source commit;
repair the record later if it remains useful.
