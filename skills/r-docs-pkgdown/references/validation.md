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
figure-text order; native-resolution inspection alone is insufficient.

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
