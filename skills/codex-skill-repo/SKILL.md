---
name: codex-skill-repo
description: Maintain a Codex skill repository as source of truth. Use when Codex edits, reviews, installs, validates, documents, commits, or publishes skills, including layout, metadata, runtime install sync, validation scripts, and avoiding runtime-state commits.
---

# Codex Skill Repo

Use this for repositories that version Codex skills separately from the active
Codex runtime directory.

## Authority

- For review or audit requests, inspect and report without editing, installing,
  committing, or pushing.
- For change requests, make in-scope source edits and run non-destructive
  validation.
- Install outside the worktree, commit, or push only when the user request or
  explicit repository instructions authorize that action.

## Source Of Truth

- Treat the version-controlled source repository, not the installed runtime
  copy, as source of truth.
- Treat `${HOME}/.agents/skills` as user-scoped installed output. A repository
  may instead expose repository-only skills through tracked `.agents/skills`
  directories or symlinks. Make authorized changes in canonical source, use the
  repository installer when in scope, and confirm both scopes with
  `./install.sh --check`; ignore unrelated installed skills.
- Do not hand-edit installed copies unless diagnosing a sync problem; port useful
  changes back to the source repo immediately.
- When moving a skill from user scope to repository scope, remove the old
  user-scoped copy only when the prior managed manifest proves this repository
  owns it. Preserve and report an unowned collision instead of overwriting or
  deleting it.
- Before source-changing work in a checkout shared across machines, apply
  `$repo-update-preflight`. After it completes, re-read instructions and relevant
  skills because their structure or policy may have changed. Then use
  [source-reconciliation.md](references/source-reconciliation.md) for the skill
  repository's incoming-policy review and machine-local state compatibility
  gate.

## Consistency Surfaces

Check this repo across four surfaces:

1. Source validity: frontmatter, metadata, links, scripts, smoke tests, mirrored
   files, and workflow hardening.
2. Runtime validity: executable commands in user-scoped skills should use
   `${HOME}/.agents/skills/...` unless explicitly marked as source-repository
   commands; repository-local discovery paths must resolve to canonical source.
3. Cross-platform validity: shell, Ruby, Python, and R behavior should account
   for Linux and macOS when scripts become substantial.
4. Drift validity: duplicated helpers, repeated command prose, overlapping
   triggers, machine-local paths, and large always-read skills need triage
   rather than automatic churn.

## Repository Shape

Keep the top level and each skill limited to owned runtime or maintainer assets:

```text
skills/
scripts/
install.sh
README.md
.github/
skills/<skill-name>/
  SKILL.md, agents/openai.yaml, optional references/, scripts/, assets/
.agents/skills/<repo-only-skill> -> ../../skills/<repo-only-skill>
```

Only create `references/`, `scripts/`, or `assets/` when the skill needs them.
Put human-facing repo documentation in the repository README, not inside skill
folders.

Before broadly rewriting documentation, identify explicitly protected or
user-authored blocks and preserve them verbatim. When a visible passage must
remain human-owned inside an otherwise agent-maintained file, make its boundary
clear with source comments when appropriate and keep the durable veto in a
concise repository-local instruction.

When repository documentation recommends Codex sandbox, approval, or other
runtime controls, explain each non-obvious setting through its user-visible
consequence. Distinguish controls that grant technical access from controls
that decide when Codex must ask, and verify current product semantics against
official documentation.

## Do Not Commit

Never copy or commit raw Codex runtime state:

- `auth.json`
- sessions, history, attachments, logs, sqlite state
- caches and installed plugin caches
- temporary files from validation or experiments
- machine-specific secrets or credentials
- papercut inbox or archive, retrospective inbox, accepted records, drafts,
  ledgers, system audit records, or cadence state from
  `CODEX_WORKFLOWS_STATE_DIR`

Review `.gitignore` before staging whenever the repo was created from a
runtime directory.

## Authoring Skills

Keep the smallest useful skill contract on the default path:

- intended outcome;
- context and evidence needed to decide and act;
- hard constraints and action authority;
- decision-changing procedure; and
- success condition and output.

This contract includes unconditional privacy, authority, evidence, and
completion rules as well as conditional decisions. Add detailed branches only
for real ambiguity or risk. Ordinary agent competence, source-incident
narration, and duplicated tool documentation do not belong on the default
path. Prescribe an exact sequence only when ordering prevents a known
correctness, safety, state, or tooling failure.

Classify learned additions before placing them: compact default judgment,
routed exact mechanics, optional sanitized cases, or external verification
only. A reference is a loading mechanism rather than a semantic category; it
may mix roles and need restructuring. Read
[semantic-authoring.md](references/semantic-authoring.md) when adding or
restructuring guidance, mechanics, examples, or casebooks.

Classify external tools by owner before prescribing installation or parity:
repository-maintainer tools run this source repository's checks; downstream
skill dependencies run only when an installed skill handles another project;
optional enhancements strengthen but do not define either workflow. Check
required availability before dependent work and name only supported fallbacks.
If a required tool cannot run and no fallback preserves the check, make the
validation gap prominent and do not claim complete validation. Route maintainer
acquisition and executable-resolution mechanics to
[repository-validation.md](references/repository-validation.md).

Create a new skill only for repeated work with clear triggers and decisions;
keep maintainer-only knowledge in repository docs. For recurring non-installed
prompts, document the exact path, a copy-ready invocation, and useful cadence.
When a supervising skill and a direct manual entry point use the same prompt,
say that they are two routes to one mechanism, show the literal path relative
to the repository root, and distinguish the skill's broader supervision or
follow-up from the direct prompt's scope.

When adding a skill, follow system `skill-creator` guidance and initialize with
`init_skill.py` when available. Keep trigger conditions in the frontmatter
description and add `agents/openai.yaml`. When passing `$skill-name` through
shell arguments, quote or escape `$`, then inspect the generated default prompt
for the literal invocation. Validate the skill and repository, install it, and
confirm managed parity when applicable.

## Promoting Local Guidance

When promoting repo-local skills, instructions, prompts, or plan material into
user-scoped skills, follow the classification, generalization, and
source-replacement workflow in
[semantic-authoring.md](references/semantic-authoring.md#promoting-local-guidance).

## Validation

Before committing, run:

```sh
./scripts/validate-skills.sh
./install.sh --check  # after installation
```

For workflow changes from this source repository root, also run when present:

```sh
./skills/github-actions-hardening/scripts/audit-actions.sh --quiet .github/workflows
```

Before validating substantial skill, script, CI, installer, shared-policy, or
drift changes, read
[repository-validation.md](references/repository-validation.md) for the quick
validator, temporary state, mirrors, advisory audits, and pre-commit review.

Repository-specific candidate consumers belong in that repository's local
skill scope. In the `codex-workflows` source checkout, use
`$skill-retro-triage` for accepted Skill Candidate Reports after re-reading
cited destination files.
