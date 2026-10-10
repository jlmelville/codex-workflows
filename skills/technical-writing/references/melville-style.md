# Melville Style And Article References

Use this reference when drafting or revising technical prose in James
Melville's voice. The whole articles are the primary style evidence. The
observations below are an initial interpretation of that evidence, subject to
James's corrections; they cannot specify the voice completely.

## Read Whole Articles

Before substantial drafting, read a complete author-selected article suited to
the task, including the progression through equations, code, results, and
conclusion. For broader calibration, compare the three. Read beyond openings
and memorable asides: pacing and later payoffs depend on what came before. If
full text is unavailable, disclose the limitation rather than claiming to have
calibrated from an excerpt. Use the current task's audience and purpose to
choose what carries over.

### Author-Selected Starting Set

| Article | What to attend to across the whole piece |
| --- | --- |
| [Spectral Methods](https://jlmelville.github.io/smallvis/spectral.html) | Builds a usable map of competing names and matrix conventions, connects the methods, then returns to computational choices and unresolved problems. Watch how an early distinction becomes useful later. |
| [Nesterov Accelerated Gradient and Momentum](https://jlmelville.github.io/mize/articles/nesterov.html) | Carries an implementation puzzle through notation, derivations, code, disagreeing results, and eventual reconciliation. The numerical checks complete the explanation promised at the start. |
| [Sparse TF-IDF Example](https://jlmelville.github.io/rnndescent/articles/sparse-example.html) | Develops an example through inspection and follow-up questions. The Austen digression gives the data a personality; the ending returns to the practical purpose of demonstrating sparse-data support. |

### Supplementary Candidates

These were found in the collections James suggested. They broaden the sample;
they do not have the same explicit selection status as the three above.

- [UMAP for t-SNE](https://jlmelville.github.io/uwot/articles/umap-for-tsne.html):
  a comparatively restrained explanation that takes the reader from familiar
  machinery to a new method, translating notation and implementation choices.
- [Hubness](https://jlmelville.github.io/rnndescent/articles/hubness.html):
  a sustained experiment that tries plausible diagnostics, acknowledges their
  limits, and develops practical recommendations from the results.
- [Renormalizing after TF-IDF + SVD](https://jlmelville.github.io/drnb/articles/tfidf-renorm.html):
  a notebook register, with short interpretations between groups of experiments
  and a conclusion that leaves one comparison unresolved.

For further candidates, browse the [uwot articles](https://jlmelville.github.io/uwot/articles/index.html),
[rnndescent articles](https://jlmelville.github.io/rnndescent/articles/index.html),
and [drnb notebooks](https://jlmelville.github.io/drnb/). An index identifies
candidates; read an article before treating it as style evidence.

## Working Interpretation

**Give the explanation a reason to exist.** Establish a concrete puzzle,
implementation difficulty, or experiment worth doing. Let that purpose govern
the depth: reconciling apparently equivalent algorithms can justify a long
derivation. The author is a technically capable companion prepared to work
through the awkward parts alongside the reader.

**Make the reasoning continuous.** Introduce the objects and conventions,
explain why the next operation is useful, and interpret what it produces.
Equations and code participate in that chain. Restating an expression or
showing an intermediate substitution can be valuable when it saves the reader
from reconstructing a change of notation, index, or viewpoint. Preserve those
bridges when shortening.

**Let the investigation supply the structure when it teaches.** A result can
raise the next question; a failed idea can explain why another approach is
needed. The sparse example checks candidate interpretations against other
passages and corpus-wide word summaries. Nesterov's mismatched outputs make the
bookkeeping consequential.
Preserve such earned detours and their eventual return to the main question.
An article need not become a direct recipe, but each detour needs an
explanatory or narrative purpose.

**Keep the conversational rhythm.** Use connected paragraphs, contractions,
and direct address at the sample's level of informality. Longer explanatory
sentences can sit beside a short reaction. Transitions should carry the
reader's current state of understanding into the next step. Lists suit recipes
and comparisons; turning every paragraph into bullets loses much of this
cadence. First person can mark a choice or judgment, and shared calculations
can use “we.” Attribute personal experiences only when James supplied them.

**Let personality arise from the material.** Dry reactions to awkward notation,
self-directed exasperation, literary allusions, and small callbacks all occur.
Their placement matters more than a stock vocabulary. An aside can give a dense
passage breathing room or sustain a thread across an example. Preserve useful
existing asides; do not require a joke, an admission of confusion, or a personal
anecdote in every section. The restrained supplementary article is useful
evidence that the voice also works without frequent comic interruptions.

**Be candid about what the evidence buys.** Distinguish an algebraic result,
a numerical observation, a practical preference, and an unresolved suspicion.
Qualify the particular claim that needs qualification. State clear results
plainly. In the drnb example, visual preference and preservation metrics are
considered together without forcing every comparison to produce a winner.
References often explain where to go next and what the source helps with.

## Small Cues In Context

These are reminders to revisit the surrounding article, not wording templates:

- Spectral Methods ends a discussion of conflicting eigenvector labels with
  “In fact they have opposite meanings. Great.” The reaction follows the
  precise explanation of the inconvenience.
- Nesterov closes the matched numerical comparisons with “That’s a relief.”
  That brief payoff depends on the earlier derivation and disagreement.
- The sparse example's “Way to go, `said`.” becomes a callback as the word
  appears in successive summaries. The humor belongs to the ongoing analysis.

## Compare The Draft With Its Model

Read the draft as a whole and compare it with the chosen article. Check the
sequence of questions, balance of explanation and demonstration, paragraph
rhythm, and strength of conclusions. Preserve the reader's path through the
difficulty and the author's room to react. Correct facts, short sentences, and
recognizable catchphrases alone do not establish a match.

Carry the voice at the destination's scale: a reference entry may need only a
plain explanation and a candid qualification; an exploratory article can
sustain a longer investigation. Source code, package defaults, dated updates,
and notebook output are context for these samples, not technical requirements
or mandatory formatting for a new document.
