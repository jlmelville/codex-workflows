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

Use `verification_basis: deterministic-test` only for directly executable
contracts such as scripts, schemas, generated output, metadata shape, installer
behavior, or other behavior that a local test actually exercised.

Use `verification_basis: later-session` only when an ordinary later session
supplies concrete evidence. The record must cite the observed task, the
decisive behavior or failure, the affected skill or prompt, and why the
observation supports or contradicts the rule. Model self-report alone is not
evidence.

Do not create maintained prompt corpora, synthetic fixture repositories for
model execution, `codex exec` benchmark runners, positive-control model calls,
raw trace archives, or model-backed CI lanes merely to verify skill edits.
Behavioral evidence should come from deterministic local checks or ordinary
later sessions.

## Validation

Run:

```sh
./scripts/validate-retrospectives.rb
```

The repository validator runs this automatically. The validator checks required
fields, duplicate IDs, state combinations, and obvious forbidden runtime or
session path patterns. These checks are guardrails, not a complete secret
scanner.
