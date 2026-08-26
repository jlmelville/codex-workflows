# Documentation Validation

Use this when an article, vignette, README example, or declared self-contained
chunk needs evidence from a fresh R session.

## Choose The Boundary

A successful complete render proves that the document works in its declared
order. It does not prove that a later chunk is self-contained when earlier
chunks can create objects, attach packages, or change options. Run a declared
self-contained chunk separately with only its documented setup.

Before treating a render as execution evidence for reader-facing code,
classify each block as an executable document chunk, an intentionally static
example, or code exercised by a separate check. A successful render does not
execute a plain fenced R block; keep that example explicitly illustrative or
retain a separate execution witness.

When the current package must be available, distinguish dependency setup from
source installation. Use the repository's normal dependency workflow first.
If dependencies are already available but a higher-level development helper
still attempts unavailable dependency planning, install the current source
directly into an explicit temporary library and put that library first for the
render.

## Validate The Claimed Lesson

A successful render establishes executability, not the truth of prose that
interprets generated output or describes how an example was selected and
reproduced. For each pivotal empirical claim, identify maintained evidence that
directly supports it. Keep the prose, executed parameter values, tables, plots,
selection and provenance account, and public reproduction boundary aligned
with that evidence. When the claim derives from generated output, add hidden
semantic checks using stable status classes, equivalence relations, or
inequalities rather than fragile exact iterations and floating-point snapshots.
Before ranking displayed scores across scales, labels, methods, or metrics,
establish that their baselines and normalizations are comparable. When they are
not, interpret each score against its own baseline instead of treating the
largest raw value as best.

## Preserve Technical-Article Integrity

Before revising a technical article, identify its primary reader task. Keep the
code, visible output, and interpretation aligned with that task. As a default,
give each substantial reader-facing passage a clear function such as orienting
the reader, defining a needed relationship, motivating a problem, explaining a
choice, connecting adjacent steps, interpreting visible evidence, or stating a
consequence. Hidden semantic checks normally need no narration; explain their
underlying invariant only when it independently helps the reader. Review
contrasts and caveats in context rather than mechanically removing connective
words, because a meaningful distinction may be the clearest way to explain a
boundary. Inspect the rendered article to confirm that hidden chunks do not
leave visible transitions or references without their payoff.
During final technical reconciliation, map each hidden assertion to visible
code, output, prose, or a declared executable example. Move unmatched schema
or coverage assertions to package tests or the API reference that owns them.
When prose or a decision table compares several result or dataset families,
enumerate structurally distinct shapes and decision-material outliers under the
stated selection criterion before claiming a common contract or ranking. When
an article delegates a demonstrated workflow to a reference page, verify that
the reference documents the exact input shape used.

## Review Planned Articles In Two Stages

When an execution plan and documentation guidance both govern a substantial
article revision, use the plan to preserve scope, factual obligations, state,
and validation, while the reader task controls visible order, terminology, and
explanatory depth. Draft the shortest question-to-payoff reader path before
mapping the plan's obligations onto it. Keep that mapping as a coverage ledger;
put an obligation into visible prose only when it changes what the reader does,
observes, interprets, or concludes.

Freeze and render the exact article, then follow `$planning-workflow`'s
[review-packet contract](../../planning-workflow/references/audits-and-review-packets.md#review-packets)
for cold-packet contents, withheld plan context, and later plan-aware
reconciliation, and its
[bounded independent-review contract](../../planning-workflow/references/audits-and-review-packets.md#bounded-independent-review)
for correction and re-review limits. In the cold stage, ask whether the named
reader can reach and use the promised payoff, whether terminology or
implementation machinery appears before it is needed, and whether visible
headings, navigation, and links support the path. In the technical stage,
confirm that editorial compression preserved required contracts, examples,
semantic witnesses, and validation. Keep rendering, executable checks, and
deterministic link checks as separate evidence; neither review stage substitutes
for them.

If the review packet transforms or packages the rendered article, treat the
delivered file as a separate validation boundary. Inspect that exact file after
transformation and before recording its immutable identity or sending it.
Preserve every site-level script, stylesheet, asset, and interaction that the
artifact or prose promises, or state explicitly which behavior the portable
packet excludes.

## Inspect Rendered Numerical Tables

Inspect rendered table cells in addition to their source objects. Fixed decimal
rounding can display a meaningful nonzero value as zero, a near-one value as
exactly one, or erase relative scale while the build and hidden semantic checks
still pass. Choose precision that preserves the reader's interpretation near
meaningful boundaries, baselines, thresholds, and decision cutoffs. When
magnitude is part of the lesson, use significant-digit or scientific formatting
for small or wide-ranging values, then confirm that the table and adjacent
interpretation describe the same computed quantity.

## Precomputed Stochastic Figures

When an article interprets a precomputed figure from a stochastic numerical
method, regenerate the selected artifact through the documented public recipe.
Freeze upstream stochastic inputs, reset the seed immediately before each
sampled call, and compare the regenerated artifact when exact identity is an
appropriate contract. If the numerical representation is non-unique, validate
the identifiable object or subspace and then explicitly recheck every
orientation-dependent caption, representative selection, and visual claim.

## Figure-Led Articles

Keep the shortest useful user action and observation on the main reading path.
When complete reproduction code is necessary but would overwhelm that path,
put it in a tracked companion script and expose it through a collapsed details
block. Parse and smoke the companion independently so the full render is not
its only completeness witness. Inspect final figures at their intended page
width for annotation size, legends, clipping, thumbnail alignment, and
figure-text order; native-resolution inspection alone is insufficient. When a
plot highlights observations selected by an estimator, subspace, or ranking,
keep the exact source objects adjacent to that originating plot and state its
ranking scope before a nearby panel introduces another ranking. If highlighted
points coincide, preserve their markers at the true coordinates and offset only
the labels, adding short leader lines when needed. When several highlights need
leaders, choose label placements jointly to avoid other highlighted markers,
labels, leader segments, and plot boundaries, and stop each segment short of
the marker edge and label glyph.

When a lesson-bearing figure shows hover, selection, animation, or another
transient widget state, treat automated widget generation and capture of that
state as separate artifact boundaries. Reproduce the widget through the
tracked recipe; for the capture, either maintain deterministic event injection
or record a bounded manual recipe naming the viewport, state trigger, and
output filename. Do not treat a rest-state static export as proof that an
interaction-state screenshot is reproducible.

## Place Companion Code Deliberately

Before locating executable article companions, decide which distribution
boundary users need. Keep short essential code inline, use build-ignored
article infrastructure only for website reproduction, and choose a
build-included installed location when installed users need the asset. Inspect
`.Rbuildignore` and the source archive rather than inferring visibility from a
successful pkgdown render. Exercise source, built-package, installed-package,
and website access only for the contexts the prose claims; do not rely on a
test or companion that disappears from the built package.

## Mathematical Catalogue Articles

When an article promises a comprehensive catalogue of implemented formulas,
inventory every entry's authoritative source, implemented domain, standard
start, known correction, and witness state before drafting. Prototype each
distinct formula shape, then independently transcribe and compare every
published formula at a nontrivial deterministic point with an entry-appropriate
absolute-plus-relative tolerance. Do not claim completeness while any entry
lacks source reconciliation or a numeric witness. Keep the duplicate oracle as
private documentation evidence unless users have a separate need for that API.

## Fresh Temporary-Library Article Builds

Use the bundled helper from an R package root when dependencies are already
available but the current package needs a fresh isolated install. It installs
the source into a temporary library, puts that library first, uses a writable
temporary cache and render destination, and removes all temporary output after
the check:

```sh
Rscript --vanilla \
  "${HOME}/.agents/skills/r-docs-pkgdown/scripts/validate-document.R" \
  --rmarkdown path/to/article.Rmd
```

For a configured pkgdown article, pass its article name instead of a source
path:

```sh
Rscript --vanilla \
  "${HOME}/.agents/skills/r-docs-pkgdown/scripts/validate-document.R" \
  --pkgdown article-name
```

The helper deliberately does not acquire dependencies. A missing dependency is
a setup result, not evidence that the document or package source failed. Its
temporary output proves execution, not final visual quality; inspect the normal
rendered artifact separately when presentation matters.

When the claim concerns files that survive `R CMD build`, add `--build-source`.
Use one `--expect-installed-doc RELATIVE-PATH` per required file beneath the
installed package's `doc/` directory. The helper rejects installed-artifact
checks against a direct source-directory install.
