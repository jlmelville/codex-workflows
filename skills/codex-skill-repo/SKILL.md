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
- Before source-changing work in a checkout shared across machines, reconcile
  its upstream, worktree, stashes, divergence, and incoming changes. Re-read
  instructions and relevant skills after integration because their structure or
  policy may have changed. Use
  [source-reconciliation.md](references/source-reconciliation.md) for the exact
  preflight, recovery branches, and machine-local state compatibility gate.

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

When turning repo-local `.agents/skills`, `docs/agents`, `prompts/`,
`AGENTS.md`, or `PLANS.md` material into global skills:

1. Inventory the local guidance and classify it as generic, language-specific,
   repo-specific, stale duplicate, or ordinary engineering judgment.
2. Promote only reusable, non-obvious workflows that are likely to recur.
3. Generalize names, triggers, paths, and examples so the new skill does not
   leak one repo's domain model.
4. Leave domain-specific contracts local until the same pattern appears in
   another repo.
5. When promoting a stable prompt into a skill, replace the old prompt file with
   a short pointer if existing workflows may still link to that path.
6. Replace duplicated local rules with short references to the global skill when
   editing that repo is in scope.

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
