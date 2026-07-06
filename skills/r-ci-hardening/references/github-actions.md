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
