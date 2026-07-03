# Hardened GitHub Actions Patterns for R Packages

## General

- Use full-length SHA pins for all `uses:` entries.
- Add a comment near pinned actions: `Pinned to a full-length commit SHA for
  immutability; Dependabot updates this reference.`
- Set `persist-credentials: false` for checkout.
- Prefer `permissions: contents: read` at workflow top level.
- Put write permissions only on deploy or publish jobs.
- Run `actionlint` and `uvx zizmor .github/workflows`.

## R Setup

Use the same pinned SHA for `r-lib/actions` actions in a workflow when possible:

```yaml
- uses: r-lib/actions/setup-r@<full-sha>
  with:
    use-public-rspm: true
- uses: r-lib/actions/setup-r-dependencies@<full-sha>
```

## Pkgdown

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
