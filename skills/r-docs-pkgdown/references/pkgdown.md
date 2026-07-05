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
- Treat enabling `Roxygen: list(markdown = TRUE)` as a docs-modernization
  commitment, not a local cleanup. Either complete the full roxygen markdown
  conversion immediately or record a required follow-up chunk before moving on
  to formatting, lint, pkgdown, CI, or structural refactors.
- Use roxygen-only searches to size the conversion without matching ordinary
  source comments:

  ```sh
  rg -n "^#'\\s*@(md|noMd)\\b" R
  rg -n "^#'.*\\\\(code|link|url|href|itemize|item|emph|strong|describe|dontrun|donttest|dontshow|eqn|deqn|Sexpr|tabular)" R
  ```

- Convert old `\code{}` and `\emph{}` markup when touching a topic.
- Regenerate with `roxygen2::roxygenise()` after roxygen source changes.
- After regenerating, inspect `git diff -- DESCRIPTION` separately.
  `roxygen2::roxygenise()` can replace `RoxygenNote` with
  `Config/roxygen2/version`; restore that churn unless metadata modernization
  is explicitly in scope.
- For inline algebra in markdown roxygen, prefer Rd-friendly plain forms such
  as `D^(-1/2)` over TeX-like text in backticks such as `D^{-1/2}`. After
  regenerating, inspect `man/*.Rd` for awkward formula rendering, not just the
  roxygen source.
- For nested list conversions, keep continuation paragraphs indented under the
  intended parent bullet. Inspect generated Rd for changed `\itemize{` and `}`
  boundaries; successful roxygen generation can still hide list-structure
  drift.
- For exported renames, run roxygen twice: the first pass may delete old topics,
  aliases, or exports, and the second pass should be idempotent.
- Search for stale public names after renames, including examples, articles,
  README, NEWS, `_pkgdown.yml`, `NAMESPACE`, and `man/*.Rd`.
- For full markdown modernization, run `roxygen2::roxygenise()` twice and then
  `devtools::check(document = FALSE, args = c("--no-manual"))` before handing
  off the docs chunk.
- After broad conversions, check for malformed inline markdown and Rd validity:

  ```sh
  perl -ne 'if (/^#\x27/ && (tr/`// % 2)) { print "$ARGV:$.:$_" }' R/*.R
  Rscript -e 'invisible(lapply(list.files("man", pattern = "\\.Rd$", full.names = TRUE), tools::checkRd))'
  ```

  Use `#\x27` instead of literal `#'` in single-quoted shell programs that
  match roxygen prefixes. Include `man-roxygen/*.R` in the Perl check when that
  directory exists.

## README

Keep README short:

- badges,
- install,
- one or two quick examples,
- links to articles and reference pages.

Use badges sparingly. Prefer glanceable project status badges: `R-CMD-check`,
test coverage, CRAN status when the package is on CRAN, and optionally a last
updated or last commit badge. Avoid badges for implementation-maintenance
checks such as Air, lintr, pkgdown, actionlint, or zizmor unless the user asks
for them; keep those signals in CI instead of the README badge row.

Move detailed metric theory, literature background, and long examples to
`vignettes/articles/`.

## Articles

Use pkgdown articles, not CRAN vignettes, when the goal is website guidance.
Build-ignore article infrastructure appropriately.

When helpers rewrite `_pkgdown.yml`, compare the result against intentional
navigation choices. Restore curated `articles:` or reference structure before
validating so user-facing site organization is not silently replaced by helper
defaults.

## GitHub Pages

`usethis::use_pkgdown_github_pages()` has both local scaffolding and remote
GitHub side effects. It can enable Pages, set repository homepage metadata, add
pkgdown URLs, add ignore files, and rewrite local workflow/config files. Treat
these effects separately: preserve useful remote state and ignore-file updates,
but restore hardened workflows and curated `_pkgdown.yml` content when helper
defaults are too broad or remove intentional navigation.

After running it, reconcile `.github/workflows/pkgdown.yaml` against hardened
patterns:

- SHA-pinned actions,
- top-level read-only permissions,
- `persist-credentials: false`,
- build/deploy split with artifact handoff,
- `contents: write` only on deploy.

Also verify remote state, not just local files:

```sh
gh api repos/OWNER/REPO/pages
gh repo view --json homepageUrl
git ls-remote --heads origin gh-pages
curl -I -L https://OWNER.github.io/REPO/
```

Expected Pages state for a `gh-pages` deploy is usually `status: built`,
`source.branch: gh-pages`, and `source.path: /`. A missing GitHub repository
homepage link can mean the remote repo metadata was not updated even when
`_pkgdown.yml`, a deploy workflow, and a `gh-pages` branch exist locally or on
the remote.

If `gh` authentication or PAT scopes block Pages setup or API reads, report the
exact permission failure. Public repos can often be checked through public HTTP
and read APIs, but enabling or updating Pages requires repository permissions.

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
