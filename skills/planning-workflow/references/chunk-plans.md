# Chunk Plans

Use this with `$planning-workflow` when broad cleanup, audit, or polish work
needs bounded packets instead of one monolithic instruction list.

## Minimum Shape

A chunk plan should include:

- goal and guardrails;
- source audit or review file, if any;
- explicit operational chunking rules;
- a chunk queue with scope, tasks, validation, and exit criteria;
- a progress log recording completed chunks, files changed, tests run,
  discoveries, decisions, and the recommended next chunk.

Each agent should complete one coherent chunk, run focused validation, update
the progress log, and stop with a handoff when more work remains. Do not
combine unrelated chunks just because context remains.

## Progress Log Edits

When a plan repeats marker text such as next-chunk recommendations, anchor a
patch on a unique heading and nearby dated entry or on an explicit end-of-log
context. After updating the log, inspect the dated-entry order and final
recommended chunk so an earlier matching marker cannot silently receive the
new entry.

## Plan Provenance Boundary

Keep execution chronology in the plan progress log, handoff, or review record.
Durable source comments and user-facing output must not depend on an ignored or
private plan, chunk identifier, or review status for meaning. A necessary
comment should stand alone and explain the lasting domain, API, compatibility,
numerical, or safety constraint—why the code behaves this way, not when the
decision was made. If moving the operation to its natural construction or
validation boundary makes the intent clear, prefer that structure and omit the
comment.

## Managed Sandbox Git Writes

If staging or committing fails under managed sandboxing with a read-only
`.git/index.lock` error, and `git -C <repo>` is an approved command form, retry
the git operation with `git -C <repo>` before considering permission changes or
lock-file cleanup.

## Behavior-Neutral File Splits

For behavior-neutral file splits, add a mechanical verification step before
tests when practical:

1. Snapshot the original source file.
2. Split it mechanically.
3. Rejoin the new files with the same separators the original used.
4. Run a unified diff against the snapshot.

Treat any non-separator diff as a source-content change that needs review
before proceeding. Treat blank lines at new file boundaries as reconstruction
separators, not content that must remain at the end of split files; strip
trailing blank lines from the new files and make the separator counts explicit
in the rejoin command.

## Bug-Scoped Staging

For cleanup chunks that may reveal several unrelated correctness bugs, decide
the likely commit boundaries before editing. Keep fixes and tests independently
stageable by bug whenever practical, instead of making one shared regression
file or broad hunk that later requires delicate partial staging.

## Staged Handoff Review

When a handoff presents a staged patch, treat the Git index as the deliverable.
Inspect `git diff --cached --name-status`, review `git diff --cached`, and run
`git diff --cached --check`. Before using working-tree tests as evidence for
the proposed commit, compare staged and unstaged path lists and confirm that no
unstaged edits overlap staged paths. Tests exercise working-tree files, so they
support the cached patch only when those paths have no unstaged drift.

## Overlapping Split Validation

When an operator-directed or post-hoc commit split leaves staged and unstaged
hunks in the same paths, materialize the exact Git index in an isolated
temporary checkout that excludes unstaged and untracked content. Run the
commit's focused and proportional validation against that snapshot; ordinary
working-tree tests are evidence only for the combined state.

Inspect both the intermediate cached patch and the final combined patch. Record
any compatibility edits needed only to keep an intermediate commit valid, and
confirm that the final state removes them or retains them for an independently
justified reason.

## Warning Ownership

When a chunk accepts a remaining warning, note, or validation anomaly, assign
ownership before moving on. Either fix it in the chunk, classify it as
environmental or non-actionable with exact evidence, or add a named pending
follow-up chunk. Do not leave "known warning" language without an owner and
next action.
