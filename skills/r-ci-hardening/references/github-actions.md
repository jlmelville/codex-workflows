# Hardened GitHub Actions Patterns for R Packages

## General

- Use full-length SHA pins for all `uses:` entries.
- Add a comment near pinned actions: `Pinned to a full-length commit SHA for
  immutability; Dependabot updates this reference.`
- `${CODEX_HOME:-$HOME/.codex}/skills/r-ci-hardening/scripts/audit-actions.sh`
  checks for nearby comments in offline mode. When the human-readable action
  version comment is in doubt, run the tag comment checker in `--require-tag`
  mode first, then use `--verify-remote` only when remote tag verification is
  worth the network request.
- Run `actionlint` before pinning existing workflows when practical. If it
  rejects an action major as obsolete, such as `actions/checkout@v3`, upgrade
  to a supported major before resolving and pinning the tag commit. Record why
  the major changed so the pin does not preserve an already-broken action.
- Set `persist-credentials: false` for checkout.
- Prefer `permissions: contents: read` at workflow top level.
- Put write permissions only on deploy or publish jobs.
- Run `actionlint` and `zizmor .github/workflows`; use `uvx zizmor` when
  `zizmor` is not installed.

## R Setup

Use the same pinned SHA for `r-lib/actions` actions in a workflow when possible:

```yaml
- uses: r-lib/actions/setup-r@<full-sha>
  with:
    use-public-rspm: true
- uses: r-lib/actions/setup-r-dependencies@<full-sha>
```

## Optional Dependency Coverage

When one `Suggests` package is intentionally unavailable, do not let an ignore
rule hide all optional-path coverage. Use explicitly named jobs with distinct
dependency modes:

- `hard-only` uses `dependencies: '"hard"'` to exercise the package without
  suggested dependencies.
- `available-optional` uses `dependencies: '"all"'`, lists an unavailable
  suggestion as `<package>=?ignore` in `extra-packages`, and sets
  `_R_CHECK_FORCE_SUGGESTS_: false` only where that exception is intentional.

After dependency setup, make the available-optional job fail when any expected
installable suggestion is absent, for example with `requireNamespace()` checks.
Log the ignored package and rationale beside the exception so the reduced
coverage is visible in the job output. `actionlint`, zizmor, and pin audits
validate workflow structure, not hosted dependency resolution; require a
GitHub-hosted run before claiming this matrix is exercised.

## External Source Health

For packages that download external datasets or assets, keep endpoint health
monitoring separate from pull-request tests and `R CMD check`. Use a dedicated
read-only workflow with `workflow_dispatch` and a low-frequency schedule.
Scheduled runs should be advisory by default; a manual input may opt into
strict failure when a maintainer wants a hard availability check.

- Probe a curated manifest of canonical download assets instead of scraping
  README, article, or citation links.
- When the manifest repeats package downloader defaults or URL constants, run
  a cheap local preflight before network work. Check required fields, empty or
  malformed values, duplicate asset identities and URLs, and correspondence
  with source-derived expected URLs so the manifest cannot silently become a
  second source of truth.
- Try `HEAD` first, then fall back to a one-byte range GET for servers that do
  not implement `HEAD` reliably. Use short timeouts and no retries by default;
  allow at most one bounded retry when the host warrants it.
- Pin actions, retain read-only permissions, disable persisted checkout
  credentials, and publish an endpoint-status table in the step summary.

Treat unreachable sources as upstream service state, not package-regression
evidence. Validate workflow structure and exercise parser or manifest behavior
without network access; only a live probe can establish current reachability.

## R CMD Check Vignettes

Static workflow checks do not validate the package semantics of
`r-lib/actions/check-r-package` inputs. When a workflow intentionally skips
vignettes, especially PDF vignettes, check both `rcmdcheck` layers:

- `with.args` passes arguments to `R CMD check`.
- `with.build_args` passes arguments to `R CMD build`.

If the policy is "do not build vignettes" and no `inst/doc` output is expected,
use this shape:

```yaml
- uses: r-lib/actions/check-r-package@<full-sha>
  with:
    args: 'c("--no-manual", "--ignore-vignettes")'
    build_args: 'c("--no-manual", "--no-build-vignettes")'
```

Validate the exact action inputs locally when diagnosing failures:

```sh
Rscript -e 'rcmdcheck::rcmdcheck(args = c("--no-manual", "--ignore-vignettes"), build_args = c("--no-manual", "--no-build-vignettes"), error_on = "never")'
```

Treat `--no-build-vignettes` in `args` without matching `build_args` as
suspicious: it can leave `R CMD build` free to rebuild vignettes while
`actionlint`, `zizmor`, and action-pin audits still pass.

## Pkgdown

When `usethis::use_pkgdown_github_pages()` rewrites a pkgdown workflow, keep
useful remote Pages/homepage side effects but restore the hardened workflow
shape below. Confirm publishing state through `$r-docs-pkgdown`; actionlint,
zizmor, and SHA audits do not prove that GitHub Pages is enabled or that the
repo homepage points at the pkgdown site.

Hardened shape:

```yaml
name: pkgdown

permissions:
  contents: read

concurrency:
  group: pkgdown-${{ github.event_name != 'pull_request' || github.run_id }}

jobs:
  build-site:
    runs-on: ubuntu-latest
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@<full-sha>
        with:
          persist-credentials: false
      - uses: r-lib/actions/setup-pandoc@<full-sha>
      - uses: r-lib/actions/setup-r@<full-sha>
        with:
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@<full-sha>
        with:
          extra-packages: any::pkgdown, local::.
          needs: website
      - name: Build site
        run: Rscript -e 'pkgdown::build_site_github_pages(new_process = FALSE, install = FALSE)'
      - name: Upload site artifact
        if: github.event_name != 'pull_request'
        uses: actions/upload-artifact@<full-sha>
        with:
          name: pkgdown-site
          path: docs
          if-no-files-found: error

  deploy-site:
    if: github.event_name != 'pull_request'
    needs: build-site
    runs-on: ubuntu-latest
    permissions:
      contents: write # zizmor: ignore[undocumented-permissions] required to publish docs
    steps:
      - uses: actions/checkout@<full-sha>
        with:
          persist-credentials: false
      - uses: actions/download-artifact@<full-sha>
        with:
          name: pkgdown-site
          path: docs
      - uses: JamesIves/github-pages-deploy-action@<full-sha>
        with:
          clean: false
          branch: gh-pages
          folder: docs
```

## Coverage

- Keep `GITHUB_PAT` only where needed.
- Prefer Codecov tokenless public upload only when appropriate.
- Add `.covrignore` only for intentional coverage exclusions.

## Dependabot

Use:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

Extra settings such as cooldown and PR limits are fine when already used across
reference repos.
