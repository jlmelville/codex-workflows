# Codex Workflows

Personal Codex skills shared across machines, with an external learning loop
that lets agents improve those skills from experience. The aim is to keep the
human loop small without turning the public repository into an archive of
incidents.

## System Model

The system has three parts:

- **Source:** this Git repository contains the durable skills, prompts, and
  tooling shared between laptops.
- **Runtime:** `./install.sh` copies repository-owned skills into
  `$HOME/.agents/skills`, the current user-wide skill location documented by
  [OpenAI](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills).
  The installer tracks its own skills and leaves unrelated installed skills
  alone.
- **Learning state:** `CODEX_WORKFLOWS_STATE_DIR` holds papercuts, candidate
  reports, triage outcomes, and other working state outside the source
  repository and Codex home.

The runtime and learning state are replaceable. Git remains the source of truth
for reusable behavior.

```text
project work -> papercuts and retros -> triage -> skill changes -> Git
                                                               |
                                                pull and install on each laptop
```

## Set Up A Laptop

Clone the repository and install its managed skills:

```sh
git clone git@github.com:jlmelville/codex-workflows.git
cd codex-workflows
./install.sh
```

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
   set = { CODEX_WORKFLOWS_STATE_DIR = "/absolute/path/to/codex-workflows-state" }
   ```

   Merge these keys into existing tables rather than defining a TOML table
   twice.

3. Enable standing papercut capture. The canonical global instruction block is
   [`skills/papercut-capture/assets/global-agents-papercuts.md`](skills/papercut-capture/assets/global-agents-papercuts.md)
   and is included in the installed skill.

   If the Codex home has neither `AGENTS.md` nor `AGENTS.override.md`, install
   the block as `AGENTS.md`:

   ```sh
   codex_profile="${CODEX_HOME:-$HOME/.codex}"
   mkdir -p "${codex_profile}"
   cp "${HOME}/.agents/skills/papercut-capture/assets/global-agents-papercuts.md" \
     "${codex_profile}/AGENTS.md"
   ```

   Otherwise, merge its `## Workflow papercuts` section into the active global
   instruction file. See
   [Repository Maintenance](docs/repository-maintenance.md#user-global-instruction-setup)
   for precedence and update details.

4. Restart Codex or open a new thread, then verify the setup:

   ```sh
   ./skills/skill-retro/scripts/retro-state.rb validate
   ./install.sh --check
   ```

After pulling skill changes, run `./install.sh` again. See
[Repository Maintenance](docs/repository-maintenance.md) for installation
details, validation, CI, and local tooling.

## Learning And Introspection

| Moment | Entry point | Scope |
| --- | --- | --- |
| During substantive project work | `$papercut-capture` | Preserve small, sanitized friction observations. |
| After a meaningful session | `$skill-retro` | Distill session evidence into a candidate; write externally only when routing is authorized. |
| When candidates accumulate | `$skill-retro-triage` | Decide whether and how each candidate changes public source, then implement an accepted batch. |
| At the process-review cadence below | `$learning-process-review` | Audit external intake, decisions, verification, open follow-up work, and feedback-loop health. |
| When the artifact audit is due | [repository retrospective prompt](prompts/skill-repository-retrospective.md) | Audit public skills and references for overlap, drift, and semantic compression. |

The final two reviews are deliberately separate: `learning-process-review`
supervises the external learning mechanism, while the repository retrospective
examines the public corpus itself. The artifact audit is report-only unless the
invoking task separately authorizes source changes.

Run the first process review after 10 papercuts or 14 calendar days after
enabling capture. Thereafter use the next trigger recorded by the previous
review; absent one, the default is five new papercuts or 14 calendar days after
the last review.

The external helper marks this artifact audit due after ten candidate reports
have been processed since the last successfully recorded artifact audit:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" artifact-audit-status
```

Run the prompt from the repository root:

> Use `prompts/skill-repository-retrospective.md` to audit this repository and
> report findings before making changes.

After the user approves the external-state update, `learning-process-review`
records a successfully completed audit and resets the cadence.

## State And Maintenance

The installed helper is available from any project repository:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" papercuts
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" pending
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" validate
```

If `CODEX_WORKFLOWS_STATE_DIR` is unavailable, `$skill-retro` routing prints a
paste-ready candidate instead of writing it.

The complete record lifecycle is documented in the
[External Retrospective State Protocol](skills/skill-retro/references/state-protocol.md).

For accepted repository changes, run:

```sh
./scripts/validate-skills.sh
./install.sh              # when skills/ changed
./install.sh --check
```

Use `./scripts/audit-skill-drift.rb` for advisory drift checks. See
[Repository Maintenance](docs/repository-maintenance.md) for the full
validation and publication workflow.

## License

This repository is licensed under the [MIT License](LICENSE).
