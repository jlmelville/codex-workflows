---
id: SCR-20260714-ci-tool-pinning-owned-update-lane
accepted_date: "2026-07-14"
source_report_summary: "Pinned CI validation tools need repository-owned dependency updates and visible version output so reproducibility does not depend on invisible package-index movement."
expected_behavior: "CI should acquire validation tools from repository-controlled pins, expose their versions, and assign future updates to an owned dependency lane."
observed_behavior: "The validation workflow previously installed one tool without a version constraint and could acquire another through a fallback; the repository now pins both in a requirements file, prints versions, and gives Dependabot ownership."
decisive_evidence:
  - "Commit b22d2d2 added .github/requirements.txt, a pip Dependabot lane, and validation-tool version output."
  - "Local repository validation and the workflow audit passed after the change."
materially_distinct_attempts:
  - "The earlier workflow acquired validation tools without complete repository-owned version constraints."
  - "The revised workflow installs pinned requirements and makes future updates reviewable through Dependabot."
trigger: "CI installs validation tools from package indexes or another version-moving external source."
non_trigger: "Action references already covered by GitHub Actions pinning, or ordinary local use of installed tools outside CI acquisition."
destination: "prompts/skill-repository-retrospective.md"
verification_opportunity: "Run ./scripts/validate-skills.sh and ./skills/github-actions-hardening/scripts/audit-actions.sh .github/workflows; separately confirm a remote validation run when CI execution evidence is required."
redaction_review: "Raw transcripts, secrets, private repository contents, and unredacted machine-local paths were excluded."
disposition: no-change
verification: supported
verification_basis: deterministic-test
implementation_commit: "b22d2d2"
---

# SCR-20260714-ci-tool-pinning-owned-update-lane

## Notes

No additional skill rule is needed. The repository configuration and outer
retrospective prompt own the behavior. Deterministic support covers local
configuration and audit checks; the CI installation was not executed remotely
in the source session.
