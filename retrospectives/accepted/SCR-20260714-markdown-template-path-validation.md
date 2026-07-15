---
id: SCR-20260714-markdown-template-path-validation
accepted_date: "2026-07-14"
source_report_summary: "Markdown template examples can accidentally match repository-path validation and fail when the referenced file does not exist."
expected_behavior: "Repository guidance should tell template authors to use existing repository paths or avoid nonexistent path-shaped placeholders."
observed_behavior: "A placeholder skill path in an accepted-candidate template failed repository validation; replacing it with an existing path passed."
decisive_evidence:
  - "The repository validator reported a missing repository path in the Markdown template."
materially_distinct_attempts:
  - "Validation with the nonexistent path-shaped placeholder failed."
  - "Validation after using an existing repository path passed."
trigger: "Adding or editing Markdown templates or documentation containing repository-relative path examples."
non_trigger: "Ordinary prose without path-shaped examples, or examples that reference files that exist."
destination: "skills/codex-skill-repo/SKILL.md"
verification_opportunity: "Run ./scripts/validate-skills.sh after changing Markdown examples; repository-path validation should reject nonexistent path-shaped examples."
redaction_review: "Raw transcripts, secrets, private repository contents, and unredacted machine-local paths were excluded."
disposition: implemented
verification: supported
verification_basis: deterministic-test
implementation_commit: "7922c42"
---

# SCR-20260714-markdown-template-path-validation

## Notes

The existing repository validator owns the executable check; this change only
documents how template authors can satisfy it without adding another script.
