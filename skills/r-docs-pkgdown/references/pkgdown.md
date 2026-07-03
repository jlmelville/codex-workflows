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
uvx zizmor .github/workflows
```

## Build Notes

`pkgdown::build_site()` may need network access for external JavaScript assets
or CRAN metadata. If sandboxed network fails and the build matters, request
approval and rerun with escalation.
