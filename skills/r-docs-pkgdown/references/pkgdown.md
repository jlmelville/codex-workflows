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
- For roxygen markdown audits or package-wide conversions, use
  [roxygen-markdown.md](roxygen-markdown.md).
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

For GitHub install instructions, use `pak::pak("owner/repo")`. When refreshing
older READMEs, replace `devtools::install_github("owner/repo")` examples rather
than preserving legacy installation guidance.

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

## Static Figures

When committed README or article figures depend on package plotting behavior,
do more than validate that image paths resolve:

1. Inventory each image reference and map it to its producing call, script, or
   documented regeneration procedure.
2. Record behavior dependencies that can make the image semantically stale,
   including plotting defaults, palettes, ordering, selection rules, reversal,
   aspect ratio, and device dimensions.
3. After related behavior changes, regenerate affected figures from current
   package code while preserving intentional dimensions and output format.
4. Visually inspect the regenerated figures. Checksums can identify exact
   duplicates but cannot establish semantic correctness.
5. Revalidate every documentation image reference, then search for exact
   duplicates, unreferenced assets, and legacy image trees. Confirm references,
   build-ignore rules, and relevant history before deleting an asset tree.
6. Run the focused article or site build that exercises the refreshed figures.

An unchanged filename or successful broken-link check does not prove that a
static figure still represents current behavior. Semantic dependency review is
not a generic validator problem; keep repository-specific rendering and cleanup
mechanics local.

## GitHub Pages

`usethis::use_pkgdown_github_pages()` has both local scaffolding and remote
GitHub side effects. It can enable Pages, set repository homepage metadata, add
pkgdown URLs, add ignore files, and rewrite local workflow/config files. Treat
these effects separately: preserve useful remote state and ignore-file updates,
but restore hardened workflows and curated `_pkgdown.yml` content when helper
defaults are too broad or remove intentional navigation.

When running the helper mainly for remote Pages or repository-homepage side
effects, expect local overwrites. Start from a clean worktree or save the
pre-helper state, then compare against `HEAD` afterward and restore curated
`_pkgdown.yml`, workflow hardening, destination choices, and ignore policy. If
the helper fails with unset PAT, insufficient scopes, or remote configuration
errors such as `maybe_ours_or_theirs`, treat that as GitHub auth/config state;
do not accept partially written local scaffold files as final.

Before adding pkgdown to a repo, run `git ls-files docs`. If `docs/` is tracked
and contains hand-authored, historical, or non-pkgdown site material, do not use
pkgdown's default `docs/` destination. Set a distinct `_pkgdown.yml`
`destination`, such as `pkgdown-site`, add matching `.gitignore` and
`.Rbuildignore` entries when generated output should stay untracked, and align
workflow artifact upload/download paths with that destination.

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

`pkgdown::build_site()` may need network access for external JavaScript assets,
CRAN package metadata, and CRAN news timeline metadata. DNS errors for hosts
such as `cloud.r-project.org` or `crandb.r-pkg.org` are sandbox/network
evidence; if the build matters, request approval and rerun with escalation.

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
artifacts. Rerun with approval only when a final pkgdown result is required.
