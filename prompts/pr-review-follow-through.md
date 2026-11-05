# PR review follow-through trial

Run this task now for the supplied PR URL. Follow one newly arriving review round for up to two
hours from launch. Use a PR with a narrow accepted scope and feedback reasonably expected during
that window. Test whether feedback receives a justified disposition without an owner reminder.

## Scope and authority

Resolve the GitHub host, repository, PR number, expected account, and accepted PR scope from the
invocation and established approved context. Ask only about missing choices. Reuse approved account
settings when available; keep this run limited to the selected PR.

Invoking this prompt authorizes justified fixes within the PR's accepted scope, relevant tests,
commits, ordinary pushes to its branch, justified CI reruns, and concise replies in the relevant PR
discussion or review threads. Do not merge, force-push, delete branches, bypass reviews or checks,
or change unrelated work. A review request does not authorize expanding the accepted scope; report
decisions requiring owner input while continuing independent in-scope work.

Read applicable repository instructions and the accepted PR plan or objective. Apply the skills
needed for the actual changes and validation.

## Shared procedures

Reuse these sections of the [R CI maintenance prompt](weekly-r-ci-updates.md):

- [GitHub access checks](weekly-r-ci-updates.md#verify-github-cli-access), using this PR's host and
  expected account;
- [checkout preservation](weekly-r-ci-updates.md#preserve-local-work), limiting inspection to any
  supplied checkout and making PR edits in a disposable clone; and
- [continuation across waits](weekly-r-ci-updates.md#continue-across-ci-waits), for pending review
  feedback as well as CI.

These are procedure references. This prompt supplies the scope, action authority, and completion
boundary; do not run maintenance batch discovery or inherit its merge authority. Fetch the selected
PR head into the disposable clone for edits. The final validation target is the resulting PR head.

## Observe and handle one round

Record the launch time, two-hour deadline, head/base commit identities, and existing review
submissions, inline threads, and PR comments as the baseline. Paginate listings so omitted feedback
is not mistaken for an empty result. Preserve links or IDs needed to distinguish new feedback from
the baseline and the agent's own replies.

Check every ten minutes while waiting, keeping unchanged state quiet. The first poll containing new
review feedback defines the trial's round. Record the selected feedback IDs and assess each request
against the current source and accepted scope. Handle necessary follow-ups on those threads while
completing the round; report further review rounds as remaining work.

Make the smallest justified correction for valid, in-scope requests. Run relevant local checks,
then publish ordinary commits to the selected PR branch and observe required hosted checks for the
exact resulting head. Follow the shared state-refresh and revalidation rules when the head or base
moves. Attribute unrelated failures rather than silently repairing them or claiming a pass.

Reply with the correction's commit and actual validation, an evidence-based explanation for a
mistaken or obsolete finding, or the decision still needed. Re-read the relevant discussion before
posting and record the reply link so a resumption does not duplicate it.

## Continue and close

Keep one private continuation note outside Git with the resolved scope and authority, launch time
and deadline, baseline and selected feedback IDs, dispositions and posted replies, head/base and CI
identities, completed validation, next action, and temporary resources. Reuse this note for the
trial result. Preserve any retry bounds across resumptions.

Follow active runtime policy through the shared continuation procedure. When scheduled checks for
a specific job are disallowed, keep checking in the active chat. Use this trial's original launch
deadline for both review and CI waits. On resumption, refresh the recorded PR and discussion state
before acting. An interruption without confirmed resumption leaves follow-through unverified.

Stop after the selected round and resulting validation, PR closure or merge by another actor, the
deadline, or when only blockers requiring owner input remain. Complete the shared preservation and
cleanup checks, including retiring any permitted temporary heartbeat. Leave unmet obligations
explicit; closing this trial does not establish reviewer approval or merge readiness.

## Report the trial

Give a compact account of feedback links, dispositions, fix commits, validation for the final head,
remaining requests or blockers, and checkout preservation and cleanup. Include observed detection
and disposition delays, retries, the continuation method and actual resumptions, and owner
reminders or troubleshooting. Distinguish necessary owner decisions from reminders to continue.

Report success only when new feedback received a justified disposition and any correction passed
relevant validation without an owner reminder. No new feedback makes the trial inconclusive. One
successful trial establishes feasibility for that case; repeated reliability, comparative attention
savings, and any unexercised resumption mechanism remain unverified.
