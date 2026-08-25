# Documentation Validation

Use this when an article, vignette, README example, or declared self-contained
chunk needs evidence from a fresh R session.

## Choose The Boundary

A successful complete render proves that the document works in its declared
order. It does not prove that a later chunk is self-contained when earlier
chunks can create objects, attach packages, or change options. Run a declared
self-contained chunk separately with only its documented setup.

When the current package must be available, distinguish dependency setup from
source installation. Use the repository's normal dependency workflow first.
If dependencies are already available but a higher-level development helper
still attempts unavailable dependency planning, install the current source
directly into an explicit temporary library and put that library first for the
render.

## Validate The Claimed Lesson

A successful render establishes executability, not the truth of prose that
interprets generated output. For each pivotal termination, ordering, tradeoff,
or improvement claim, identify the result field and metric that proves it and
keep the prose, table, and plot on that same basis. Add hidden semantic checks
using stable status classes, equivalence relations, or inequalities rather than
fragile exact iterations and floating-point snapshots.

## Preserve Technical-Article Integrity

Before revising a technical article, identify its primary reader task. Keep the
code, visible output, and interpretation aligned with that task, and make each
reader-facing paragraph motivate a problem, explain a choice, interpret visible
evidence, or state a consequence. Hidden semantic checks normally need no
narration; explain their underlying invariant only when it independently helps
the reader. Review contrasts and caveats in context rather than mechanically
removing connective words, because a meaningful distinction may be the clearest
way to explain a boundary. Inspect the rendered article to confirm that hidden
chunks do not leave visible transitions or references without their payoff.

## Review Planned Articles In Two Stages

When an execution plan and documentation guidance both govern a substantial
article revision, use the plan to preserve scope, factual obligations, state,
and validation, while the reader task controls visible order, terminology, and
explanatory depth. Draft the shortest question-to-payoff reader path before
mapping the plan's obligations onto it. Keep that mapping as a coverage ledger;
put an obligation into visible prose only when it changes what the reader does,
observes, interprets, or concludes.

Freeze and render the exact article before its editorial review. Give a cold
reviewer the rendered artifact, named audience, primary reader task, the
article's role in the documentation set, what nearby guides are intended to
cover, and an explicit scope boundary. Keep that context reader-facing;
withhold the source, execution plan, coverage ledger, and prior reviews. Ask
whether the reader can reach and use the promised payoff, whether terminology
or implementation machinery appears before it is needed, and whether visible
headings, navigation, and links support the path. Require a bounded verdict and
use `$planning-workflow`'s bounded independent-review rules for correction and
re-review limits.

After the corrected article passes that reader review, perform a separate
plan-aware technical reconciliation against the exact source and coverage
ledger. Confirm that editorial compression preserved required contracts,
examples, semantic witnesses, and validation. Keep rendering, executable
checks, and deterministic link checks as separate evidence; neither review
stage substitutes for them.

## Inspect Rendered Numerical Tables

Inspect rendered table cells in addition to their source objects. Fixed decimal
rounding can display a meaningful nonzero value as zero or erase relative scale
while the build and hidden semantic checks still pass. When magnitude is part
of the lesson, use significant-digit or scientific formatting for small or
wide-ranging values, then confirm that the table and adjacent interpretation
describe the same computed quantity.

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

## Direct Temporary-Library Install

For an R Markdown article or vignette, replace `DOCUMENT` with the document
being checked and run from the package root:

```sh
Rscript --vanilla - DOCUMENT <<'RS'
local({
  arguments <- commandArgs(trailingOnly = TRUE)
  stopifnot(length(arguments) == 1L, file.exists(arguments[[1L]]))
  document <- arguments[[1L]]

  library_path <- tempfile("doc-library-")
  dir.create(library_path)
  on.exit(unlink(library_path, recursive = TRUE, force = TRUE), add = TRUE)

  status <- system2(
    file.path(R.home("bin"), "R"),
    c(
      "CMD", "INSTALL", "-l", shQuote(library_path),
      shQuote(normalizePath(".", mustWork = TRUE))
    )
  )
  stopifnot(identical(status, 0L))

  .libPaths(c(library_path, .libPaths()))
  rmarkdown::render(
    document,
    envir = new.env(parent = globalenv())
  )
})
RS
```

Direct `R CMD INSTALL` deliberately does not resolve or install dependencies.
A missing dependency is a dependency-setup result, not evidence that the
document or package source failed. Preserve the fresh-session boundary when
adapting the render command to another document engine.

A direct source-directory install validates installed package code but does not
establish which vignette sources, rendered documents, or auxiliary files survive
the package build. When the claim concerns installed `doc/` contents, build a
source tarball in a temporary directory and install that tarball into the
temporary library instead. Inside a `local()` harness with the same cleanup
pattern, replace the direct install step with:

```r
package_root <- normalizePath(".", mustWork = TRUE)
build_path <- tempfile("doc-build-")
dir.create(build_path)
on.exit(unlink(build_path, recursive = TRUE, force = TRUE), add = TRUE)

previous_path <- setwd(build_path)
on.exit(setwd(previous_path), add = TRUE)
build_status <- system2(
  file.path(R.home("bin"), "R"),
  c("CMD", "build", shQuote(package_root))
)
setwd(previous_path)
stopifnot(identical(build_status, 0L))

tarballs <- list.files(build_path, pattern = "[.]tar[.]gz$", full.names = TRUE)
stopifnot(length(tarballs) == 1L)
install_status <- system2(
  file.path(R.home("bin"), "R"),
  c("CMD", "INSTALL", "-l", shQuote(library_path), shQuote(tarballs))
)
stopifnot(identical(install_status, 0L))
```

Inspect the installed package's `doc/` directory through `system.file()` with
`lib.loc = library_path`; a successful build and install alone does not prove
that each expected artifact is present.
