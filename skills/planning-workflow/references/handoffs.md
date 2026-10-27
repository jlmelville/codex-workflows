# Handoffs

Use this with `$planning-workflow` when a fresh agent needs enough context to
continue without chat history.

Put handoffs in chat by default. Write a file only when the user asks or the
repo already uses one. The active plan owns durable state; the handoff points
to it. Do not repeat inherited global policy. Verify every `Read first` path in
the recipient's context and name an inline replacement explicitly.

When the accepted task includes resuming after an asynchronous wait, record the condition for
continuation, who or what observes it, and the next action. Verify the mechanism that starts another
turn before promising to return; report unavailable scheduling as unverified follow-through.
Preserve scope, authority, retry limits, and deadlines across the wait. Refresh decision-relevant
state before acting, and close temporary watchers and resources when the work completes or stops.
A handoff the user will explicitly start needs no automatic wake-up mechanism. For a
source-repository example, see the [R CI continuation procedure](https://github.com/jlmelville/codex-workflows/blob/main/prompts/weekly-r-ci-updates.md#continue-across-ci-waits).

## Workspace lifetime and recovery

For a continuing role, keep the chat's saved workspace in a stable checkout whose lifetime matches
the role. Isolate delivery work in separate checkouts and pass their working directories explicitly
to commands. Check whether a workspace tool also moves the calling chat; creating a disposable
delivery checkout must not silently change the role's home. In Codex, ordinary Git worktrees outside
the managed worktree root can keep delivery ownership independent of chat archival. Record their
cleanup owner and retention condition in the existing plan. Check required local setup explicitly;
ordinary Git worktrees do not inherit the app's managed-worktree file-copy behavior.

Before takeover or workspace recovery, reconcile these distinct resources:

- the chat's actual saved working directory, from app metadata;
- the execution checkout, branch/commit and Git worktree linkage;
- the canonical records/evidence location; and
- attached worktrees, their lifecycle owner and any running jobs.

Confirm required paths exist with the expected types, including configuration directories and
files along the lookup path. A command's explicit working directory cannot repair a failure that
occurs before tools run. Verify recovery with a small fresh turn in the affected or successor chat,
then read back its saved directory. A shell probe or successful new configuration-loader process
alone does not establish that an existing chat can resume.

A failed chat can leave a build or measurement running. Inspect the recorded job/session, source,
log and exit status before restarting it. Reuse completed evidence when its source and environment
still match; record the exact next unfinished action in the existing brief. If the initialization
failure persists, choose one observation that distinguishes plausible causes, change one condition
with a backup and rollback, and retry once. If the baseline now works, leave configuration intact
and record the cause as unresolved. Use a supported handoff or authorized successor when necessary;
do not repair chat state by editing runtime databases.

Before retiring a chat, inventory its attached resources and decide what must survive: committed
source, uncommitted changes, ignored evidence, or an actual checkout at a usable path. These are
different retention promises. Copy required files outside the retiring resource's cleanup scope
and verify their contents and Git linkage before proceeding. A recovery snapshot is sufficient
only when it covers the promised material; do not assume it includes ignored files. In Codex,
archiving a chat can remove its managed worktrees, so label/quiesce the predecessor and defer
archival if a required checkout or job still depends on it. After any archival, verify the selected
retention targets and successor workspace before reporting preservation complete. See the
[official worktree lifecycle](https://learn.chatgpt.com/docs/environments/git-worktrees).

## Continuation prompt

Keep owner intent and agent inference visibly separate:

```text
Fresh-agent handoff prompt

Repository and goal:
Phase status:
Saved chat workspace / execution checkout / canonical records:
Resource ownership and retention (when relevant):

Read first:
- <active plan or repo instruction>

Owner ask:
- <actual objective and constraints>

Inherited demonstrated facts:
- <working capability or validated result, with evidence>

Owner-accepted decisions:
- <decision explicitly accepted by the owner>

Agent-proposed decisions:
- <proposal still open to challenge>

Explicit non-goals:
- <work outside this task>

Validation:
- Ran `<command>`: <result, relevant revision/environment, requirement supported>
- Still unverified: <consequential requirement or evidence boundary, if any>

Open issues and next action:
- <uncertainty, exact next step, and guardrail>
```

Preserve the origin and scope of agent-added restrictions when copying them;
describe authority not established for the successor as unresolved rather than
as an owner prohibition. Prefer exact paths, symbols, commands, statuses, and
bounded errors over narrative.

Point to consequential rejected approaches and their conditions in the active
plan so the successor can avoid repeating a ruled-out investigation without
treating a temporary limitation as permanent. If no plan exists, include that
information here. Keep historical observations distinct from preconditions the
successor must recheck before acting.
