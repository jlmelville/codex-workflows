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

## Establish The Dependency Universe

1. Fix the repository set and metadata snapshot that the later comparison will
   use. Enumerate the exact direct reverse dependencies and their hard
   dependency closure from that same universe; classify archived or unavailable
   packages separately.
2. Inventory packages requiring compilation and their system requirements
   before scheduling installs. Estimate library, cache, download, quarantine,
   and build-temporary capacity independently.
3. Install into an isolated, resumable library in hard-dependency order with
   bounded per-package timeouts. Preserve completed layers so an external
   repository or compiler failure does not restart the entire closure.
4. Verify the selected version of every closure member, then load each direct
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

## Completion Evidence

Report the repository snapshot, direct and closure counts, unavailable
packages, system-requirement findings, external storage paths and capacity,
verified versions, isolated namespace-load results, private-library seed
mapping, in-tree footprint, and exact development-install smoke result. Keep
baseline and candidate package outcomes separate from preparation failures.
