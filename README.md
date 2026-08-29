# Codex Workflows

<!-- USER-AUTHORED PREAMBLE: Preserve verbatim unless James explicitly requests a change. -->
These are the last human words you are going to read on this repo. I am
experimenting with Codex skills and this is the repo for them. Apart from that,
I am just going to let Codex do its thing.
<!-- END USER-AUTHORED PREAMBLE -->

Personal Codex skills shared across machines, with an external learning loop
that lets agents improve those skills from experience. The aim is to keep the
human loop small without turning the public repository into an archive of
incidents.

## System Model

The system has three parts:

- **Source:** this Git repository contains the durable skills, prompts, and
  tooling shared between laptops.
- **Runtime and discovery:** `./install.sh` copies user-scoped skills into
  `$HOME/.agents/skills`, while tracked links under `.agents/skills` expose
  repository-only skills inside this checkout. These are the current `USER`
  and `REPO` locations documented by
  [OpenAI](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills).
  The installer also maintains the canonical global learning block in the
  active Codex instruction file. It tracks its owned content and leaves
  unrelated installed skills and instructions alone.
- **Learning state:** `CODEX_WORKFLOWS_STATE_DIR` holds papercuts, candidate
  reports, triage outcomes, and other working state outside the source
  repository and Codex home.

The user runtime and learning state are replaceable. Git remains the source of
truth for reusable behavior and repository-local discovery links.

```text
project work -> papercuts and retros -> triage -> skill changes -> Git
                                                               |
                                                pull and install on each laptop
```

## Discover Capabilities

Generate the current human-facing skill catalogue from canonical skill
frontmatter and `agents/openai.yaml` metadata:

```sh
./scripts/list-skills.rb --catalog
```

The catalogue shows each capability, its activation contract, a copy-ready
invocation, and whether the skill includes scripts, references, or assets. It is
generated on demand so the README does not become a second skill inventory.

## Set Up A Laptop

Install [rbenv](https://github.com/rbenv/rbenv#installation), ruby-build, and
the platform packages needed to compile Ruby first. The exact macOS and
Debian-like package lists are in
[Repository Maintenance](docs/repository-maintenance.md#repository-maintainer-tooling).

For Bash, load rbenv from the login profile that Codex can import. On the
Debian-like setup used here, with no `~/.bash_profile` or `~/.bash_login`, add
this to `~/.profile`:

```sh
if [ -x "$HOME/.rbenv/bin/rbenv" ]; then
    eval "$("$HOME/.rbenv/bin/rbenv" init - --no-rehash bash)"
elif command -v rbenv >/dev/null 2>&1; then
    eval "$(rbenv init - --no-rehash bash)"
fi
```

If Bash uses `~/.bash_profile` on another machine, put the block there or have
that file source `~/.profile`. Open a new login shell, then clone the repository,
install its exact Ruby, and install the managed skills:

```sh
git clone git@github.com:jlmelville/codex-workflows.git
cd codex-workflows
rbenv install -s "$(cat .ruby-version)"
./scripts/check-ruby-runtime.sh
./install.sh
```

The repository requires the exact CRuby version in `.ruby-version`; rbenv is
the supported user setup. Installed Ruby helpers pin that version through their
shebang even when they run from another repository with a different
`.ruby-version`, and reject any explicitly forced incompatible interpreter
before doing work. Bundler is needed only for repository development and
validation, not for running installed helpers.

The checkout itself supplies the repository-local skills; the installer keeps
them out of the user-wide skill directory and validates their links.

1. Choose an external state directory and initialize it:

   ```sh
   export CODEX_WORKFLOWS_STATE_DIR=/absolute/path/to/codex-workflows-state
   ./skills/skill-retro/scripts/retro-state.rb init
   ```

   Keep it outside Git worktrees and Codex runtime directories. A reasonable
   local-only default is `$HOME/.local/share/codex-workflows`.

2. Make that location available and writable in every Codex session. Merge the
   following into `~/.codex/config.toml`, using the same absolute path:

   ```toml
   sandbox_mode = "workspace-write"
   approval_policy = "on-request"

   [sandbox_workspace_write]
   writable_roots = ["/absolute/path/to/codex-workflows-state"]

   [shell_environment_policy]
   experimental_use_profile = true
   set = { CODEX_WORKFLOWS_STATE_DIR = "/absolute/path/to/codex-workflows-state" }
   ```

   `workspace-write` permits normal repository edits, `writable_roots`
   additionally permits the external learning-state writes used by these
   workflows, and `on-request` keeps out-of-sandbox actions gated by approval.
   `experimental_use_profile` tells Codex to load the user shell profile when
   it constructs command environments, so the rbenv shims reach sandboxed
   commands without a machine-specific static `PATH`. The option is documented
   in the current
   [Codex configuration reference](https://developers.openai.com/codex/config-reference/),
   despite retaining its experimental name.

   Merge these keys into existing tables rather than defining a TOML table
   twice.

3. Confirm standing learning capture. The installer maintains the canonical
   global instruction block from
   [`skills/skill-retro/assets/global-agents-learning.md`](skills/skill-retro/assets/global-agents-learning.md)
   in `${CODEX_HOME:-$HOME/.codex}/AGENTS.override.md` when that file exists,
   otherwise in `AGENTS.md`. It authorizes papercut capture and high-confidence
   candidate or verification-proposal routing. Existing unrelated instructions
   are preserved. `./install.sh --check` fails when the managed block is absent,
   stale, malformed, or left in the inactive global file. See
   [Repository Maintenance](docs/repository-maintenance.md#user-global-instruction-setup)
   for ownership and precedence details.

4. Restart Codex or open a new thread, then have that new session verify the
   setup. An already-running session can retain the `PATH` it captured before
   the profile policy changed.

   ```sh
   command -v ruby
   ruby --version
   codex --strict-config --version
   ./scripts/check-ruby-runtime.sh
   ./skills/skill-retro/scripts/retro-state.rb validate
   ./install.sh --check
   ```

   `command -v ruby` should resolve to the rbenv shim. Inside this checkout, the
   two Ruby checks should report the exact version in `.ruby-version`.

After pulling skill changes, run `./install.sh` again. See
[Repository Maintenance](docs/repository-maintenance.md) for installation
details, validation, CI, and local tooling.

## Learning And Introspection

`$skill-retro-triage` and `$learning-process-review` are repository-local: run
Codex from this checkout when invoking them. The producer skills remain
user-scoped so they can collect evidence from other repositories.
Automatically routed Skill Candidate Reports and Verification Evidence
Proposals go directly to `$skill-retro-triage`; `$learning-process-review` is a
periodic audit and is not a prerequisite for triage.

| Moment | Entry point | Scope |
| --- | --- | --- |
| During substantive project work | `$papercut-capture` | Preserve small, sanitized friction observations. |
| At a meaningful task boundary | `$skill-retro` | Evaluate session evidence and automatically route only high-confidence candidates or exact verification proposals. |
| When intake accumulates | `$skill-retro-triage` | Judge candidates and verification proposals, then implement the accepted batch. |
| At the process-review cadence below | `$learning-process-review` | Audit external learning state; when the artifact audit is due, also run and supervise the repository prompt below. |
| When the artifact audit is due (direct/manual entry) | `prompts/skill-repository-retrospective.md` | Run the same report-only public-skill audit directly, without the broader learning-process review. |

The final two rows describe different review scopes, not two artifact-audit
prompts. `$learning-process-review` always reviews the external learning
mechanism. When `artifact-audit-status` is due, that skill also runs the one
repository prompt named in the final row and supervises its follow-up. Invoking
the prompt directly is the manual entry point for that same artifact audit; it
skips the broader learning-process review.

The repository prompt examines the public skill corpus itself. Its audit is
report-only unless the invoking task separately authorizes source changes.

Run the first process review after 10 papercuts or 14 calendar days after
enabling capture. Thereafter use the next trigger recorded by the previous
review; absent one, the default is five new papercuts or 14 calendar days after
the last review.

The external helper marks this artifact audit due after ten candidate reports
have been processed since the last successfully recorded artifact audit:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" artifact-audit-status
```

To invoke that same artifact audit directly, run the prompt from the repository
root:

> Use `prompts/skill-repository-retrospective.md` to audit this repository and
> report findings before making changes.

After the user approves the external-state update, `learning-process-review`
records a successfully completed audit and resets the cadence.

## State And Maintenance

The installed helper is available from any project repository:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" papercuts
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" pending
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" pending-verifications
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" validate
```

If `CODEX_WORKFLOWS_STATE_DIR` is unavailable, `$skill-retro` routing prints a
paste-ready candidate or verification proposal instead of writing it.

The complete record lifecycle is documented in the
[External Retrospective State Protocol](skills/skill-retro/references/state-protocol.md).

For accepted repository changes, run:

```sh
./scripts/validate-skills.sh
./install.sh              # update user scope and validate repo-local links
./install.sh --check
```

Use `./scripts/audit-skill-drift.rb` for drift and payload-budget checks. See
[Repository Maintenance](docs/repository-maintenance.md) for the full
validation and publication workflow.

## License

This repository is licensed under the [MIT License](LICENSE).
