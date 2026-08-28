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
- When roxygen blocks move files without wording changes, classify generated
  `man/*.Rd` diffs that only update `% Please edit documentation in ...` source
  comments as expected source-path churn.
- After regenerating, inspect `git diff -- DESCRIPTION` separately.
  During an intentional documentation rebuild, retain expected generator
  metadata from the installed roxygen release unless the repository pins
  another generator. When documentation mutation was incidental and no rebuild
  was requested, restore generator metadata churn with other unrelated changes.
- Run roxygen a second time after source moves or exported renames. The first
  pass may update source comments or delete old topics, aliases, or exports; the
  second pass should be idempotent.
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

Use [figure-style.md](figure-style.md) for visual semantics, preservation,
accessibility, and optional enlargement. This section owns generated-asset
integrity and reproduction.

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

## Retiring Stale Site Artifacts

When removing output from an old pkgdown layout, validate three boundaries
separately:

1. Resolve repository consumers of the exact candidate files.
2. Identify the configured current destination, canonical article sources, and
   URL or navigation ownership. Classify same-name redirect assets separately.
3. Build the source archive and inspect expected presence and absence after the
   deletion.

Delete only established legacy output. Use explicit no-diff checks to protect
current sources, redirects, `_pkgdown.yml`, and other guarded configuration;
similar names do not prove that an asset is generated debris.

## GitHub Pages

`usethis::use_pkgdown_github_pages()` has both local scaffolding and remote
GitHub side effects. It can enable Pages, set repository homepage metadata, add
pkgdown URLs, add ignore files, and rewrite local workflow/config files. Do not
run it for a local-only documentation or workflow request. Require explicit
authority to enable or update remote Pages and repository-homepage state first;
otherwise use `usethis::use_pkgdown()` or copy the complete local feature
bundle and leave remote publication state unchanged.

When remote mutation is authorized, treat the effects separately: preserve
useful remote state and ignore-file updates, but restore hardened workflows and
curated `_pkgdown.yml` content when helper defaults are too broad or remove
intentional navigation.

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

After workflow changes, run the complete
[workflow audit](../../github-actions-hardening/SKILL.md#checks) required by
`$r-ci-hardening` rather than duplicating its individual tool commands here.

## Build Notes

`pkgdown::build_site()` may need network access for external JavaScript assets,
CRAN package metadata, and CRAN news timeline metadata. DNS errors for hosts
such as `cloud.r-project.org` or `crandb.r-pkg.org` are sandbox/network
evidence; if the build matters, request approval and rerun with escalation.

In restricted Codex sandboxes, set cache paths to writable temporary
directories when needed, for example `XDG_CACHE_HOME=/tmp/pkgdown-cache`. Treat
generated `docs/` output as source diff only when the repo tracks or explicitly
requests committed site output.

For a reusable local HTTP preview when CI owns deployment, keep preview output
separate from the configured deployment destination. Use a dedicated
repository-local generated directory such as `.pkgdown-preview`, ignore
`/.pkgdown-preview/` in Git and `^\.pkgdown-preview$` in `.Rbuildignore`, and
leave the deployment destination and workflow artifact paths unchanged. From
the package root, clear only that preview directory at the start of each
invocation, build it, and keep pkgdown's preview server alive in a dedicated R
process with:

```r
preview_pkgdown <- function(preview = ".pkgdown-preview") {
  unlink(preview, recursive = TRUE, force = TRUE)
  on.exit(pkgdown::stop_preview(), add = TRUE)
  pkgdown::build_site(
    override = list(destination = preview),
    preview = TRUE
  )
  repeat Sys.sleep(3600)
}

preview_pkgdown()
```

The preview server requires pkgdown's optional `nanonext` dependency. `Ctrl-C`
stops the server process but leaves the generated preview available for
inspection; the next invocation starts fresh, or the directory can be removed
explicitly when earlier cleanup is useful.

When validating pkgdown without committing generated site output, combine a
writable cache with a temporary destination:

```sh
XDG_CACHE_HOME=/tmp/r-cache Rscript -e 'local({
  dest <- tempfile("pkgdown-project-")
  build <- function() {
    dir.create(dest)
    on.exit(unlink(dest, recursive = TRUE, force = TRUE), add = TRUE)
    pkgdown::build_site(new_process = FALSE, override = list(destination = dest))
  }
  build()
  stopifnot(!dir.exists(dest))
})'
```

Use a project-specific `tempfile()` prefix when it helps identify cleanup
artifacts. Scope `on.exit()` inside a function invoked from the local expression
rather than at top level, and check for prefix-matching leftovers after
interrupted runs. Rerun with approval only when a final pkgdown result is
required.
