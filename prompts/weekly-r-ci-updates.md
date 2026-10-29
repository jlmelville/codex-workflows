# R CI dependency maintenance

Run this task now. Load saved settings from
`${XDG_CONFIG_HOME:-$HOME/.config}/codex-workflows/weekly-r-ci-updates.yaml`
when present, then apply overrides supplied by the invoking message or local
entry point. Overrides apply only to this run unless the user asks to save them.

Require `github_host`, `github_account`, `repository_owners`, `checkout_roots`,
and `mode` (`review` or `merge`). On first use, inspect available CLI account
metadata and user-supplied context, including any existing local entry point.
Suggest settings from that evidence and ask one concise question covering only
unresolved choices. Default to `review` when mode is unspecified. Repository
owners and merge authority must come from user instructions or saved settings;
do not infer them from the authenticated account. Confirm inferred owners and
any proposed merge mode before using them.

On first use, save the resolved settings as YAML at the path above, outside Git
worktrees, so later invocations need no setup. Save configuration only, never
credentials. If saving is blocked, report it and continue the authorized run
with the resolved settings. An existing local entry point can remain as a
shortcut to this shared prompt.

Optional `repositories` is a nonempty list of exact `owner/name` identities on
`github_host`; each owner must appear in `repository_owners`. Ask for correction
before discovery if the list is empty, malformed, or outside those owners.
Omitting this setting retains owner-wide discovery.

Find qualifying GitHub Actions dependency updates in R package repositories
within that scope. Review mode validates and reports without changing GitHub
state. Merge mode also performs the authorized updates and merges below. Leave
blocked items for follow-up and continue with independent repositories.

## Skills and authority

Apply `$dependabot-pr-maintenance`, including its pinned-actions, stale-CI, and
batch-merge guidance, plus `$github-actions-hardening` and `$r-ci-hardening`.
Use their current validation procedures and canonical audit scripts. Read
applicable repository instructions from existing checkouts and the fresh remote
default-branch tree before validation or edits.

In merge mode, this invocation authorizes merging qualifying PRs, justified CI
reruns, stale bot branch updates through GitHub's branch-update operation, and
small fixes directly needed for an update, such as correcting a pin's version
comment. Work through the batch without asking for confirmation on each PR.
Revalidate any changed PR head. Neither mode authorizes comments or reviews,
force-pushes, branch deletion, protection bypasses, or unrelated changes.

## Verify GitHub CLI access

Before discovery or maintenance changes, run
`gh auth status --hostname HOST` and
`gh api --hostname HOST user --jq .login`, substituting `github_host` for `HOST`.
Confirm the active account matches `github_account` and has the repository and
workflow access needed for the task (`repo` and `workflow` scopes for OAuth
tokens). Do not expose token values.

If a check fails inside the sandbox, retry with approved network and system
credential-store access before concluding that the credential is invalid. If
the account or required access still cannot be verified, stop and report the
concrete failure and needed `gh auth login` or `gh auth refresh` step. Verify
authentication again after any repair before continuing.

Prefer `gh` for discovery, PR and check inspection, logs, branch updates, CI
reruns, and merges guarded by the validated expected head SHA. Explicitly target
the configured host in GitHub operations. Use a connected GitHub app or direct
API call only when `gh` cannot perform a required operation; report the fallback
and its reason.

## Preserve local work

Before discovery, protect every Git inspection of an existing checkout,
including helper subprocesses, with this wrapper. Set `checkout` to the path
being inspected:

<!-- checkout-index-inspection:start -->
```sh
inspect_git() {
  GIT_OPTIONAL_LOCKS=0 git -c diff.autoRefreshIndex=false -C "$checkout" "$@"
}
```
<!-- checkout-index-inspection:end -->

Pass inspection arguments to this wrapper, for example
`inspect_git status --porcelain=v1 --untracked-files=all`. Use it for `diff`,
`remote`, `rev-parse`, and other inspections; apply both protections explicitly
in helper subprocesses that cannot call the shell function. Optional locks alone
do not prevent `git diff` from refreshing the index. Do not change repository
or global Git configuration to apply this fix. Repository validation executes
this marked wrapper through
[`scripts/test-checkout-index-preservation.py`](../scripts/test-checkout-index-preservation.py).

Use `${HOME}/.agents/skills/dependabot-pr-maintenance/scripts/checkout-state.py`
`snapshot CHECKOUT...` before further inspection, then `compare --file SNAPSHOT`
after the last inspection; see `--help`. Save its private JSON outside inspected
checkouts. An incomplete snapshot or comparison cannot establish preservation.
A metadata-only index change still fails preservation; report differences and
distinguish concurrent activity from this run's changes. Run commands that
require index writes only in a disposable clone.

Use disposable standalone clones under a newly created temporary directory for
validation and authorized PR edits, starting from the current remote
default-branch commit. Existing checkouts are discovery and instruction sources;
preserve their tracked and untracked files, index, stashes, local branches, and
commits. Do not pull, stash, reset, clean, switch branches, or fast-forward them.
A dirty, diverged, or outdated checkout is not a reason to skip a repository.
Perform the skill's fetch/refresh steps in the disposable clone. Remove only
temporary resources created by this run.

## Discover the batch

- Use `checkout-state.py discover ROOT...` from the installed helper above for
  filesystem candidates beneath `checkout_roots`; inspect rejected markers and
  report incomplete inventories. Resolve candidates' GitHub identities from
  remotes and deduplicate by host and `owner/name`.
  Maintain only repositories on `github_host` whose owners appear in
  `repository_owners` and, when supplied, whose identities appear in
  `repositories`.
- Include repositories without local checkouts. When `repositories` is
  supplied, query each listed repository directly instead of listing all
  repositories for its owner. Otherwise discover repositories for every
  configured owner on GitHub. Skip archived repositories. Confirm R package
  identity using the root `DESCRIPTION` on the current remote default branch;
  GitHub's primary-language label can miss packages with substantial C++ code.
- Paginate repository and open-PR listings. Serialize GitHub listing/search
  requests and follow the skill's rate-limit and network retry guidance. Record
  discovery failures instead of treating them as empty results.
- Eligible PRs are genuine Dependabot updates targeting the repository's
  current default branch and consisting solely of GitHub Actions dependency
  version/SHA changes in workflows or composite actions, with associated
  version comments. Exclude drafts, runtime/package dependency updates, source
  changes, and broad workflow redesigns. Major action updates can qualify after
  checking upstream release notes, migration requirements, and runner/runtime
  compatibility.

## Validate and merge

Follow the skills' candidate review and validation loop, including individual
and combined merge-result validation against the latest remote default branch.
Use hosted R package checks; add local package validation when repository
instructions or the particular change require it. Review mode reports the
existing check results and any evidence that would require a remote change.

In merge mode, follow the skills' stale-check recovery and sequential merge
loop, including expected-head protection and reassessment after each merge.
Repeat affected validation when a PR head or base moves. Keep fixes confined to
the CI update. Unrelated failures do not authorize ignoring required checks.

Process independent repositories while checks run, then revisit pending
candidates. Bound retries and report unresolved blockers. After the last merge
in each repository, verify workflows on the final default-branch commit as
required by the batch skill and report any post-merge failure explicitly.

## Continue across CI waits

When pending PR or post-merge CI needs another turn, create one temporary
heartbeat in this chat using the app's automation tool. Check every ten minutes
for up to two hours from the first wait. Reuse this batch's temporary heartbeat
if one already exists; leave the recurring weekly automation unchanged.

Before yielding, save a private continuation record outside Git and put its
absolute path in the heartbeat prompt. Record the resolved repository scope and
mode, pending PRs and validated head/base SHAs, merge commits, expected workflows
and run IDs, completed validation, next actions, retry counts and limits, deadline,
and paths to disposable clones and checkout snapshots. Save the temporary
automation ID and confirm it is active before claiming that work will resume.
If scheduling is unavailable, report that follow-through is unverified rather
than leaving an implicit promise to return.

Each scheduled turn reads the latest continuation record and checks the deadline
before further work. Re-read this prompt when its relevant content changed or is
unavailable in context. Resume only the recorded batch within its resolved scope
and mode. Refresh GitHub account, PR, head/base, and CI state before acting;
revalidate changed heads or bases. Preserve the existing retry limits and
deadline across turns. Continue independent recorded items while checks run,
then revisit pending items through the same final-commit validation boundary.
Keep the continuation record current; skip discovery of new work.

Keep unchanged pending checks quiet. When the batch completes, reaches its
deadline or retry limit, or has only blockers requiring user action, delete only
the recorded temporary heartbeat with the automation tool. Close the run record,
compare the original checkout snapshots, and remove disposable resources when
no longer needed. A later trigger for a closed run only retires its temporary
heartbeat. Report completion, meaningful failures, or required user action once;
do not leave a temporary heartbeat running after its work ends.

## Report

Summarize discovery coverage, including repositories with no eligible updates
and any gaps. When `repositories` is supplied, account for every listed
repository, including access failures and exclusions. Give a compact table of
PR links, dependency changes, outcome, validation results, and merge commit or
concrete blocker. In review mode,
identify candidates ready to merge without claiming they were merged.
Distinguish merged, blocked, pending, and out-of-scope items. Confirm local
checkouts were preserved and identify follow-up work. If a continuation was
needed, report actual scheduled resumptions, retries, temporary heartbeat
removal, and any observed user reminders, approvals, or troubleshooting.
