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

## Warning Ownership

When a chunk accepts a remaining warning, note, or validation anomaly, assign
ownership before moving on. Either fix it in the chunk, classify it as
environmental or non-actionable with exact evidence, or add a named pending
follow-up chunk. Do not leave "known warning" language without an owner and
next action.
