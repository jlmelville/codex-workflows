# Handoffs

Use this with `$planning-workflow` when a fresh agent needs enough context to
continue without chat history.

Put handoffs in chat by default. Write a file only when the user asks or the
repo already uses one. The active plan owns durable state; the handoff points
to it. Do not repeat inherited global policy. Verify every `Read first` path in
the recipient's context and name an inline replacement explicitly.

Keep owner intent and agent inference visibly separate:

```text
Fresh-agent handoff prompt

Repository and goal:
Phase status:

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
- Ran `<command>`: <result>

Open issues and next action:
- <uncertainty, exact next step, and guardrail>
```

Do not promote a prior agent's mechanism, adjective, or decision list into an
owner constraint. Prefer exact paths, symbols, commands, statuses, and bounded
errors over narrative.
