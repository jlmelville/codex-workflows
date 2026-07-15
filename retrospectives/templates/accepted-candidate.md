---
id: SCR-YYYYMMDD-short-slug
accepted_date: YYYY-MM-DD
source_report_summary: "One or two sentences summarizing the accepted chat report without raw transcript text."
expected_behavior: "What the skill, prompt, script, or repository workflow should do."
observed_behavior: "What happened in the source session that made the candidate useful."
decisive_evidence:
  - "Sanitized command, warning, failure signal, or behavior summary."
materially_distinct_attempts:
  - "Attempt or occurrence that contributed independent evidence."
trigger: "When this guidance should apply."
non_trigger: "When this guidance should not apply."
destination: "skills/skill-retro/SKILL.md or another repository-relative destination."
verification_opportunity: "Name a deterministic local check or ordinary later-session observation; do not propose synthetic model evals."
redaction_review: "Confirm that raw transcripts, secrets, private repo contents, and unredacted local paths were excluded."
disposition: accepted
verification: unverified
verification_basis: none
implementation_commit: ""
---

# SCR-YYYYMMDD-short-slug

## Notes

Keep this record concise. Store the accepted evidence and decision context, not
a transcript.

For `verification_basis: later-session`, cite the observed task, decisive
behavior or failure, affected skill or prompt, and why the observation supports
or contradicts the rule. For prose or trigger changes with no such evidence,
leave `verification: unverified` and `verification_basis: none`.
