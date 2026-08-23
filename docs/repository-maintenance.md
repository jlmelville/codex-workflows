# Repository Maintenance

This document contains the detailed installation, authoring, validation, and
tooling reference for `codex-workflows`. Start with the repository
[README](../README.md) for installation and retrospective-state setup.

## Skill Shape

Future skills should use this layout:

```text
skills/<skill-name>/
  SKILL.md
  agents/openai.yaml
  references/
  scripts/
  assets/

.agents/skills/<repo-only-skill> -> ../../skills/<repo-only-skill>
```

Only include `references/`, `scripts/`, or `assets/` when the skill actually
needs them. Prefer concise skills with narrow trigger descriptions. Put
human-facing repository documentation in the README or `docs/`, not inside
individual skill folders.

Before adding or restructuring learned guidance, follow the semantic admission
and casebook policy in
[`semantic-authoring.md`](../skills/codex-skill-repo/references/semantic-authoring.md).
It distinguishes default judgment, routed exact mechanics, optional cases, and
external verification. Moving text into a reference changes loading, but does
not by itself reduce the number of decisions in the corpus.

## Installation Details

Install the user-scoped portion of the source tree into the user-wide skill
directory:

```sh
./install.sh
```

Canonical skill content remains under `skills/`. A tracked relative symlink
under `.agents/skills` marks a skill as repository-local; Codex discovers that
skill only while working in this checkout. The installer validates those links
and excludes their targets from the user-wide installation.

All remaining skills are synced into `$HOME/.agents/skills`, the current Codex
`USER` skill location. The installer writes a managed-skill manifest at
`$HOME/.agents/codex-workflows-managed-skills.tsv`. On the first run without a
manifest, the current user-scoped source skill names become the ownership set;
later runs remove only stale skills named in the previous manifest. Unrelated
installed skills are preserved. When a formerly user-scoped skill becomes
repository-local, the next install removes its old user-wide copy only when the
previous manifest proves this repository owned it.

Earlier versions installed into `${CODEX_HOME:-$HOME/.codex}/skills`. When the
old Codex home contains this repository's managed-skill manifest, a normal
install first writes the current runtime and then removes only legacy skills
named by that old manifest. It removes the old manifest after a successful
migration. `--dry-run` previews that migration without writing to either
location, and `--check` reports an incomplete legacy migration.

`CODEX_HOME` still controls Codex configuration and global instruction files;
it no longer selects this repository's user-skill destination. For isolated
installer testing, set both `HOME` and `CODEX_HOME` to temporary directories.
Some bundled Codex system-skill guidance may still mention
`${CODEX_HOME:-$HOME/.codex}/skills` during the location transition; this
repository follows the current official `USER` location table linked from the
README.

Preview changes without replacing installed skills:

```sh
./install.sh --dry-run
```

Confirm that managed user-scoped skills match the source tree, repository-local
links resolve to their canonical sources, no local skill is duplicated in the
user scope, and relevant file modes match:

```sh
./install.sh --check
```

Do not hand-edit installed copies. Port useful diagnostic changes back to the
source repository and reinstall them.

### User-global instruction setup

The skill installer writes only `$HOME/.agents/skills`, its ownership manifest,
and repository-managed legacy copies during migration. Repository-local links
are tracked source that it validates but does not rewrite. It never edits
`AGENTS.md`, `AGENTS.override.md`, `config.toml`, shell startup files, or
external retrospective state.

Standing papercut capture and automatic retrospective evaluation therefore have
a separate one-time setup step. Their canonical instruction block is
[`skills/skill-retro/assets/global-agents-learning.md`](../skills/skill-retro/assets/global-agents-learning.md).
After installing the skills:

- copy the installed asset from `$HOME/.agents/skills/skill-retro/assets`
  to `${CODEX_HOME:-$HOME/.codex}/AGENTS.md` only when neither
  `AGENTS.md` nor `AGENTS.override.md` exists in that Codex home;
- otherwise merge or replace its `## Workflow papercuts` and
  `## Workflow retrospectives` sections;
- when `${CODEX_HOME:-$HOME/.codex}/AGENTS.override.md` exists, update the
  override instead because it takes precedence over the base global file;
- restart Codex or open a new thread after changing the active global file;
- after later source updates, reinstall skills and compare the canonical asset
  with the previously copied section because global instructions are not
  updated automatically.

Removing either section disables that policy globally. A closer repository
instruction or explicit task instruction may opt out without changing the
canonical template.

## Validation

Run the repository validator before committing:

```sh
bundle install
./scripts/validate-skills.sh
```

Bundler installs the formatter/linter pinned in `Gemfile.lock`; the validator
never installs dependencies implicitly. On distributions that expose only a
versioned Bundler executable, use the matching command such as `bundle3.3`.
System Ruby packages may also require their matching development-header package
before Bundler can compile native dependencies.

The validator reports local `actionlint` and `zizmor` versions that do not
match the versions pinned for CI. Treat the report as advisory locally and run
the parity check explicitly before claiming CI-equivalent results:

```sh
./scripts/check-ci-tool-parity.sh --strict
```

Under `CI=true`, the parity check is strict automatically.

It checks skill frontmatter, UI metadata YAML, shell syntax, ShellCheck results,
Ruby syntax and Standard Ruby conformance, Python/R script syntax, local links,
skill references, mirrored files, executable modes for bundled shell scripts,
hard drift findings, installer behavior, and substantial bundled-script
interfaces. The retro-state smoke test uses temporary fixtures; repository
validation never reads the live `CODEX_WORKFLOWS_STATE_DIR`.

Review skill trigger and metadata shape with:

```sh
./scripts/list-skills.rb
```

Run the advisory bloat and drift audit with:

```sh
./scripts/audit-skill-drift.rb
```

The audit reports always-loaded description budget, long or overlapping skill
descriptions, repeated helper names, repeated command guidance, machine-specific
paths, and repo-relative skill-script references that may break after
installation. Findings are grouped as hard, review, or informational. Accepted
advisory findings live in
[`scripts/audit-skill-drift-triage.tsv`](../scripts/audit-skill-drift-triage.tsv);
each row records the audit section, a row substring to match, and the rationale
for accepting that finding.

Use `--strict-hard --hard-only` for validation that should fail only on hard
installed-runtime problems. Use `--strict` when a cleanup branch should fail if
any untriaged findings remain.

For new or substantially changed skills, also run the system skill quick
validator when its dependencies are available. If it needs Python packages such
as PyYAML, use temporary `uv` state rather than modifying the project.

Markdown templates and documentation are subject to repository-path
validation. Use real existing repository paths in examples, or avoid
placeholder text shaped like a repository-relative path when no such file
exists.

For workflow changes, run the source-tree workflow audit when present:

```sh
./skills/github-actions-hardening/scripts/audit-actions.sh --quiet .github/workflows
```

When adding or changing a manual validation lane, push it, trigger it once with
`gh workflow run`, watch it to completion, and fix setup failures.

## Consistency Surfaces

Maintain the repository across four surfaces:

- **Source validity:** frontmatter, metadata, links, scripts, smoke tests,
  mirrored files, and workflow hardening.
- **Runtime validity:** executable commands in user-scoped skills should use
  `${HOME}/.agents/skills/...` unless explicitly marked as source-repository
  commands; repository-local links must resolve to canonical source without a
  duplicate user-scoped copy.
- **Cross-platform validity:** shell, Ruby, Python, and R checks should keep
  Linux and macOS behavior in view when scripts become substantial.
- **Drift validity:** duplicated helpers, repeated command prose, overlapping
  triggers, machine-local paths, and large always-read skills need triage rather
  than automatic churn.

When changing shared tool policy, common command examples, or duplicated
bundled scripts, search the whole skill tree for stale parallel guidance. If
two scripts are intentionally mirrored, update both or record why they differ.

GitHub Actions runs the repository validation on pushes and pull requests, plus
a lightweight workflow audit. A manual macOS validation job is available
through `workflow_dispatch` for cross-platform checks.

## Publication Checklist

Before publishing an accepted change:

1. Run `./scripts/validate-skills.sh`.
2. Run `./install.sh` when files under `skills/` changed.
3. Run `./install.sh --check`.
4. Stage only intended files.
5. Inspect `git diff --cached --stat` and
   `git diff --cached --name-only`.
6. Commit and push to `origin/main` unless the user says otherwise.

Use `$skill-retro-triage` for accepted Skill Candidate Reports after re-reading
the cited destinations. Personal candidate, ledger, draft, audit, and cadence
state remains beneath `CODEX_WORKFLOWS_STATE_DIR` and must not be committed.

## Deferred Maintenance

Put skill-repository observations that should survive chat compaction but are
not ready for a public edit in the external maintenance ledger defined by the
[state protocol](../skills/skill-retro/references/state-protocol.md). Review
those entries during periodic learning-process retrospectives or when related
skill changes suggest consolidation. Public source validity must not depend on
that disposable state.

## Repository Maintainer Tooling

This inventory covers tools used to maintain and validate this repository. It
does not include tools such as Air, Perl, or clang-format that individual
skills may use later inside other project repositories.

| Tool | Required when | Version authority | Installation policy |
| --- | --- | --- | --- |
| Git and Bash | Cloning, installing, validating, and publishing | Host package manager; shell scripts remain compatible with macOS Bash 3.2 | Use the platform package manager or operating-system copy. |
| Ruby and Bundler | All repository validation | `.ruby-version` selects the CI Ruby; `Gemfile.lock` pins Bundler and StandardRB | Use Homebrew, apt, or a Ruby version manager; run `bundle install` in the repository. |
| ShellCheck | All repository validation | Host package manager and CI runner | Use Homebrew or the distribution package. |
| Python 3 | Syntax-checking bundled Python scripts | Host package manager and CI runner | Use Homebrew, apt, or the operating-system package. No project virtual environment is required. |
| R / `Rscript` | Syntax-checking bundled R scripts | Host package manager and CI runner | Use Homebrew or the distribution package. |
| ripgrep | Maintainer searches and CI diagnostics | Host package manager and CI runner | Use Homebrew or the distribution package. |
| actionlint | Workflow changes and CI | `ACTIONLINT_VERSION` in `.github/workflows/validate.yml` | Use Homebrew on macOS; on Linux use a distribution package, upstream release, or the pinned `go install` route used by CI. |
| zizmor | Workflow changes and CI | `.github/requirements.txt` | Use Homebrew on macOS; on Linux use an upstream-supported package route such as pipx or Cargo. |
| GitHub CLI (`gh`) | Inspecting PRs and workflow runs or triggering manual CI | Host package manager | Optional for ordinary validation; install through Homebrew or the supported platform package. |
| uv / `uvx` | Optional temporary Python-tool execution | Host package manager; not a repository dependency | Install through Homebrew or upstream only when a temporary tool workflow needs it. Do not create a persistent repository `.venv` for maintainer CLIs. |

For a typical macOS maintainer setup, install the host tools with Homebrew, make
the chosen Ruby available on `PATH`, and then install the locked Ruby
dependencies:

```sh
brew install git ruby python shellcheck ripgrep r actionlint zizmor gh
bundle install
```

On Debian-like Linux, install the broadly available system dependencies with
apt, then use the supported upstream package route for actionlint and zizmor
when the distribution does not provide a suitable package:

```sh
sudo apt-get update
sudo apt-get install -y git bash ruby-full bundler shellcheck python3 r-base ripgrep
bundle install
```

Local package-manager versions may be newer than CI. That is acceptable for
ordinary validation; use `./scripts/check-ci-tool-parity.sh --strict` only when
claiming exact actionlint and zizmor parity with CI. The check reports the
resolved executable path and never prepends an ignored repository environment.

### Update ownership

| Surface | Update route |
| --- | --- |
| GitHub Actions SHAs | Weekly Dependabot PRs; keep nearby version comments synchronized. |
| StandardRB and its Ruby dependencies | Weekly Bundler Dependabot PRs through `Gemfile.lock`. |
| zizmor | Weekly pip Dependabot PRs through `.github/requirements.txt`. |
| Ruby version | Manual update of `.ruby-version`, followed by Linux and manual macOS CI. |
| actionlint | Manual update of `ACTIONLINT_VERSION`, followed by the workflow audit and CI. |
| Host tools | `brew update && brew upgrade` or the operating system's normal package-update workflow. |
| Optional uv | Update through the package manager that installed it; it is not tracked for CI parity. |

Project-specific package dependencies still belong in the project repository,
not in this workflow repository.
