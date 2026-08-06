# Codex Workflows

These are the last human words you are going to read on this repo. I am
experimenting with Codex skills and this is the repo for them. Apart from that,
I am just going to let Codex do its thing.

Personal Codex skills shared across machines, and an experiment in agents
improving those skills from their own experience.

The aim is to keep the human loop small: agents preserve useful observations
while they work, turn mature lessons into skill candidates, and periodically
apply the worthwhile candidates back to this repository.

## System Model

The system has three parts:

- **Source:** this Git repository contains the durable skills, prompts, and
  tooling shared between laptops.
- **Runtime:** `./install.sh` copies repository-owned skills into
  `${CODEX_HOME:-$HOME/.codex}/skills`, where Codex discovers them. The
  installer tracks its skills in a manifest and leaves other installed skills
  alone.
- **Learning state:** `CODEX_WORKFLOWS_STATE_DIR` holds papercuts, candidate
  reports, triage outcomes, and other working state outside the source
  repository and Codex home. It can be synchronized separately between
  machines when the same queues should be available on both.

The runtime and learning state are replaceable. Git remains the source of truth
for reusable behavior.

```text
project work -> papercuts and retros -> triage -> skill changes -> Git
                                                               |
                                                pull and install on each laptop
```

## Set Up A Laptop

Run these commands from the repository root.

1. Install the managed skills:

   ```sh
   ./install.sh
   ```

2. Choose an external state directory and initialize it:

   ```sh
   export CODEX_WORKFLOWS_STATE_DIR=/absolute/path/to/codex-workflows-state
   ./skills/skill-retro/scripts/retro-state.rb init
   ```

   Keep the directory outside Git worktrees and outside
   `${CODEX_HOME:-$HOME/.codex}`.

3. Make that location available and writable in every Codex session. Merge the
   following into `~/.codex/config.toml`, using the same absolute path:

   ```toml
   sandbox_mode = "workspace-write"
   approval_policy = "on-request"

   [sandbox_workspace_write]
   writable_roots = ["/absolute/path/to/codex-workflows-state"]

   [shell_environment_policy]
   set = { CODEX_WORKFLOWS_STATE_DIR = "/absolute/path/to/codex-workflows-state" }
   ```

   Do not define the same TOML table twice. The top-level sandbox and approval
   settings are unnecessary when an active permissions profile already supplies
   them. Setting the environment variable only in a shell startup file may not
   reach Codex sessions launched from a desktop or IDE.

4. Enable standing papercut capture. The canonical global instruction block is
   [`skills/papercut-capture/assets/global-agents-papercuts.md`](skills/papercut-capture/assets/global-agents-papercuts.md)
   and is included in the installed skill.

   If the Codex home has neither `AGENTS.md` nor `AGENTS.override.md`, install
   the block as `AGENTS.md`:

   ```sh
   codex_profile="${CODEX_HOME:-$HOME/.codex}"
   mkdir -p "${codex_profile}"
   cp "${codex_profile}/skills/papercut-capture/assets/global-agents-papercuts.md" \
     "${codex_profile}/AGENTS.md"
   ```

   Otherwise, merge its `## Workflow papercuts` section into the active global
   instruction file. `AGENTS.override.md` takes precedence over `AGENTS.md` when
   both exist. Reconcile the copied section after later updates to the canonical
   asset.

5. Restart Codex or open a new thread, then verify the setup:

   ```sh
   ./skills/skill-retro/scripts/retro-state.rb validate
   ./install.sh --check
   ```

   During the initial papercut pilot, substantive-task responses should end with
   `Papercuts recorded: N`, including zero.

After pulling skill changes on either laptop, run `./install.sh` again. See
[Repository Maintenance](docs/repository-maintenance.md) for custom
`CODEX_HOME` installation, dry runs, validation details, CI, and local tooling.

## Working Rhythm

The learning cycle has four cadences.

### During project work: capture papercuts

The standing global instruction activates `$papercut-capture` during
substantive repository work. It records small, sanitized observations while
their evidence is fresh. Project or task instructions can opt out.

### After substantive work: run a skill retro

Invoke `$skill-retro` after a meaningful coding session, investigation, CI
debug, or cleanup. It turns the session into a mature Skill Candidate Report.
The default result stays in chat; `route` or explicitly enabled `auto` mode can
write it to the external inbox.

The stable prompt at [prompts/skill-retrospective.md](prompts/skill-retrospective.md)
is an alternative entry point.

### About daily: triage accumulated retros

In this repository, invoke `$skill-retro-triage`. It judges pending candidates
and proposes an implementation batch before changing source or external state.
Once accepted, it applies the reusable changes, validates and installs them,
and follows the repository's commit and push workflow.

### About weekly: inspect the learning system

Use the
[Learning Process Retrospective Prompt](prompts/learning-process-retrospective.md)
to examine intake quality, papercut yield, triage decisions, deferrals,
verification, and whether the feedback loop is improving. Paste this into Codex
from the repository root:

> Use `prompts/learning-process-retrospective.md` to review whether the
> codex-workflows learning process is working. Follow the prompt as written and
> report findings in chat before making any changes.

During the initial papercut pilot, run the first review after 10 recorded
papercuts or 14 days of substantive use, whichever comes first.

## Occasional Repository Audit

The learning-process retrospective evaluates the external feedback loop. A
separate
[Skill Repository Retrospective Prompt](prompts/skill-repository-retrospective.md)
audits the public artifacts themselves for bloat, overlap, drift, missing
mechanisms, and unclear skill boundaries.

Paste this into Codex from the repository root:

> Use `prompts/skill-repository-retrospective.md` to audit the current
> codex-workflows skill system. Follow the prompt as written and report findings
> in chat before making any changes.

## State And Maintenance

The installed helper is available from any project repository:

```sh
"${CODEX_HOME:-$HOME/.codex}/skills/skill-retro/scripts/retro-state.rb" papercuts
"${CODEX_HOME:-$HOME/.codex}/skills/skill-retro/scripts/retro-state.rb" pending
"${CODEX_HOME:-$HOME/.codex}/skills/skill-retro/scripts/retro-state.rb" validate
```

If `CODEX_WORKFLOWS_STATE_DIR` is unavailable, retrospective routing prints a
paste-ready candidate instead of writing it. Losing or pruning external state
does not invalidate the repository or installed skills.

The complete record lifecycle is documented in the
[External Retrospective State Protocol](skills/skill-retro/references/state-protocol.md).

For accepted repository changes, run:

```sh
./scripts/validate-skills.sh
./install.sh              # when skills/ changed
./install.sh --check
```

Use `./scripts/audit-skill-drift.rb` for an advisory review of trigger overlap,
bloat, duplicated guidance, and installed-path drift.

## License

This repository is licensed under the [MIT License](LICENSE).
