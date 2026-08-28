# Reverse-Dependency Preparation

Use this before `revdepcheck` when dependency setup can dominate the result:
the direct reverse-dependency set is large, much of its closure is compiled,
the run spans CRAN and Bioconductor, or packages fail before the package under
test is installed. A small reverse-dependency set whose ordinary setup succeeds
does not need this full preflight.

Dependency acquisition and repository queries may need network access, while a
large isolated library may write beyond the package worktree. Establish the
required authority and available capacity before starting a long preparation
run.

## Choose The Direct Cohort

For a routine CRAN update, default the release gate to direct CRAN reverse
dependencies. Opt direct Bioconductor reverse dependencies into a separate
lane when the change carries behavioral or API compatibility risk, or when the
maintainer explicitly wants Bioconductor compatibility evidence. This is
release-preparation judgment, not a claim that CRAN formally requires or
forbids either cohort.

A CRAN target may still depend on Bioconductor packages. Keep repository,
cache, and dependency preparation able to resolve every dependency reached
from the selected cohort even when direct Bioconductor targets are out of
scope.

## Establish The Dependency Universe

1. Fix the repository set and metadata snapshot that the later comparison will
   use. Enumerate the exact direct reverse dependencies and their hard
   dependency closure from that same universe; classify archived or unavailable
   packages separately.
2. Before dependency installation or worker launch, resolve and download the
   source tarball for every direct target. Record its selected repository or
   official-archive URL and checksum. For an archive fallback, verify the
   tarball's package and version identity; stop before comparison if any direct
   source remains unresolved.
3. Inventory packages requiring compilation and their system requirements
   before scheduling installs. Estimate library, cache, download, quarantine,
   and build-temporary capacity independently.
4. Install into an isolated, resumable library in hard-dependency order with
   bounded per-package timeouts. Preserve completed layers so an external
   repository or compiler failure does not restart the entire closure.
5. Verify the selected version of every closure member, then load each direct
   reverse-dependency namespace in a separate process. Classify repository API
   drift, toolchain incompatibility, missing system requirements, and archived
   hard dependencies as preparation failures rather than failures caused by
   the package under test.

Do not call a baseline-versus-candidate result clean merely because both sides
share an unresolved dependency failure. Begin the comparison only after its
common dependency universe is available or every remaining exclusion has a
bounded external attribution.

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

Before the full comparison, exercise the runner's exact local development
install with the final library layout and disk-backed `TMPDIR`. Proceed only
after that smoke check builds and loads the development package and the runner
can start a representative reverse-dependency worker.

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
