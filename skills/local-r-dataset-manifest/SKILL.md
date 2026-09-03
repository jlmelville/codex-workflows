---
name: local-r-dataset-manifest
description: Maintain James's local R benchmark dataset manifest under /mnt/e/dev/R/datasets, especially R-datasets-manifest.tsv. Use to inventory, validate, update, or choose local R benchmark datasets, saved nearest-neighbor graphs, or helpers such as loadj(), savej(), nng(), and nngi().
---

# Local R Dataset Manifest

Use this for James-local benchmark data curation. These datasets live outside
package repos and are local filesystem state, not package source.

## Default Paths

- Dataset root: `/mnt/e/dev/R/datasets`
- Manifest: `/mnt/e/dev/R/datasets/R-datasets-manifest.tsv`
- Helper definitions: targeted lines in `/home/james/.Rprofile`

These paths are WSL-local. On non-WSL machines, report an absent dataset root instead of recreating it.

When the manifest is absent but the task still needs benchmark data, check
known R-native dataset packages and relevant sibling repositories for a
canonical structured loader before parsing raw artifacts or adding a bridge.
Validate split and metadata fields, provider version or commit, acquisition URL,
and stable digests; use raw files or a foreign-language loader only as fallback.

## Manifest Contract

Each manifest row names a curated bundle:

- `file` maps to `path` basename `<file>l.Rda`.
- The `.Rda` loads exactly one object named `<file>`.
- The object is a list with `X`, `Y`, and `nn`.
- `X` is a matrix; never record or enumerate `colnames(X)`.
- `nn$idx` and `nn$dist` are both `nrow(X) x 150`.
- `nn_k` is `150`, and neighbor row counts match `nrow(X)`.

Treat broad inventories of every `.Rda`/`.Rds` file as discovery aids only. The
manifest is the curated source of truth for agents choosing benchmark data.

## Derived Feature Caches

For reusable unsupervised features, fit the declared transform on the full source and cache its scores before deterministic
benchmark row selection. Record source and cache digests, transform settings and order, seed, and dependency version;
validate one finite, dimensioned object in isolation. Keep an incomplete bundle out of the manifest, and fit on training
rows when evaluation roles make full-data fitting leakage.

## Workflow

1. Read the current manifest first:

   ```sh
   column -t -s $'\t' /mnt/e/dev/R/datasets/R-datasets-manifest.tsv
   ```

2. If helper behavior matters, inspect only relevant `/home/james/.Rprofile` definitions such as `loadj()`, `savej()`, `nng()`, or `nngi()`.
3. Validate all rows before changing the live manifest:

   ```sh
   Rscript --vanilla "${HOME}/.agents/skills/local-r-dataset-manifest/scripts/validate_manifest.R"
   ```

4. Write proposed changes to `/tmp` first. Review the draft and failure report.
5. Replace the live manifest only after zero validation errors. Request sandbox approval for `--replace`; replacement is atomic and cannot use `--max-rows`.

   ```sh
   Rscript --vanilla "${HOME}/.agents/skills/local-r-dataset-manifest/scripts/validate_manifest.R" --replace
   ```

Load data in isolated R environments, never `.GlobalEnv`. If validation reports
missing files or structure mismatches, preserve the current manifest and report
all failures.
