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
manifest, the current user-scoped source skill names become the ownership set.
For each source name absent from the previous manifest, an existing target is
adopted only when its complete tree matches source; a different target is
preserved and stops the install as an unowned collision. Later runs remove only
stale skills named in the previous manifest. When a formerly user-scoped skill
becomes repository-local, the next install removes its old user-wide copy only
when the previous manifest proves this repository owned it.

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
user scope, relevant file modes match, and the active global learning block is
current:

```sh
./install.sh --check
```

Do not hand-edit installed copies. Port useful diagnostic changes back to the
source repository and reinstall them.

### User-global instruction setup

The installer owns the marked global learning block sourced from
[`skills/skill-retro/assets/global-agents-learning.md`](../skills/skill-retro/assets/global-agents-learning.md).
It writes that block to `${CODEX_HOME:-$HOME/.codex}/AGENTS.override.md` when
the override exists, otherwise to `AGENTS.md`, matching Codex's global
instruction precedence. Existing unrelated bytes remain outside the marked
block and preserve their file mode. On first install, an exact unmarked copy of
the canonical asset at the top of the active file is adopted without
duplication.

`./install.sh` updates stale owned content and removes an owned block from the
inactive base file when an override becomes active. It refuses symlinked global
instruction files, duplicate or unpaired markers, or an owned block away from
the top rather than guessing. `--dry-run` reports the same decisions without
writing, and `--check` requires the active block to match source and the
inactive file to be free of owned content.

The installer does not edit `config.toml`, shell startup files, external
retrospective state, or unrelated global instructions. Those host-specific
surfaces must be bootstrapped before the installer can reliably select Ruby.
Restart Codex or open a new thread after the active global instruction file or
shell-environment policy changes.

### Ruby and Codex shell bootstrap

Bootstrap a new machine in this order:

1. Install the platform packages needed to compile Ruby.
2. Install rbenv and its ruby-build plugin.
3. Initialize rbenv in the Bash login profile that Codex will load.
4. Start a new login shell, clone this repository, and install the version in
   `.ruby-version`.
5. Enable Codex profile loading, restart Codex, and run the checks below.

This order needs no intermediate repository edit: rbenv installation and shell
initialization are host prerequisites, while `.ruby-version` supplies the exact
version only after the checkout exists.

For Bash, add the following to the active login startup file. Debian-like
systems normally use `~/.profile` when neither `~/.bash_profile` nor
`~/.bash_login` exists; if `~/.bash_profile` exists, put the block there or
source `~/.profile` from it.

```sh
if [ -x "$HOME/.rbenv/bin/rbenv" ]; then
    eval "$("$HOME/.rbenv/bin/rbenv" init - --no-rehash bash)"
elif command -v rbenv >/dev/null 2>&1; then
    eval "$(rbenv init - --no-rehash bash)"
fi
```

The first branch supports rbenv's upstream Git-checkout layout; the second
supports package-manager installations already visible on `PATH`. The
`--no-rehash` form retains rbenv's shim and shell setup without regenerating
shims on every login.

After starting a fresh login shell from the repository checkout, finish Ruby
selection and verify the host shell:

```sh
rbenv install -s "$(cat .ruby-version)"
command -v ruby
ruby --version
./scripts/check-ruby-runtime.sh
```

Then merge the following key into the existing table in
`~/.codex/config.toml`:

```toml
[shell_environment_policy]
experimental_use_profile = true
```

The current
[Codex configuration reference](https://developers.openai.com/codex/config-reference/)
documents this setting as loading the user shell profile for subprocesses. It
therefore carries rbenv's shim `PATH` into Codex commands without hard-coding a
complete machine-specific `PATH` in TOML. Its name remains experimental, so
validate the installed Codex version and restart before relying on it:

```sh
codex --strict-config --version
```

An already-running Codex session can retain its previous command environment.
After restarting or opening a new thread, verify there that `command -v ruby`
resolves to the rbenv shim and that `./scripts/check-ruby-runtime.sh` passes.

The `.ruby-version` file controls repository commands, while installed helper
shebangs set `RBENV_VERSION` to prevent a different project's `.ruby-version`
from changing their interpreter. Both layers rely on the rbenv shims being
present on the command `PATH`; no user-wide `rbenv global` selection is
required.

## Validation

Run the repository validator before committing:

```sh
rbenv install -s "$(cat .ruby-version)"
bundle install
./scripts/validate-skills.sh
```

The exact CRuby version in `.ruby-version` is the runtime contract for both
repository maintenance and installed Ruby helpers. rbenv is the supported user
selector. `./scripts/check-ruby-runtime.sh`, the installer, and the validator
verify the selected engine and version before mutation or validation work. A
generic system Ruby is not a supported fallback; an exact CRuby installed by
another mechanism is acceptable when it is the `ruby` resolved on `PATH`.

An ordinary `.ruby-version` affects version-manager selection only relative to
the current working directory. Installed helpers can run from arbitrary
repositories, so each executable Ruby program also selects the repository
version through `RBENV_VERSION` in its `env -S` shebang and enforces the same
contract in-process. The runtime check executes a real shebang probe from a
directory containing a deliberately conflicting `.ruby-version`.

Bundler installs only the repository-development formatter/linter pinned in
`Gemfile.lock`; installed helpers use the Ruby standard library and do not run
through Bundler. The validator never installs dependencies implicitly. Run
`bundle install` under the selected repository Ruby.

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

Run the drift and instructional-payload audit with:

```sh
./scripts/audit-skill-drift.rb
```

The audit reports description and instructional payloads, overlap, repeated
helpers or commands, machine paths, and installed-path risks. Payload ceilings
cover physical lines and whitespace-normalized characters so line reflow cannot
conceal growth. Neither measure is a semantic score. Payload growth and broken
runtime guidance are hard; semantic findings remain advisory.
Accepted advisory findings live in
[`scripts/audit-skill-drift-triage.tsv`](../scripts/audit-skill-drift-triage.tsv);
each row records the audit section, a row substring to match, and the rationale
for accepting that finding.

Use `--strict-hard --hard-only` for repository validation and `--strict` when a
cleanup branch should fail on every untriaged finding. Payload limits live in
[`scripts/audit-skill-drift-payload-baseline.tsv`](../scripts/audit-skill-drift-payload-baseline.tsv)
and may move down, not up, during ordinary maintenance. The initial character
limits preserve accepted content plus 100 characters per unused line in the
corresponding line ceiling; do not regenerate them automatically.

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

Use `$skill-retro-triage` for accepted Skill Candidate Reports and Verification
Evidence Proposals after re-reading the cited destinations. Personal candidate,
verification, ledger, draft, audit, and cadence state remains beneath
`CODEX_WORKFLOWS_STATE_DIR` and must not be committed.

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
| CRuby | Installing, validating, and running bundled Ruby helpers | `.ruby-version` is the exact source, CI, and installed-helper version | Use rbenv as the supported user selector and install the exact repository version. Another provider is acceptable only when `ruby` resolves to that exact CRuby. |
| Bundler and StandardRB | Repository development and validation only | `Gemfile` binds Ruby to `.ruby-version`; `Gemfile.lock` records the Ruby and gem dependency graph | Run `bundle install` in the repository under its selected Ruby. Installed helpers do not depend on Bundler. |
| ShellCheck | All repository validation | Host package manager and CI runner | Use Homebrew or the distribution package. |
| Python 3 | Syntax-checking bundled Python scripts | Host package manager and CI runner | Use Homebrew, apt, or the operating-system package. No project virtual environment is required. |
| R / `Rscript` | Syntax-checking bundled R scripts | Host package manager and CI runner | Use Homebrew or the distribution package. |
| ripgrep | Maintainer searches and CI diagnostics | Host package manager and CI runner | Use Homebrew or the distribution package. |
| actionlint | Workflow changes and CI | `ACTIONLINT_VERSION` in `.github/workflows/validate.yml` | Use Homebrew on macOS; on Linux use a distribution package, upstream release, or the pinned `go install` route used by CI. |
| zizmor | Workflow changes and CI | `.github/requirements.txt` | Use Homebrew on macOS; on Linux use an upstream-supported package route such as pipx or Cargo. |
| GitHub CLI (`gh`) | Inspecting PRs and workflow runs or triggering manual CI | Host package manager | Optional for ordinary validation; install through Homebrew or the supported platform package. |
| uv / `uvx` | Optional temporary Python-tool execution | Host package manager; not a repository dependency | Install through Homebrew or upstream only when a temporary tool workflow needs it. Do not create a persistent repository `.venv` for maintainer CLIs. |

For a typical macOS maintainer setup, install rbenv, ruby-build's recommended
build libraries, and the host tools with Homebrew. Initialize rbenv in the Bash
login profile as described above, start a new login shell, and then install the
repository Ruby and locked development dependencies:

```sh
brew install git rbenv ruby-build openssl@3 readline libyaml gmp autoconf
brew install python shellcheck ripgrep r actionlint zizmor gh
rbenv install -s "$(cat .ruby-version)"
./scripts/check-ruby-runtime.sh
bundle install
```

On Debian-like Linux, install the host tools and ruby-build's
[suggested build environment](https://github.com/rbenv/ruby-build/wiki#suggested-build-environment)
with apt. In particular, `libyaml-dev` is required for CRuby's Psych extension;
omitting it can leave a seemingly installed Ruby unable to load YAML. The
distribution rbenv package is commonly stale, so the upstream
[rbenv installation guide](https://github.com/rbenv/rbenv#basic-git-checkout)
recommends a Git checkout. Install the ruby-build plugin as well because it
provides `rbenv install`:

```sh
sudo apt-get update
sudo apt-get install -y git bash shellcheck python3 r-base ripgrep \
  build-essential autoconf libssl-dev libyaml-dev zlib1g-dev \
  libffi-dev libgmp-dev rustc
git clone https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
git clone https://github.com/rbenv/ruby-build.git \
  "$HOME/.rbenv/plugins/ruby-build"
```

Add the Bash login-profile block above and start a fresh login shell. Then clone
this repository and run:

```sh
rbenv install -s "$(cat .ruby-version)"
./scripts/check-ruby-runtime.sh
bundle install
```

Use supported upstream package routes for actionlint and zizmor when the
distribution does not provide suitable packages.

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
| Ruby version | Manual coordinated update of `.ruby-version`, `Gemfile.lock`, every executable Ruby shebang and guard, followed by the runtime-policy check, full validation, Linux CI, and manual macOS CI. |
| actionlint | Manual update of `ACTIONLINT_VERSION`, followed by the workflow audit and CI. |
| Host tools | `brew update && brew upgrade` or the operating system's normal package-update workflow. |
| Optional uv | Update through the package manager that installed it; it is not tracked for CI parity. |

Project-specific package dependencies still belong in the project repository,
not in this workflow repository.
