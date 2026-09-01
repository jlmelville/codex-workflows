# Reverse-Dependency Preparation

Use this before `revdepcheck` when setup can dominate the result: a large direct set, compiled closure, mixed CRAN
and Bioconductor run, or failure before the package under test installs. A small set with ordinary successful setup
does not need this preflight. Repository queries may need network access and isolated libraries may write beyond
the worktree, so establish authority and capacity before a long run.

## Choose The Direct Cohort

For routine CRAN updates, default to direct CRAN reverse dependencies. Put direct Bioconductor targets in a
separate lane when behavioral or API risk, or the maintainer, warrants that evidence; this is release judgment,
not a claim about CRAN requirements. Still resolve Bioconductor dependencies reached from selected CRAN targets.

Freeze direct and broader cohorts from one unfiltered inventory such as `DB <- utils::available.packages(filters =
list())`. Record direct relationship types with `recursive = FALSE`; when feasible, also evaluate
`tools::package_dependencies(PACKAGE, db = DB, reverse = TRUE, which = "most", recursive = "strong")` and classify
the additions. A package page or direct-only run proves no broader coverage; completion names the checked cohort.

## Establish The Dependency Universe

1. Fix the repository set and snapshot; enumerate direct targets and their hard closure, classifying archived or
   unavailable packages. Record the runner version and inspect its resolver. Current stock `revdepcheck` seeds each
   target with `Depends`, `Imports`, `LinkingTo`, and `Suggests`, then recurses through the first three; preserve
   unavailable names before its available-package intersection.
2. Before installation or workers, resolve every direct source tarball and record repository or official-archive
   URL and checksum. Verify archive fallback package/version identity; stop if any direct source is unresolved.
3. Inventory compiled packages and system requirements; estimate library, cache, download, quarantine, and build
   temporary capacity independently.
4. Install into an isolated resumable library in hard-dependency order with bounded timeouts, preserving completed
   layers across external repository or compiler failures.
5. Verify every closure version, then load each direct target namespace separately. Attribute repository API drift,
   toolchain incompatibility, system requirements, and archived hard dependencies to preparation.

Custom DESCRIPTION dependency parsers validate each complete comma-separated entry before extracting its name.
During development, differential-test against R's strict checker across operators and versions, repeated constraints,
trailing tokens, empty entries, and boundary whitespace; do not depend on an unexported checker at runtime.

Use radix ordering for every identity-bearing character field in content-addressed manifests. Mixed-case rows and
columns must produce identical identities and cross-validate under two collations; display ordering is exempt.

A shared unresolved dependency failure is not a clean comparison. Start only when the common universe is available
or every exclusion has bounded external attribution.

## Keep Preparation Outside The Package Source

Resolve the preparation library, package cache, downloads, quarantine, and
build-temporary directories to absolute paths and require them to be outside
the package root. An `.Rbuildignore` rule is not sufficient: a local installer
may stage the source tree before `R CMD build` applies package exclusions.

Keep only runner-owned state and the smallest required private-library seeds in
the source-tree reverse-dependency directory. Record its size before the run so
an accidental cache or preparation-library copy is visible. Launch the parent
R process, not only its children, with a spacious disk-backed `TMPDIR`; source
staging can occur before a compiler or installer subprocess exists.

## Isolate Writable Comparison State

Baseline and candidate checks may share frozen manifests and immutable,
read-only dependency artifacts. Give concurrent sides distinct writable
`HOME`, XDG cache, `TMPDIR`, package-cache, download-cache, and runner-work
roots, and record their resolved paths. Treat a collision or unexplained shared
writable path as an infrastructure failure, not a package regression or clean
comparison.

For a custom runner that executes both sides concurrently and does not already
guarantee this isolation, exercise a small fixture that makes each side write
the same default cache key. Require both writes to remain isolated before the
full run.

## Bridge Into The Runner

Do not assume the runner's per-package libraries inherit a shared preparation
library. Probe the exact baseline and development install paths. When a stock
dependency reinstall fails but a prepared copy has already been validated,
map only that dependency to the affected private libraries and retain or seed
that exact copy. Keep repository-specific compatibility patches outside this
skill and record the package-to-private-library mapping in the run handoff.
For an exact local R repository, validate every published `PACKAGES`, `PACKAGES.gz`, and `PACKAGES.rds` variant against the same manifest, or publish one validated variant and reject alternates during reuse; exercise stock `available.packages()` or `install.packages()` against the result so validation covers the index R consumes.

When exact installed package/version text is part of an artifact or manifest identity, read `Package` and `Version` from the installed `DESCRIPTION` at the already-verified package path. `packageVersion()` and `getNamespaceVersion()` are suitable for version semantics, not literal evidence, because R version objects normalize separators. Exercise this boundary with a hyphenated revision.

Before launching workers, compare each per-target check limit with retained successful preparation-build timings for that target and report the basis. Do not silently replace an explicit operator limit. After a timeout, preserve the incomplete result and rerun only affected targets in fresh writable state against the same prepared artifacts.

Before the full comparison, exercise the runner's exact local development
install with the final library layout and disk-backed `TMPDIR`. Proceed only
after that smoke check builds and loads the development package and the runner
can start a representative reverse-dependency worker.

## Extend A Completed Stock Run

Before resetting a completed run, distinguish its database, target-private
libraries, and binary cache; workers may delete private libraries while leaving
reusable archives. Record the cache root, audit exact versions and platform
compatibility, and prefer supported incremental addition when only direct
targets changed.

Exclude preserved caches from live discovery and verify target count and install
stage before launch. Update-disable flags are not integrity boundaries: expose
artifacts read-only and isolate required metadata writes, using filesystem
enforcement for frozen evidence. Compare manifests before and after and retain
platform mount or namespace recipes in the handoff.

Treat every field used as positive compatibility evidence as an asserted lane
boundary. Generic values such as `unknown`, `unspecified`, or `default` must
not establish a shared reuse identity. Apply the rule uniformly across the
identity-field registry and test each dimension with both specific and generic
values; quarantine missing provenance or assign it a non-shared identity.

## Scale Across CI

When the dependency closure cannot fit or recover reliably on one host, freeze
one comparison manifest containing the repository snapshot, direct targets,
source artifacts and checksums, and resolved dependency versions. Baseline and
candidate jobs must use that same manifest. Keep CRAN and Bioconductor targets
in explicit lanes so cohort policy remains visible.

Partition targets into per-package or small dependency-aware shards that
install only their required closure. Preflight each shard before comparison;
fail fast within a shard when its prerequisites are broken, but disable matrix
fail-fast so independent shards continue collecting evidence. Every shard must
emit exactly one typed result for each requested target, including
infrastructure-failure and not-checked outcomes, and upload its result and logs
unconditionally.

Aggregate against the frozen requested-target set. Reject missing, duplicate,
or incomplete results and any baseline-versus-candidate pair that lacks an
attributable outcome; a shared setup failure is not an unchanged package.
Exercise the workflow on a small representative cohort before scaling it. Use
the [R CI guidance](../../r-ci-hardening/references/github-actions.md) for
workflow permissions, action pins, checkout credentials, and other GitHub
Actions hardening rather than duplicating those rules here.

## Completion Evidence

Report the selected cohorts, repository snapshot, direct-source URL and
checksum manifest, direct and closure counts, unavailable packages,
system-requirement findings, external storage paths and capacity, verified
versions, isolated namespace-load results, private-library seed mapping,
side-specific writable paths, in-tree footprint, and exact development-install
smoke result. For sharded runs, also retain the comparison manifest, shard
membership, typed per-target results, unconditional logs, and aggregate
cardinality check. Keep baseline and candidate package outcomes separate from
preparation and infrastructure failures.
