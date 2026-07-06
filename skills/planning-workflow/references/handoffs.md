# Handoffs

Use this with `$planning-workflow` when a fresh agent needs enough context to
continue without relying on chat history.

Put handoffs in the chat response by default. Write persistent handoff files
only when the user asks or the repo already uses them for active work. The
active plan should hold durable state; the handoff should point to it.

Use a fenced `text` block:

```text
Fresh-agent handoff prompt

We are working in <repo path> on <goal>. Phase/chunk <id> is <complete/in progress/blocked>.

Read first:
- <repo instructions or active plan>
- <supporting audit/review file, if needed>

Current state:
- <what changed or was learned>
- <important files touched or inspected>
- <key decisions, constraints, or user vetoes>

Validation:
- Ran `<command>`: <result>
- Ran `<command>`: <result or failure>

Open issues:
- <bug/failure/uncertainty>
- <thing not yet tested>

Next recommended steps:
1. <next task>
2. <next task>
3. <tests or smoke checks to run>

Guardrails:
- <do not revisit / do not broaden / preserve this behavior>
```

Keep handoffs concise. Prefer exact file paths, function names, commands,
statuses, and error messages over broad narrative.
