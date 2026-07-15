# Retrospective Candidate Archive

This area stores accepted Skill Candidate Reports after the user has decided
they are worth acting on in `codex-workflows`.

Do not store raw transcripts, session logs, tool dumps, credentials, private
repository contents, or unredacted machine-local evidence here. Summarize the
source report and cite only the decisive, sanitized evidence needed to explain
the repository change.

## Accepted Records

Accepted records live in `retrospectives/accepted/` as Markdown files with YAML
frontmatter. Use
[templates/accepted-candidate.md](templates/accepted-candidate.md) for new
records.

The record ID format is:

```text
SCR-YYYYMMDD-short-slug
```

State is split into independent fields:

- `disposition`: `accepted`, `implemented`, `no-change`, `superseded`, or
  `reverted`
- `verification`: `unverified`, `supported`, or `contradicted`
- `verification_basis`: `none`, `later-session`, or `deterministic-test`

Use `verification: unverified` with `verification_basis: none` after ordinary
implementation when no later session or deterministic behavior check has
actually tested the rule. A static validation pass for a prose change is not
behavioral support.

## Validation

Run:

```sh
./scripts/validate-retrospectives.rb
```

The repository validator runs this automatically. The validator checks required
fields, duplicate IDs, state combinations, and obvious forbidden runtime or
session path patterns. These checks are guardrails, not a complete secret
scanner.
