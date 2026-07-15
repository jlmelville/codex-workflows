---
id: SCR-20260714-ruby-yaml-date-fixtures
accepted_date: "2026-07-14"
source_report_summary: "Ruby YAML parsing coerced an unquoted ISO date in a validator fixture to Date, exposing an implicit safe-load policy."
expected_behavior: "Ruby validators should handle YAML date values deliberately through quoting, permitted classes, or explicit rejection."
observed_behavior: "The retrospective validator self-test failed on an unspecified Date class until fixture dates and permitted classes were handled deliberately."
decisive_evidence:
  - "The self-test raised: Tried to load unspecified class: Date."
materially_distinct_attempts:
  - "The initial fixture with an unquoted date failed safe loading."
  - "Quoting fixture dates and permitting Date made the deterministic self-test pass."
trigger: "Writing a Ruby validator that parses YAML frontmatter containing date-like scalars."
non_trigger: "Validators that do not parse YAML, or schemas where date coercion is already explicitly tested and documented."
destination: "skills/skill-retro/references/maintenance-ledger.md"
verification_opportunity: "If another Ruby YAML validator is added, run its self-test with quoted and unquoted date fixtures and compare the declared policy."
redaction_review: "Raw transcripts, secrets, private repository contents, and unredacted machine-local paths were excluded."
disposition: accepted
verification: supported
verification_basis: deterministic-test
implementation_commit: ""
---

# SCR-20260714-ruby-yaml-date-fixtures

## Notes

The behavior is deterministic, but one occurrence does not yet justify a new
generic Ruby validator reference. The maintenance ledger owns the recurrence
threshold.
