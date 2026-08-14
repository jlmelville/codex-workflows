# Semantic Skill Authoring

Use this when adding learned guidance or restructuring a skill corpus. Preserve
the evidence and mechanics needed for correctness while reducing duplicated
incident-shaped decisions.

## Admission

State what the proposed material changes: an action, authority boundary,
required observation, or success condition. Check whether an existing
principle already produces that result. A new repository, package, or narrative
is further evidence rather than a new public rule when the decision and witness
shape are unchanged.

Use these destinations:

- **Default judgment:** a compact principle or procedure needed when the skill
  triggers. State the distinguishing condition and resulting action, not the
  source incident. Keep unconditional privacy, authority, evidence, and
  completion contracts here when they must always govern the work.
- **Routed mechanics:** exact commands, APIs, tool behavior, environment
  requirements, file formats, ordering constraints, and fail-closed recipes.
  Prefer a script or validator when behavior is deterministic or quoting is
  fragile. Do not compress exact mechanics into vague advice.
- **Optional cases:** short analogies for a distinct plausible wrong
  implementation or observation boundary when judgment and mechanics do not
  make the next move clear.
- **Verification only:** recurrence that supports or contradicts an existing
  decision and witness. Keep it in external accepted state; it is not public
  skill content.

Split material when its parts need different roles or loading conditions. The
smallest change is the smallest truthful change to the decision model, not the
fewest edited lines. Do not merge distinguishable conditions that require
different actions.

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
