# Legacy Papercut Review

Existing `PC-*` records remain review input in `review-queue`. Read selected records when relevant
under the parent skill's authority. New observations already use the shared review path and need
no papercut promotion step.

For legacy closure, use `no-action`, `local-fix`, `candidate`, `external-owner` or `duplicate`.
Keep the original observation, classifications, evidence and digest intact. A local-fix outcome
grants no authority over another repository; an external-owner outcome grants no messaging
authority.

For a legacy `candidate` closure, a linked `RC-*` record must exist first. Preserve the original
papercut as evidence and name its ID in the reviewed context. This compatibility operation does not
accept a shared change. A duplicate closure must point to an existing papercut.

Read [legacy closure](../../skill-retro/references/state-protocol.md#papercut-intake-and-closure)
before authorized closure. Read-only reviews leave records unchanged; capture authority alone
permits no closure. Finish state mutations with helper validation.
