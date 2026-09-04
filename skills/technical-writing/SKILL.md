---
name: technical-writing
description: Write, revise, or review technical prose across READMEs, API documentation, guides, comments, docstrings, release notes, design documents, and explanations. Use when deciding what readers need, structuring content around their task, grounding warnings or contrasts, or removing low-value detail. Pair with format-specific skills for generation and validation.
---

# Technical Writing

Use this skill to decide what technical prose belongs and how to shape it.
Let surface-specific skills own file formats, public contracts, generation,
rendering, and validation.

## Establish The Reader Task

Before drafting, identify:

- the surface and intended reader;
- the reader's immediate task or decision;
- the source-supported facts; and
- the function of the passage in that task.

Do not preserve a detail merely because it is true. Give it a reader-facing
job: orient, instruct, connect steps, explain a reason, define a non-obvious
contract, or prevent a plausible mistake.

## Admit Sentences By Reader Value

- Retain a sentence when it changes the reader's action or interpretation,
  connects material needed for the task, or exposes behavior the reader could
  not safely infer.
- Delete facts already evident to the intended reader when they do not affect
  the task. Prefer deletion to polishing a sentence with no useful function.
- Do not narrate code syntax or control flow. Retain a concise bridge when
  incidental or out-of-domain setup creates an object or condition needed by
  the document's actual task.
- Match detail to the surface. Keep internal history, experiment reports,
  maintainer procedures, and exhaustive edge cases out of a task-oriented
  document unless they change what its reader should do.

## Ground Contrasts And Warnings

Use a negative contrast only when available evidence establishes the rejected
alternative or the distinction prevents a plausible mistake. Otherwise state
the positive fact directly or delete the contrast.

A useful warning names the consequence and the reader's action. Do not list an
arcane option, limitation, or hypothetical misuse merely to appear complete;
explain the supported reason someone would need it.

## Shape The Passage

- Lead with the outcome or task, then supply the minimum context needed to act.
- Follow the reader's workflow rather than the author's implementation or
  discovery chronology.
- Choose the form as well as the wording. When prose obscures order, shape,
  ownership, or change, use the smallest structural representation that exposes
  the relationship; keep prose for interpretation.
- Keep examples focused on the concept being taught and explain incidental
  setup only where it bridges into that concept.
- Move specialized detail to a better-matched surface when it remains useful.

## Run A Reader Pass

Treat an explanation as a dependency chain. During drafting and review, check
that each premise, term, object role, and relationship is established before the
next step relies on it; restore or reorder the earliest missing dependency. If a
reader says the explanation did not land, use that feedback to localize the
break and rebuild from there rather than merely shortening or paraphrasing the
same path.

For each sentence, ask whether it adds non-inferable value, is supported by the
available evidence, belongs on this surface, and advances the reader's task.
For each negative clause, identify the source of the alternative it rejects.
Delete or rewrite anything that fails those checks.

When the boundary remains unclear, read
[sentence-admission cases](references/sentence-admission-cases.md).
