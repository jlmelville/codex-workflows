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
