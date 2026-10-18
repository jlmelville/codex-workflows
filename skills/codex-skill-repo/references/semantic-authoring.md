# Semantic Skill Authoring

Use this when adding or restructuring skill-repository guidance, creating
skills or recurring prompts, promoting repo-local guidance, or deciding payload
capacity. Preserve the evidence and mechanics needed for correctness while
reducing duplicated incident-shaped decisions.

## Admission

State the changed action, authority, observation, or success condition. Check whether an existing
principle already produces it. Another incident adds evidence rather than a rule when the decision and
required observation are unchanged.

Consulting a skill does not require running its workflow. Run it only when the task requires its
outcome and authority permits it. If an earlier decision ends that work, skip the stages that depend
on it. Still complete any independently required finishing work.

Classify learned additions before placing them:

- **Default judgment:** a compact principle needed when the skill triggers. State the condition and
  action that distinguish the case; keep unconditional privacy, authority, evidence, and completion
  contracts here. Omit incident narration.
- **Routed mechanics:** exact commands, APIs, tool behavior, environment
  requirements, file formats, ordering, and fail-closed recipes. Prefer scripts
  for deterministic or quoting-sensitive behavior; do not turn mechanics vague.
  Keep commands, field vocabularies, and mechanically enforced constraints in
  discoverable helper help, templates, and refusal messages where practical.
  Remove duplicated prose only after those surfaces are usable; retain the
  judgment, invocation route, authority, privacy, and recovery decisions the
  helper cannot make.
- **Optional cases:** short analogies for a distinct plausible wrong implementation
  or observation boundary that judgment and mechanics do not resolve.
- **Verification only:** recurrence supporting or contradicting an existing decision and required
  observation. Keep it in external accepted state, not public skill content.

Split material when its parts serve different roles or need to be loaded under different conditions.
Minimize changes to the decisions the guidance supports, even when that requires editing more lines.
Preserve distinct conditions that require different actions.

Capacity metrics reveal review pressure; they do not prove that text is
dispensable. Do not pay for a justified addition by rewriting an unrelated
skill, flattening distinct advice into generic prose, or deleting evidence
needed to apply a rule. If a limit is crossed, review the affected addition and
its local destination first. Any offsetting reduction must independently
improve that same material or another explicitly reviewed target, not serve as
an invisible cross-skill subsidy.
When a necessary accepted addition crosses a baseline, prefer an explicit,
narrowly scoped capacity decision over hidden collateral compression.

## New Skill Creation

When adding a skill, follow system `skill-creator` guidance and initialize with
`init_skill.py` when available. Keep trigger conditions in the frontmatter
description and add `agents/openai.yaml`. When passing `$skill-name` through
shell arguments, quote or escape `$`, then inspect the generated default prompt
for the literal invocation. Validate the skill and repository, install it, and
confirm managed parity when applicable.

## Recurring Non-Installed Prompts

For recurring non-installed prompts, document the exact path, a copy-ready
invocation, and useful cadence. When a supervising skill and a direct manual
entry point use the same prompt, say that they are two routes to one mechanism,
show the literal path relative to the repository root, and distinguish the
skill's broader supervision or follow-up from the direct prompt's scope.

When recurring prompts need stable personal inputs, keep repeat invocations short
by reusing approved settings stored outside Git. Assist first-use setup using
available evidence and ask only about unresolved choices. Reuse scope and action
authority only when the user has approved them. Keep invocation overrides
temporary unless the user asks to save them. Let each owning prompt specify its
storage format and location, and save configuration rather than credentials.

## Bounded Forward-Testing

For a complex or risky skill change, an occasional independent attempt at a
realistic task may justify its cost. Follow the system `skill-creator` guidance
when available. Use minimum raw artifacts, an isolated temporary workspace,
permitted side effects, and a bounded question; withhold the intended answer.
Inspect the resulting actions and artifacts. Compare the existing and revised
guidance only when the question requires a comparator, and state the limits of
that observation, including the model and context when known.

Before inspecting evaluation results, derive acceptance criteria from the user's
desired outcome, authority, and relevant constraints, independently of the
proposed skill's prescribed steps. The evaluating agent owns this work. Apply
the same criteria to both conditions in a comparison, and report conformance
separately from task success.

Optionally, include a case selected from the user's objective independently of
the triggering incident, including a should-not-trigger case when relevant.
If using a final holdout during iterative tuning, keep it untouched until the
revision is finalized; cases used to select revisions are development evidence.

For comparisons, isolate each condition's instructions, plugins, conversation history, and workspace
so the baseline cannot inherit the guidance under evaluation. Hold the task and resources comparable.
Before trusting an automated scorer, check that a known-good result passes and a plausible bad result
fails on the behavior being measured. Verify required behavior before interpreting reductions in
code size, tool calls, or cost; report untested dimensions separately.
When comparing resource use, include failed and capped attempts, state the accounting boundary,
and use inexpensive measurements already available from the run.

This is optional authoring evidence. It does not establish ordinary later-use
effectiveness or satisfy a `later-session` verification opportunity. Keep the
existing typed evidence requirements. Do not build maintained prompt corpora,
repeated-run infrastructure, raw trace archives, paid model-backed CI, or public
evidence records merely to validate prose. Additional authority or substantial
cost still requires approval.

## Promoting Local Guidance

When turning repo-local `.agents/skills`, `docs/agents`, `prompts/`,
`AGENTS.md`, or `PLANS.md` material into user-scoped skills:

1. Inventory the local guidance and classify it as generic, language-specific,
   repo-specific, stale duplicate, or ordinary engineering judgment.
2. Promote only reusable, non-obvious workflows that are likely to recur.
3. Generalize names, triggers, paths, and examples so the new skill does not
   leak one repo's domain model.
4. Leave domain-specific contracts local until the same pattern appears in
   another repo.
5. When promoting a stable prompt into a skill, replace the old prompt file with
   a short pointer if existing workflows may still link to that path.
6. Replace duplicated local rules with short references to the user-scoped
   skill when editing that repo is in scope.

## References And Casebooks

A reference controls when material is loaded rather than defining its semantic
role; it may mix roles and need restructuring. Moving text into `references/`
does not by itself compress the decision model. Route a reference from
`SKILL.md` with the condition that makes it relevant.

Create no global casebook by default. When a skill has useful optional cases,
keep its casebook as a sanitized reference inside that skill and route to it
only when the default judgment and relevant mechanics leave genuine ambiguity.
Organize capsules by reasoning problem or witness shape, never by source
repository or report chronology.

Admit a capsule only for a distinct plausible wrong implementation or
observation boundary. Keep it compact:

- situation;
- plausible wrong behavior;
- useful witness or observation boundary; and
- related mechanic, when one is needed.

Exclude report narratives, private provenance, transcripts, and raw evidence.
Full evidence may remain in external state; public casebooks contain only the
sanitized reusable shape.
