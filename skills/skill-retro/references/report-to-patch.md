# Skill Candidate Implementation

Use after a Skill Candidate Report has been accepted for `codex-workflows`.

For each candidate:

1. Re-read the cited existing skill, reference, prompt, or script before
   editing.
2. Classify the smallest destination:
   - `SKILL.md`: routing, trigger boundaries, must-remember rules, or short
     checklists.
   - `references/`: detailed edge cases, command recipes, workflows, or
     examples.
   - `scripts/`: deterministic checks or repeated fragile commands.
   - `prompts/`: reusable instructions for another agent or model.
   - `maintenance-ledger.md`: threshold-based observations not ready for a
     direct change.
3. Write one atomic edit per missing delta.
4. Add or update validation when the lesson is about command behavior, schema,
   file shape, generated output, or fragile search patterns.
5. Run `./scripts/validate-skills.sh`.
6. If files under `skills/` changed and installed runtime parity matters, run
   `./install.sh` and compare source to installed skills with:

```sh
diff -qr ./skills "${CODEX_HOME:-$HOME/.codex}/skills" -x .system
```

7. In the final response, cite the candidate source, files changed, validation
   run, install/sync status, and any deferred items.
