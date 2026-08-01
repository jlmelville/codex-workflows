---
name: repo-bootstrap
description: Bootstrap a local project into a clean Git and GitHub repo, including file selection, .gitignore, README, validation, first commit, remote setup, branch naming, first push, and minimal CI. Use when Codex creates, initializes, publishes, or prepares a new repo from local files.
---

# Repo Bootstrap

Use this when turning local work into a repository that can be safely pushed to
GitHub.

## Authority

- For `prepare`, edit local project files and validate them. Do not initialize
  Git or create a commit unless the user asks.
- For `initialize` or `create a repository`, include local Git initialization,
  branch setup, and an initial local commit. Do not configure a remote or push.
- For `publish`, or an explicit request to create or configure a GitHub remote,
  include remote setup and the first push.

## First Pass

1. Inspect the directory tree and current git state.
2. Identify source files, generated files, runtime state, secrets, caches, and
   local-only configuration.
3. Create or update `.gitignore` before staging anything.
4. Before publishing, confirm whether the user wants the whole directory
   published or only a clean subset.

## Minimum Repository Shape

Create only the files the project needs:

- `README.md` with purpose, install/use notes, validation, and maintenance
  workflow.
- `.gitignore` covering editor files, caches, secrets, runtime state, and build
  outputs.
- CI workflow when there is a meaningful validation command.
- Dependency update configuration when the repository uses managed dependencies
  or GitHub Actions.

Avoid adding license, contribution, release, or packaging files unless requested
or clearly required by the project.

## Git Procedure

1. Initialize Git only when initialization is authorized and the directory is
   not already a repository.
2. When initializing, use `main` as the initial branch unless the user requests
   otherwise.
3. Stage explicit paths when there is any chance of unrelated or sensitive
   files.
4. Run relevant validation before the initial commit.
5. When initialization, creation, or publication is in scope, commit with a
   short message that describes the project state.
6. When publication is authorized, add `origin` after the user provides or
   creates the GitHub repository.
7. Push with upstream tracking as part of the authorized publication.

## GitHub Setup

For a new GitHub repository, recommend a concise description that states the
project's purpose and scope. Keep the remote URL explicit and verify it with:

```sh
git remote -v
git ls-remote origin HEAD
```

If GitHub CLI auth fails but SSH git works, continue with git operations and
report that `gh` still needs re-authentication for API tasks.

## CI Starter

Add CI only when it can run deterministic checks. Good first checks include:

- repository validation scripts,
- shell syntax and ShellCheck,
- language test suites,
- workflow audits for GitHub Actions.

For GitHub Actions, also apply `$github-actions-hardening`.

## Final Verification

Before finishing, report:

- repository path,
- branch and commit,
- validation commands run,
- remote URL and pushed state when publication was in scope,
- anything intentionally left uncommitted or unpushed.
