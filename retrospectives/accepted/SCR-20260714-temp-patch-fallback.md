---
id: SCR-20260714-temp-patch-fallback
accepted_date: "2026-07-14"
source_report_summary: "Combined validation of overlapping bot PRs needed a patch-based fallback when a clean checkout inherited Git transport configuration that prevented PR-ref fetches."
expected_behavior: "When temporary-checkout PR fetching is blocked by inherited URL rewriting or SSH configuration, the skill should direct agents to materialize reviewed patches, apply them sequentially, and validate the combined result."
observed_behavior: "A clean HTTPS clone retained an SSH-routed origin and could not fetch PR refs; applying five reviewed PR patches sequentially reproduced a combined state that passed the workflow validators."
decisive_evidence:
  - "Fetching a PR ref failed because the effective SSH transport could not use the local SSH configuration."
  - "Five patches obtained from GitHub applied sequentially with three-way fallback and produced the expected combined pin updates."
  - "The resulting combined state passed actionlint, the repository R CI audit, and zizmor."
materially_distinct_attempts:
  - "A clean clone and direct PR-ref fetch was attempted first but inherited an unusable Git transport configuration."
  - "Materialized PR patches were then applied sequentially to the clean checkout and validated as one combined state."
trigger: "Combined validation of overlapping dependency-bot PRs when a clean checkout cannot fetch PR refs because inherited Git or SSH transport configuration is unusable."
non_trigger: "Normal PR validation when refs fetch successfully, or patches that have not already been reviewed and matched to the intended PRs."
destination: "skills/dependabot-pr-maintenance/SKILL.md"
verification_opportunity: "In a later ordinary batch-PR session with blocked PR-ref fetching, confirm that every reviewed patch applies cleanly, the combined diff is complete, and all relevant workflow validators pass."
redaction_review: "Raw transcripts, secrets, private repository contents, and unredacted machine-local paths were excluded."
disposition: implemented
verification: unverified
verification_basis: none
implementation_commit: ""
---

# SCR-20260714-temp-patch-fallback

## Notes

The accepted change is a short fallback in the existing pinned-actions audit.
No script is warranted after one occurrence because the sequence is simple and
environment-dependent. The source session supports the candidate, but the new
prose remains unverified until an ordinary later session exercises it.
