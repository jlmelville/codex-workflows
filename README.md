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
scripts/
  validate-skills.sh
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

- `r-*`: R package workflows, tests, documentation, Rcpp, and CI hardening.
- `python-*`: reserved for Python packaging, testing, linting, typing, and
  project workflow skills.
- Generic skills can live beside language-specific skills, for example
  `plan-work`, `design-system`, or `review-architecture`.

Prefer concise skills with narrow trigger descriptions. Put repo/user
documentation here in the README, not inside individual skill folders.

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

This checks basic skill frontmatter, UI metadata YAML, shell script syntax, and
executable bits for bundled shell scripts.

GitHub Actions runs the same validation on pushes and pull requests, plus a
lightweight workflow audit and ShellCheck when available.

## Local Tooling

Some skills assume these tools may be available in project worktrees:

- `ruby` for repository validation
- `Rscript`
- `air`
- `actionlint`
- `uvx`
- `clang-format`

Project-specific package dependencies still belong in the project repo, not in
this workflow repository.
