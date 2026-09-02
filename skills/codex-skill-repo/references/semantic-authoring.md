# Semantic Skill Authoring

Use this when adding learned guidance or restructuring a skill corpus. Preserve
the evidence and mechanics needed for correctness while reducing duplicated
incident-shaped decisions.

## Admission

State the changed action, authority, observation, or success condition and check whether an existing principle already
produces it. A new narrative is further evidence, not a new rule, when the decision and witness are unchanged.

A skill may be relevant enough to consult without entering its operational workflow. Enter only when the task requires
that outcome and authority permits it; a terminal predecessor prunes dependent stages but not independent closure duties.

Use these destinations:

- **Default judgment:** a compact principle needed when the skill triggers. State the distinguishing condition and
  action, not the incident; keep unconditional privacy, authority, evidence, and completion contracts here.
- **Routed mechanics:** exact commands, APIs, tool behavior, environment
  requirements, file formats, ordering, and fail-closed recipes. Prefer scripts
  for deterministic or quoting-sensitive behavior; do not turn mechanics vague.
- **Optional cases:** short analogies for a distinct plausible wrong implementation
  or observation boundary that judgment and mechanics do not resolve.
- **Verification only:** recurrence supporting or contradicting an existing decision
  and witness. Keep it in external accepted state, not public skill content.

Split material when its parts need different roles or loading conditions. The
smallest change is the smallest truthful change to the decision model, not the
fewest edited lines. Do not merge distinguishable conditions that require
different actions.

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

A reference controls when material is loaded; moving text into `references/`
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
