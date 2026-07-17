# Audits And Review Packets

Use this with `$planning-workflow` when converting an audit, model critique, or
external review into executable repository work.

## Audit-To-Plan Conversion

Keep audits and execution plans separate when possible. Audits preserve raw
critique and evidence; execution plans convert that evidence into ordered work.

When converting an external audit or model review into a chunk plan:

1. Preserve the source audit.
2. Statically confirm findings before making them tasks.
3. Mark unverified claims.
4. Resolve open questions into explicit decisions where possible.
5. Include the source audit pointer, confirmed findings, guardrails, a decision
   log, open questions, and which claims still need test evidence.
6. Surface recommendations that consume paid services or quotas before
   accepting them into scope, especially model or API evals, paid CI, and
   hosted runners. Separate free static or local validation from cost-bearing
   execution, state whether the cost is one-time or recurring, and obtain
   explicit user acceptance before adding model-backed evals or recurring paid
   infrastructure.
7. Give every substantive recommendation one disposition in an itemized
   crosswalk: resolved with evidence, accepted into a named chunk, deferred
   with a review trigger, or declined with rationale.
8. Before closing the plan, re-read the source audit and reconcile the crosswalk
   against it. Do not infer audit completeness only from finishing the tasks
   that were transcribed into the execution queue.

## Stabilization Chunks

When a post-cleanup audit mixes small completion defects with broader future
quality work, keep the active cleanup bounded. Add a stabilization chunk for
confirmed finish-hygiene items, and move roadmap, research, or long-horizon
validation work into a separate plan with its own acceptance criteria.

## Review Packets

Review packets should be self-contained and should ask the reviewer to
challenge assumptions, gaps, and risks, not merely summarize the plan. Include
the narrow evidence needed for review and the specific questions to answer.
