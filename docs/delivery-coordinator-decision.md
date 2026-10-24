# Delivery coordinator decision

Accepted by James on 2026-10-23. Revisit under the conditions below or when James changes direction.

## Decision

Keep delivery coordination in existing task prompts, skills, private continuation records, and
temporary heartbeats. A separate delivery coordinator is not justified by the evidence available.
Treat coordination as responsibilities that each workflow must own through its accepted completion
boundary: preserve state and authority, resume work, validate the result, report, and clean up.

The [weekly R CI prompt](../prompts/weekly-r-ci-updates.md#continue-across-ci-waits) is the current
concrete implementation. The prompt owns the batch, the continuation record preserves evidence and
next actions, the heartbeat starts another turn, and the maintenance skills govern validation and
authorized GitHub actions.

## Evidence and limits

A bounded one-PR R CI trial crossed a turn boundary, resumed through one scheduled heartbeat,
verified successful final CI, and removed its temporary heartbeat. No owner intervention was
observed after launch. This establishes that the mechanism worked for that case.

The trial did not measure comparative attention savings or establish reliable failure recovery,
repeated weekly operation, or coordination among independent workers. Use ordinary runs and their
existing reports to assess those questions; this decision creates no additional monitoring cadence.

## Conditions for revisiting

Before designing a separate coordinator, identify evidence from real runs that existing workflows
leave a specific responsibility unmet. Examples include missed resumptions, duplicate actions,
repeated state reconstruction, incomplete cleanup, or work the owner repeatedly has to rescue.
Record the affected responsibility, its cost, and why a smaller change to the current workflow
would be insufficient. Another article or a hypothetical future workload is not sufficient evidence.

If several prompts repeatedly need the same state or lifecycle mechanics, consider a shared helper
first. Consider a broader coordinator when real tasks require decisions across tasks, such as
dependency ordering or competing changes, that individual workflows cannot reliably own. Any
proposal should name its consumer, the missing responsibility, and an observable acceptance result.
