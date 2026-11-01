# Repository Instructions

This repository is the source of truth for personal Codex skills. User-scoped
runtime copies live under `$HOME/.agents/skills`; tracked links under
`.agents/skills` expose repository-only skills from their canonical `skills/`
sources.

The visible user-authored preamble in `README.md`, between the
`USER-AUTHORED PREAMBLE` HTML comments, is protected text. Preserve it verbatim
and do not move, rewrite, or remove it unless James explicitly requests a change
to that preamble.

Before source-changing maintenance, apply `$repo-update-preflight`, then use
`$codex-skill-repo`'s source-reconciliation overlay for incoming skill-repository
policy and machine-local state compatibility. Never hide or overwrite unrelated
work merely to make the checkout clean. After pulling retrospective helper or
protocol changes, validate this machine's local state with the newly pulled
source helper before judging or mutating records.

For accepted changes in this repo:

- Validate skill changes with `./scripts/validate-skills.sh`.
- Run `./install.sh` when files under `skills/` change. It syncs user-scoped
  skills and validates repository-local links, and may require sandbox approval
  because it writes outside the repo.
- Confirm both skill scopes match source with `./install.sh --check`. The check
  ignores unrelated user-scoped skills not owned by this repo.
- Commit the intended repo changes and push to `origin/main` unless the user
  says otherwise.
- Do not stage or commit unrelated local changes.

## Delivery coordination

Before proposing a separate delivery coordinator, read the
[accepted decision](docs/delivery-coordinator-decision.md). Keep coordination
in existing prompts, continuation records, and temporary heartbeats unless
evidence from real runs identifies an unmet responsibility.

## Chat titles

When a new chat's purpose becomes clear, the main agent delegates title drafting to a
`gpt-6.1-terra` subagent with `fork_turns="none"`. Supply only a compact brief: the chat's purpose,
distinguishing subject or question, current title, user naming constraints, and the naming guidance
below. Request one title without explanation; do not pass the full chat history. The main agent
applies the title with the available chat-title tool without asking for confirmation. Use this
drafting process when supplying a title for an authorized new chat.

Put the specific subject, question, or enduring role early. Use dates to distinguish repeated review
sessions. Preserve meaningful existing titles, explicit user choices, and established role names.
Rename again only when the title materially misrepresents the work.
