# Audits And Review Packets

Use this with `$planning-workflow` when converting an audit, model critique, or
external review into executable repository work.

## Audit-To-Plan Conversion

When converting an external audit or model review into a chunk plan:

1. Preserve the source audit.
2. Re-check the available toolchain before inheriting limitations from the
   audit environment. Confirm consequential findings with the smallest
   deterministic public probe, focused test, dependency-source inspection, or
   equivalent executable evidence available; fall back to static confirmation
   only when execution remains unavailable. Treat a green general suite as
   baseline evidence, not as disproof of a claim about an input it never
   exercises.
3. Separate the factual observation, defect classification, and proposed
   remedy. Reproduce the observation, then name the violated contract or
   intended semantics before treating it as a defect. A true observation can
   still receive a no-change disposition when it violates no contract or the
   remedy would create an unjustified compatibility change.
4. When a recommendation would remove or normalize public behavior in
   multi-author code, inspect its introduction and evolution plus current
   consumers. Record contributor ownership when known, and put unresolved
   compatibility intent behind a separate user decision gate rather than
   bundling it into unrelated correctness work.
5. Label claims as confirmed, disproved, or still unverified and retain the
   decisive evidence for each disposition.
6. Resolve open questions into explicit decisions where possible.
7. Include the source audit pointer, confirmed findings, guardrails, a decision
   log, open questions, and which claims still need test evidence.
8. Surface recommendations that consume paid services or quotas before
   accepting them into scope, especially model or API evals, paid CI, and
   hosted runners. Separate free static or local validation from cost-bearing
   execution, state whether the cost is one-time or recurring, and obtain
   explicit user acceptance before adding model-backed evals or recurring paid
   infrastructure.
9. Give every substantive recommendation one disposition in an itemized
   crosswalk: resolved with evidence, accepted into a named chunk, deferred
   with a review trigger, or declined with rationale.
10. Before closing the plan, re-read the source audit and reconcile the crosswalk
   against it. Do not infer audit completeness only from finishing the tasks
   that were transcribed into the execution queue.

At plan creation and resume, verify that every source artifact required by the
exit criteria exists at its recorded path and has the promised visibility and
retention, such as a tracked file or an explicitly external artifact. If a
mandated final reread becomes impossible, restore the original evidence or get
an explicit operator waiver; do not reconstruct missing content and present it
as the source.

When later implementation or product decisions supersede an earlier
recommendation, update that recommendation's original crosswalk entry at the
time of the decision. Record the current disposition, rationale, and evidence
pointer so final closure does not have to infer which intermediate decisions
still apply.

## Review Target Identity

Every asynchronous review request should name the exact artifact set and an
immutable identity, and the response should echo both. Use a commit or tree for
clean tracked content; use a frozen packet copy or content digest for dirty,
ignored, untracked, or otherwise mutable artifacts.

Review-target identity covers the files or patch the reviewer saw; it does not
automatically make every scientific input or in-memory object content-addressed.
Keep run provenance separate with fixed inputs, settings, seeds, versions,
schemas, and semantic witnesses. For persistent numerical packets, use
[review-complete checkpoints](numerical-reproduction-work-packets.md#review-complete-checkpoints).
Add digests for data, intermediates, or results only when they are themselves
mutable review targets or an explicit integrity, regulatory, or
costly-regeneration requirement makes the digest decision-relevant.

Before applying findings, confirm that the current target still has the reviewed
identity. When it changed during review, treat the response as stale evidence:
reconcile each finding against the current artifact and rerun a targeted review
where needed. Do not apply or discard a mixed stale response wholesale. If no
stable snapshot can be supplied, serialize patch-and-review cycles.

## Bounded Independent Review

Use this loop only when the operator or active plan requires independent review.
Capture the scoped baseline before implementation, run focused validation, then
freeze the exact review target. Ask for a read-only bounded verdict. Permit at
most the agreed small correction and re-review allowance—one of each when the
operator requests a bounded loop without another limit—and stop on a pass.

Recorded mechanisms are never frozen against challenge. A reviewer may require
`scope-reopen` when a proven path plus a capacity or scope adjustment satisfies
the objective; splitting or repairing the replacement does not resolve that
finding. Also stop for disputed goals, low-value proof requests, repeated
concerns, or review growth comparable to the work. Compaction before a passing
verdict ends the live cycle; a later session must not infer acceptance.

When the operator requests several reviewers, give each a distinct contract
against one immutable target and collect the full panel before editing.
Deduplicate compatible findings into one correction pass and re-review the same
corrected identity. Panel size supplies parallel evidence; it does not authorize
serial rewrite loops or proactive reviewer panels for ordinary changes.

## Public API Value Gate

When an audit recommends new public diagnostics, result fields, metadata, or
resource controls, separate technical acceptance from product acceptance.
Retention should identify a recognizable user problem, a concrete action or
decision, a credible interpretation rule, evidence or peer precedent, and the
API, compute, memory, compatibility, and documentation costs. Correctness and
comprehensive tests do not by themselves justify public exposure.

If value remains hypothetical, prefer internalization or removal; do not expand
documentation to manufacture a use case for an already implemented surface.
For existing implementations, perform the disposition review read-only, put
unresolved retention behind an explicit user decision, and separate accepted
cleanup from final documentation into bounded follow-up packets.

## Stabilization Chunks

When a post-cleanup audit mixes small completion defects with broader future
quality work, keep the active cleanup bounded. Add a stabilization chunk for
confirmed finish-hygiene items, and move roadmap, research, or long-horizon
validation work into a separate plan with its own acceptance criteria.

## Review Packets

Review packets should be self-contained and should ask the reviewer to
challenge assumptions, gaps, and risks, not merely summarize the plan. Include
the narrow evidence needed for review and the specific questions to answer.

For planned reader-facing documentation, treat the plan as a coverage ledger,
not a prose outline. Let the applicable documentation guidance control visible
order, terminology, and explanatory depth. When that guidance calls for a cold
reader stage, limit the first packet to the rendered artifact, audience, reader
task, the document's reader-facing role, nearby-guide responsibilities, and an
explicit scope boundary; withhold implementation sources, plan or coverage
obligations, and prior reviews. Then use a later plan-aware packet for technical
reconciliation. For R package articles, follow
[the staged article review](../../r-docs-pkgdown/references/validation.md#review-planned-articles-in-two-stages).
