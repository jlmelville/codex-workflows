---
name: technical-writing
description: Draft, revise, or review technical documentation, explain technical designs, and create or refine technical diagrams, including Mermaid. Use for deliberate technical communication and substantive comment or docstring revisions; skip incidental text edits during coding.
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

Make the reader's knowledge explicit: identify the terms, notation, and concepts they can be assumed
to know and those the passage must establish. Check jargon and analogies against that baseline; a
comparison helps only when the reader knows what it compares with.

When revising established prose, preserve the intended author voice alongside clarity. Calibrate
against representative samples, preferring author-selected ones; use older prose when recent rewrites
are an unreliable baseline. Retain useful explanatory cadence and transitions at the surface's level of
informality, without inventing personal experience or compulsory humor. Concision and rendering checks
do not establish that the author's voice survived.

For James Melville's technical prose, read
[Melville style and article references](references/melville-style.md).
Use its author-selected whole articles to calibrate the draft; the distilled
observations are a reading aid, not a substitute for those articles.

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

- Lead with the outcome or task, then supply the minimum context needed to act. Make the intended
  audience and payoff clear early. For articles, use the title and first three sentences as a
  diagnostic for relevance, not a fixed limit. Count subtitles, images, and other preamble when
  judging how quickly the reader reaches that payoff.
- Follow the reader's workflow rather than the author's implementation or
  discovery chronology.
- Choose the form as well as the wording. When prose obscures order, shape,
  ownership, or change, use the smallest structural representation that exposes
  the relationship; keep prose for interpretation.
- Keep examples focused on the concept being taught and explain incidental
  setup only where it bridges into that concept.
- Move specialized detail to a better-matched surface when it remains useful.

For diagrams, arrange the reader's comparison explicitly: keep identities,
terminology, and ordering stable across alternatives, and group phases or
ownership boundaries that change interpretation. Use parallel, concise labels
and put a shared edge meaning in a caption instead of repeating it on every
arrow. Keep consequential constraints and failure paths visible. In Mermaid,
use block grids for alignment and state diagrams for lifecycle logic when
supported; automatic flowchart layout is not a positioning guarantee.
Before delivery, render Mermaid and inspect it at its intended display size
(760px wide for chat if unspecified). Check label legibility and clipping;
reorient, regroup, or split cramped diagrams before reducing text size.
If rendering is unavailable, report readability as unverified.
Pair focal color with meaningful text or shape.

## Run A Reader Pass

Treat an explanation as a dependency chain. During drafting and review, check
that each premise, term, object role, and relationship is established before the
next step relies on it; restore or reorder the earliest missing dependency. If a
reader says the explanation did not land, use that feedback to localize the
break and rebuild from there rather than merely shortening or paraphrasing the
same path.

Supply enough local context to follow the explanation without opening supporting links or
reconstructing earlier discussions. Summarize the necessary contribution of a link or prior
installment; retain links for evidence and further detail. For deliberately cumulative material,
state prerequisites and recap what the next step needs.

For each sentence, ask whether it adds non-inferable value, is supported by the
available evidence, belongs on this surface, and advances the reader's task.
For each negative clause, identify the source of the alternative it rejects and
the reader mistake it prevents. Remove clauses whose only job is defending the
writer from a possible criticism; changing their wording leaves that problem
intact. Put a supported limitation once where it changes interpretation or
action. Delete or rewrite anything that fails those checks.

When the boundary remains unclear, read
[sentence-admission cases](references/sentence-admission-cases.md).
