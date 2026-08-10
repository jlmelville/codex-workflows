# Audits And Review Packets

Use this with `$planning-workflow` when converting an audit, model critique, or
external review into executable repository work.

## Audit-To-Plan Conversion

Keep audits and execution plans separate when possible. Audits preserve raw
critique and evidence; execution plans convert that evidence into ordered work.

When converting an external audit or model review into a chunk plan:

1. Preserve the source audit.
2. Statically confirm findings before making them tasks.
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
5. Mark unverified claims.
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
