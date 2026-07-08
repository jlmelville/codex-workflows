# Codex Workflows

These are the last human words you are going to read on this repo. I am experimenting with Codex
skills and this is the repo for them. Apart from that, I am just going to let Codex do its thing.

Personal Codex skills and supporting scripts for software work.

This repository is the source of truth. The installed copy lives under
`~/.codex/skills`, where Codex can discover skills automatically. Edit skills
here, commit them, then run `./install.sh` to sync them into the active Codex
configuration.

## Layout

```text
skills/
  r-*              R package development workflows
  python-*         Python project workflows
  <generic>        Cross-language repo, CI, shell, and dependency workflows
prompts/
  *.md             Reusable prompts for skill-adjacent intake and review
scripts/
  validate-skills.sh
  list-skills.rb
  audit-skill-drift.rb
  audit-skill-drift-triage.tsv
install.sh
```

Future skills should use the same shape:

```text
skills/<skill-name>/
  SKILL.md
  agents/openai.yaml
  references/
  scripts/
  assets/
```

Only include `references/`, `scripts/`, or `assets/` when the skill actually
needs them.

## Skill Families

- `r-*`: R package workflows, tests, documentation, Rcpp, performance, and CI
  hardening.
- `python-*`: Python project workflows for `uv`, pytest, Ruff, typing, and
  package layout.
- `local-*`: durable James-local workflows for machine-local files or data
  surfaces that recur across sessions.
- Generic skills cover cross-language operations such as skill repository
  maintenance, AGENTS.md maintenance, GitHub Actions hardening, dependency PR
  review, repository bootstrap, notebook inspection, uv sandbox execution, and
  shell script quality.

Prefer concise skills with narrow trigger descriptions. Put repo/user
documentation here in the README, not inside individual skill folders.

## Prompts

Use [prompts/skill-retrospective.md](prompts/skill-retrospective.md) at the end
of project work to ask an agent for skill candidates. Prompt templates are for
skill-adjacent intake and review; they are not installed into `~/.codex/skills`.

## Retrospective Workflow

There are three loops:

1. **Project/session loop**: in another repo, ask an agent to use
   `$skill-retro` at the end of a meaningful coding session, investigation, CI
   debug, or cleanup. The output is a Skill Candidate Report in chat; it should
   not edit `codex-workflows` directly.
2. **Accepted-report loop**: in this repo, paste accepted candidate reports and
   invoke `$skill-retro-triage`. That workflow turns accepted reports into
   scoped source edits, validation, install sync when `skills/` changed, commit,
   and push.
3. **Repository outer loop**: periodically run the
   [Skill Repository Retrospective Prompt](prompts/skill-repository-retrospective.md)
   in this repo after several skill-retro-driven updates. This is the "take
   stock of the whole skill system" pass: it reviews all skills, references,
   bundled scripts, prompts, recent commits, drift audit output, and the
   maintenance ledger for consolidation, bloat, trigger overlap, script
   opportunities, stale ledger entries, and no-action findings.

The outer loop is a prompt, not an installed skill. Ask for it explicitly, for
example: "Use `prompts/skill-repository-retrospective.md` to audit the current
state of this repo and all skills." It should produce a report in chat first.
Apply any accepted recommendations afterward with `$skill-retro-triage` or a
normal scoped repo-edit request.

For deferred observations about this repository that should survive chat
compaction but are not yet ready for a direct skill, prompt, or script change,
use the [skill maintenance ledger](skills/skill-retro/references/maintenance-ledger.md).
Review it during periodic skill repository retrospectives or after several
skill-retro-driven commits.

## Install

From this repo:

```sh
./install.sh
```

To install to a different Codex home:

```sh
CODEX_HOME=/path/to/.codex ./install.sh
```

The installer syncs `skills/*` into `${CODEX_HOME:-$HOME/.codex}/skills`.

## Validate

Run:

```sh
./scripts/validate-skills.sh
```

This checks basic skill frontmatter, UI metadata YAML, shell script syntax,
ShellCheck results, Ruby/Python/R script syntax, local links, skill references,
mirrored files, executable bits for bundled shell scripts, hard drift findings,
and smoke tests for substantial bundled script interfaces.

To review skill trigger and metadata shape, run:

```sh
./scripts/list-skills.rb
```

To run a bloat and drift review, run:

```sh
./scripts/audit-skill-drift.rb
```

This advisory audit reports always-loaded description budget, long or overlapping
skill descriptions, repeated helper names, repeated command guidance,
machine-specific paths, and repo-relative skill script references that may break
after installation. Findings are grouped as hard, review, or informational.
Accepted advisory findings live in
[scripts/audit-skill-drift-triage.tsv](scripts/audit-skill-drift-triage.tsv).
Each triage row records the audit section, a row substring to match, and the
rationale for accepting that finding.

Use `--strict-hard --hard-only` for validation that should fail only on hard
installed-runtime problems. Use `--strict` when a cleanup branch should fail if
any untriaged findings remain.

## Consistency Surfaces

Maintain this repo across four surfaces:

- Source validity: frontmatter, metadata, links, scripts, smoke tests, mirrored
  files, and workflow hardening.
- Installed validity: executable commands in installed skills should use
  `${CODEX_HOME:-$HOME/.codex}/skills/...` unless explicitly marked as
  source-repository commands.
- Cross-platform validity: shell, Ruby, Python, and R checks should keep Linux
  and macOS behavior in view when scripts become substantial.
- Drift validity: duplicated helpers, repeated command prose, overlapping
  triggers, machine-local paths, and large always-read skills need triage rather
  than automatic churn.

GitHub Actions runs the same validation on pushes and pull requests, plus a
lightweight workflow audit. A manual macOS validation job is available through
`workflow_dispatch` for cross-platform checks.

## License

This repository is licensed under the [MIT License](LICENSE).

## Local Tooling

Some skills assume these tools may be available in project worktrees:

- `python3` for bundled Python script validation
- Bash 3.2-compatible Bash for bundled shell scripts
- `ruby` for repository validation
- `rg` / `ripgrep` for repository and roxygen source searches
- `shellcheck` for shell script validation
- `perl` for roxygen odd-backtick audits
- `Rscript`
- `air`
- `actionlint`
- `uvx`
- `clang-format`

Project-specific package dependencies still belong in the project repo, not in
this workflow repository.
