# Skill Candidate Implementation

Use after triage has judged external candidate evidence and implementation is
authorized, including an already accepted batch.

## State Before Source

Read the protocol's [Installed Helper](state-protocol.md#installed-helper) and
[Triage And Archive](state-protocol.md#triage-and-archive) before archiving each
complete verdict with the helper. Preserve all originating IDs; use
`reconsider` for a fired deferral to retain its lineage. For mixed batches,
adjudicate verification proposals separately through the
[verification protocol](state-protocol.md#accepted-records-and-verification).

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

For an accepted already-landed change, verify the exact public landing commit
and current destination after normal verdict archival. If no source delta
remains, proceed to External Accepted Record using that commit, skipping only
source, installation, and publication work already completed. Finish any
independently required checks; do not re-land the change or make an empty source
commit. Keep a new outcome implemented and behaviorally unverified unless
qualifying evidence establishes more.

For each accepted candidate that still needs source work:

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

After the public commit exists, read
[Accepted Records And Verification](state-protocol.md#accepted-records-and-verification).
For a new outcome, use `prepare-accepted --id RC-ID --commit SHA`; repeat origins and commits when
needed, and see `--help`. Complete the blank outcome fields and judge the final destination and
evidence. Curate the prior candidate context before submitting with `record-accepted`. The draft
preserves known linkage without treating the original proposal as the implemented outcome. For an
existing identity, use `prepare-accepted-update` and `update-accepted` instead.

Store sanitized evidence, destination, trigger and non-trigger, verification opportunity,
disposition, verification state and basis, applied proposal provenance, and known public commits.

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
candidate. Close a residual contradiction ledger only after the old accepted record is `superseded`,
`reverted`, or explicitly retained under the state protocol; preserve its contradiction evidence.

For implementation drift under a still-valid decision, update the existing
accepted record after publication with the repaired destination and commit.
Preserve its verification state and basis unless independent later-session or
deterministic evidence changes them.

Finish by running the external helper's `validate` command. Failure to update
disposable state does not invalidate an otherwise correct public source commit;
repair the record later if it remains useful.
