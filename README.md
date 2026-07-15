# Codex Workflows

These are the last human words you are going to read on this repo. I am experimenting with Codex
skills and this is the repo for them. Apart from that, I am just going to let Codex do its thing.

Personal Codex skills and supporting scripts for software work.

This repository is the source of truth. The installed copy lives under
`${CODEX_HOME:-$HOME/.codex}/skills`, where Codex discovers skills
automatically. Personal retrospective reports and housekeeping state live
outside Git beneath `CODEX_WORKFLOWS_STATE_DIR`.

## Quick Start

Run these commands from the repository root.

1. Install the managed skills:

   ```sh
   ./install.sh
   ```

2. Choose an external state directory and initialize it with the source-tree
   helper:

   ```sh
   export CODEX_WORKFLOWS_STATE_DIR=/path/to/personal/codex-workflows-state
   ./skills/skill-retro/scripts/retro-state.rb init
   ```

   Keep this environment variable available in shells where Codex should route
   or triage retrospective records. The helper creates the directory when
   needed and refuses to put operational state inside a Git worktree.

3. Confirm that the installed skills match the source tree:

   ```sh
   ./install.sh --check
   ```

After installation, the helper is available from any project repository:

```sh
"${CODEX_HOME:-$HOME/.codex}/skills/skill-retro/scripts/retro-state.rb" init
"${CODEX_HOME:-$HOME/.codex}/skills/skill-retro/scripts/retro-state.rb" pending
"${CODEX_HOME:-$HOME/.codex}/skills/skill-retro/scripts/retro-state.rb" validate
```

If `CODEX_WORKFLOWS_STATE_DIR` is unset, retrospective routing prints a
paste-ready candidate and writes nothing. External state may be pruned or lost
without invalidating the source repository or installed skills.

See [Repository Maintenance](docs/repository-maintenance.md) for custom
`CODEX_HOME` installation, dry runs, validation, audits, CI, and local tooling.

## How Source And State Fit Together

Edit skills in this repository, validate and commit them, then run
`./install.sh` to sync them into the active Codex configuration. The installer
manages only skills recorded in its manifest under `CODEX_HOME`; unrelated
installed skills are preserved.

Git stores reusable skills, prompts, deterministic tooling, schemas, fixtures,
and the small documentation needed to run the loops. The configured external
state directory stores disposable inbox reports, verdict history, accepted
evidence, drafts, ledgers, learning-process audits, and cadence state.

The complete state boundary and record lifecycle are documented in
[External Retrospective State Protocol](skills/skill-retro/references/state-protocol.md).

## Repository Layout

```text
skills/
  r-*              R package development workflows
  python-*         Python project workflows
  <generic>        Cross-language repo, CI, shell, and dependency workflows
prompts/
  *.md             Reusable prompts for skill-adjacent intake and review
docs/
  *.md             Human-facing architecture and maintenance documentation
scripts/
  validate-skills.sh
  list-skills.rb
  audit-skill-drift.rb
  audit-skill-drift-triage.tsv
install.sh
```

### Skill Families

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

Prefer concise skills with narrow trigger descriptions. Detailed authoring and
validation conventions are in
[Repository Maintenance](docs/repository-maintenance.md).

## Retrospective Workflow

There are three related loops:

1. **Project/session loop:** In another repository, ask an agent to use
   `$skill-retro` after meaningful coding, investigation, CI debugging, or
   cleanup. Default output stays in chat. Explicit `route` or `auto` mode may
   write a sanitized candidate only to the configured external inbox; the
   producing repository never needs the location of this source checkout.
2. **Triage loop:** In this repository, invoke `$skill-retro-triage` to judge
   pending external candidates independently. By default it presents verdicts
   and a proposed implementation batch before editing. After acceptance it
   updates external outcome records, makes scoped public source changes,
   validates, installs when needed, commits, and pushes.
3. **Repository outer loop:** Periodically use the
   [Skill Repository Retrospective Prompt](prompts/skill-repository-retrospective.md)
   to review the public skill system for consolidation, bloat, trigger overlap,
   script opportunities, and drift. It reports in chat before changes are
   applied.

Use [the stable retrospective prompt](prompts/skill-retrospective.md) to request
session candidates. Prompt templates are skill-adjacent entry points and are
not installed into `CODEX_HOME`.

The artifact-focused repository retrospective deliberately does not inspect
personal state. Use the separate
[Learning Process Retrospective Prompt](prompts/learning-process-retrospective.md)
to review external report quality, verdict patterns, deferrals, drafts, and
verification evidence.

## Routine Maintenance

The normal repository checks are:

```sh
./scripts/validate-skills.sh
./install.sh
./install.sh --check
```

Run the advisory skill-system audit when reviewing trigger overlap, bloat, or
drift:

```sh
./scripts/audit-skill-drift.rb
```

See [Repository Maintenance](docs/repository-maintenance.md) for the full
command reference, validation scope, consistency surfaces, CI behavior, and
tool prerequisites.

## License

This repository is licensed under the [MIT License](LICENSE).
