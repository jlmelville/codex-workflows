# pkgdown and Documentation Reference

## DESCRIPTION

Common fields:

- `URL`
- `BugReports`
- `Roxygen: list(markdown = TRUE)`
- `Config/roxygen2/version`
- `Config/Needs/website: pkgdown`
- `Suggests: pkgdown` when building locally or in CI

## Roxygen

- Prefer markdown roxygen globally.
- Convert old `\code{}` and `\emph{}` markup when touching a topic.
- Regenerate with `roxygen2::roxygenise()` after roxygen source changes.
- Check whether regenerated files include unrelated version churn before
  committing.
- For exported renames, run roxygen twice: the first pass may delete old topics,
  aliases, or exports, and the second pass should be idempotent.
- Search for stale public names after renames, including examples, articles,
  README, NEWS, `_pkgdown.yml`, `NAMESPACE`, and `man/*.Rd`.

## README

Keep README short:

- badges,
- install,
- one or two quick examples,
- links to articles and reference pages.

Move detailed metric theory, literature background, and long examples to
`vignettes/articles/`.

## Articles

Use pkgdown articles, not CRAN vignettes, when the goal is website guidance.
Build-ignore article infrastructure appropriately.

## GitHub Pages

`usethis::use_pkgdown_github_pages()` may rewrite workflows. After running it,
reconcile `.github/workflows/pkgdown.yaml` against hardened patterns:

- SHA-pinned actions,
- top-level read-only permissions,
- `persist-credentials: false`,
- build/deploy split with artifact handoff,
- `contents: write` only on deploy.

Run:

```sh
actionlint
zizmor .github/workflows  # or uvx zizmor .github/workflows when not installed
```

## Build Notes

`pkgdown::build_site()` may need network access for external JavaScript assets
or CRAN metadata. If sandboxed network fails and the build matters, request
approval and rerun with escalation.

In restricted Codex sandboxes, set cache paths to writable temporary
directories when needed, for example `XDG_CACHE_HOME=/tmp/pkgdown-cache`. Treat
generated `docs/` output as source diff only when the repo tracks or explicitly
requests committed site output.

When validating pkgdown without committing generated site output, combine a
writable cache with a temporary destination:

```sh
XDG_CACHE_HOME=/tmp/r-cache Rscript -e 'dest <- tempfile("pkgdown-"); dir.create(dest); pkgdown::build_site(new_process = FALSE, override = list(destination = dest))'
```

Use a project-specific `tempfile()` prefix when it helps identify cleanup
artifacts. DNS errors such as `Could not resolve hostname [cloud.r-project.org]`
are sandbox/network evidence; rerun with approval only when a final pkgdown
result is required.
