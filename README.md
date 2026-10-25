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
- **Learning state:** `CODEX_WORKFLOWS_STATE_DIR` holds observations, legacy candidate
  reports, triage outcomes, and other working state outside the source
  repository and Codex home.

The user runtime and learning state are replaceable. Git remains the source of
truth for reusable behavior and repository-local discovery links.

```text
project work -> observations -> review -> authorized improvements -> Git
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

## Steer With Principles

Use these names to redirect work when the cue fits. Follow the links for the
canonical guidance.

| Name | When to use it |
| --- | --- |
| [Test the shared premise](skills/skill-retro/assets/global-agents-learning.md#workflow-judgment) | Successive fixes share an assumption but stop making useful progress. |
| [Evidence at the claim's boundary](skills/skill-retro/references/value-stream.md) | A check may establish less than the reported outcome. |
| [Simplify without weakening the contract](skills/architecture-audit/SKILL.md#judge-simplifications) | A proposed simplification may discard required behavior. |

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
   otherwise in `AGENTS.md`. It authorizes sanitized observation capture;
   review and existing-state changes need their own authority. Existing unrelated instructions
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

## R CI Maintenance Example

[`prompts/weekly-r-ci-updates.md`](prompts/weekly-r-ci-updates.md) combines
`$dependabot-pr-maintenance`, `$github-actions-hardening`, and `$r-ci-hardening`
to maintain GitHub Actions dependencies across R package repositories. Use it
weekly or when a batch of Dependabot action updates has accumulated, with the
skills installed and `gh` available.

From this repository, send:

```text
Run prompts/weekly-r-ci-updates.md.
```

On first use, Codex walks you through the GitHub account, repository owners,
checkout roots, and mode, reusing any existing local entry-point settings you
provide. It saves your choices outside Git at
`~/.config/codex-workflows/weekly-r-ci-updates.yaml` (under `XDG_CONFIG_HOME`
when set). Later runs load that file automatically. You can ask Codex to update
the saved settings whenever your scope changes.

Review mode is the default and validates without changing GitHub state. Ask for
`mode: merge` to authorize the scoped updates, CI reruns, fixes, and merges
described in the prompt; you can save that choice for future runs. An optional
`repositories` list limits maintenance to exact `owner/name` identities,
including repositories without local checkouts. Omit it for owner-wide discovery.

When running outside this repository, reference the shared prompt by its
absolute path, or keep a local shortcut to it. Start the maintenance chat in
your checkout parent directory with access to the configured roots.

## Learning And Introspection

`$skill-retro-triage` and `$learning-process-review` are repository-local: run
Codex from this checkout when invoking them. The producer skills remain
user-scoped so they can collect evidence from other repositories.
Captured observations go directly to `$skill-retro-triage` for review.
`$learning-process-review` is a broader review route and is not a prerequisite.

The managed learning instructions ask agents to examine the journey while work
unfolds, using the user's objective and applicable guidance to notice concerns
beyond named failure signals. Observation capture preserves
qualifying evidence from that judgment without inventing a record
for every task. See [value-stream judgment](skills/skill-retro/references/value-stream.md).

| Moment | Entry point | Scope |
| --- | --- | --- |
| During substantive work or at a meaningful boundary | `$skill-retro` | Capture concrete observations once; no remedy or skill classification required. |
| When observations need review | `$skill-retro-triage` | Judge the evidence, choose remedies or verification, and complete authorized actions. |
| For a focused question or useful review reminder | `$learning-process-review` | Review the requested learning-state or public-skill scope and complete authorized follow-up. |
| For a requested or justified full public audit | `prompts/skill-repository-retrospective.md` | Inspect the public corpus without private learning state. |

`$learning-process-review` supports focused public-skill questions, private learning-state reviews,
and full audits. A due artifact reminder prompts a judgment about useful scope; it does not add
a full audit automatically. The repository prompt is the direct entry point for the same full
public audit. Its findings exclude private state, and source changes need invoking authority.

For a focused question about how the learning machinery affects ordinary work,
or to explore another machine's local evidence, use:

> Use `prompts/learning-process-investigation.md` to investigate the learning
> process using this machine's evidence. Report findings before making changes.

This prompt and `$learning-process-review` provide direct and supervised routes
to the same focused investigation. Use it for a concrete unresolved question or
within an existing process review when deeper downstream tracing would help;
it adds no cadence and does not complete the broader review or public artifact
audit. The broader skill retains responsibility for authorized drains and
review follow-up.

Use 10 observations or 14 days after enabling capture as the first process-review reminder.
Thereafter use the previously agreed trigger; absent one, the default is five new observations or
14 days after the last review. Judge useful scope when reminded; this does not schedule a task
or require a full audit.

Material loop changes with uncertain benefit can use
[bounded experiments](skills/learning-process-review/references/loop-experiments.md)
in existing ledgers. Process review judges their benefit and operating cost alongside undrained
observations. `$papercut-capture` remains a compatibility entry point to the unified capture skill.

The external helper marks this artifact audit due at approximately ten retained observations or
legacy candidates first reviewed after the last completed repository audit. Reconsiderations do not
count again; archive cleanup or backdated review times can reduce the estimate:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" artifact-audit-status
```

To invoke that same artifact audit directly, run the prompt from the repository
root:

> Use `prompts/skill-repository-retrospective.md` to audit this repository and
> report findings before making changes.

When state recording is authorized, `learning-process-review` records a successfully completed
audit, supplying the next reminder cutoff.

## State And Maintenance

The installed helper is available from any project repository:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" template observation
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" review-queue
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" validate
```

If `CODEX_WORKFLOWS_STATE_DIR` is unavailable, `$skill-retro` routing prints a
paste-ready observation instead of writing it.

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
