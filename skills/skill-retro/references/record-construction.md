# Observation Record Construction

Use after an observation qualifies under `SKILL.md`. Before writing, read the state protocol's
[Installed Helper](state-protocol.md#installed-helper) and
[Observation Intake](state-protocol.md#observation-intake) for authority, privacy and recovery.

Generate the current shape with the installed helper:

```sh
"${HOME}/.agents/skills/skill-retro/scripts/retro-state.rb" template observation
```

Complete the title, sanitized source scope, observation, bounded evidence and redaction review.
Use the Markdown body for context already known: guidance in use, impact, workaround, observed
outcome, user feedback or a clearly labeled explanation. The record must stand alone for a reviewer
who lacks the producing conversation. Omit unavailable details instead of inventing them.

For an instruction-related detour, preserve the clause or sanitized source reference, authorized
work, observed action and consequence. Distinguish the instruction from the agent's interpretation.
For an already-landed improvement, retain the prior gap, owner direction, exact public commit and
actual validation when available. Landing does not establish later benefit.

Submit completed input with `record-observation --file PATH`, or `--file -` for standard input.
Use a temporary input file outside Git and remove it when practical. When the state root is unset
or an authorized write is blocked, preserve and disclose the validated paste-ready fallback.
Neither a helper nor a fallback expands capture authority.

No producer-side remedy or confidence taxonomy is required. Preserve one original observation;
`$skill-retro-triage` adds review decisions and applies the separate evidence rules for shared
changes and verification. In chat, state the observation, why it matters and the evidence needed
for the current conversation; do not reproduce an empty form.
