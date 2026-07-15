---
id: SCR-20260714-ci-tool-pinning-owned-update-lane
accepted_date: "2026-07-14"
source_report_summary: "Pinned CI validation tools need repository-owned updates and visible version output so reproducibility does not depend on invisible package-index movement or forgotten inline pins."
expected_behavior: "CI tools with a stable package-manager lane should use it; exceptional inline pins should name a manual owner and compatibility constraint, while floating platform tools should print their versions."
observed_behavior: "The repository added Dependabot-owned pins for uv and zizmor, but a later retrospective found actionlint stale at v1.7.7 with no explicit owner; the workflow now centralizes the Go-compatible v1.7.11 pin, assigns its review to the repository retrospective, and isolates macOS Python tools from Homebrew's externally managed environment."
decisive_evidence:
  - "Commit b22d2d2 added .github/requirements.txt, a pip Dependabot lane, and validation-tool version output."
  - "The remote Ubuntu validation run for b22d2d2 completed successfully."
  - "A later repository retrospective found actionlint v1.7.11 compatible with the workflow's Go 1.24 runner while the inline workflow pin remained at v1.7.7."
  - "The first manual cross-platform run installed actionlint v1.7.11 on macOS, then exposed a PEP 668 failure from installing Python tools into Homebrew's externally managed environment."
materially_distinct_attempts:
  - "The earlier workflow acquired validation tools without complete repository-owned version constraints."
  - "The revised workflow installs pinned requirements and makes future updates reviewable through Dependabot."
  - "The follow-up retrospective caught the separately pinned actionlint version and assigned it an explicit manual update path."
  - "The failed macOS run led to a runner-temporary virtual environment for the pinned Python tools instead of overriding system-package protections."
trigger: "CI installs validation tools from package indexes or another version-moving external source."
non_trigger: "Action references already covered by GitHub Actions pinning, or ordinary local use of installed tools outside CI acquisition."
destination: ".github/workflows/validate.yml and prompts/skill-repository-retrospective.md"
verification_opportunity: "Run local repository and workflow validation, then dispatch the validation workflow so both Ubuntu and macOS exercise the centralized actionlint pin."
redaction_review: "Raw transcripts, secrets, private repository contents, and unredacted machine-local paths were excluded."
disposition: implemented
verification: unverified
verification_basis: none
implementation_commit: ""
---

# SCR-20260714-ci-tool-pinning-owned-update-lane

## Notes

No additional skill rule is needed. Dependabot owns the Python requirements;
the outer retrospective owns the compatibility-sensitive actionlint pin.
Runner or operating-system tools remain version-visible rather than fully
pinned. The first manual macOS run exposed and localized a Python environment
setup failure after actionlint installed successfully. Verification of the
virtual environment fix and complete two-platform lane is pending.
