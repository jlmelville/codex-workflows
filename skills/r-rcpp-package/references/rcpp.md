# Compiled R Package Reference

## Attribute Workflow

After adding, removing, or changing `// [[Rcpp::export]]` functions:

```sh
Rscript -e 'Rcpp::compileAttributes()'
git diff -- R/RcppExports.R src/RcppExports.cpp
Rscript -e 'Rcpp::compileAttributes()'
git diff -- R/RcppExports.R src/RcppExports.cpp
```

The first diff should show only the intended wrapper, registration, or signature
change. The second run should be idempotent: no new generated-file diff should
appear after rerunning `compileAttributes()`.

Do not hand-edit `R/RcppExports.R` or `src/RcppExports.cpp` to make the diff
look right. Fix the exported C++ signature or attributes and regenerate.

## cpp11 Return Conversions

For memory-sensitive cpp11 results, inspect the supported cpp11 headers rather
than assuming list construction is zero-copy. In affected versions,
`named_arg` assignment takes a container by value before converting it to an R
object, while the container `as_sexp()` conversion itself can accept a const
reference. Model the overlap among original C++ storage, any by-value
temporary, the new R payload, and auxiliary vectors.

When that temporary materially affects the bound, convert large containers
first into protected cpp11 SEXP wrappers, then add the lightweight wrappers to
the result. Verify protection semantics in the supported headers, recheck them
when the cpp11 version changes, and test allocation-component or phase-sum
formulas without claiming measured peak RSS. When exported cpp11 signatures
change, regenerate registration twice with the package's established command
and inspect the second pass for idempotence.

## C++ Language Standard

Inventory features used by hand-maintained and installed headers and select the
narrowest standard supporting the package contract. Do not rely on R's moving
default dialect or confuse dialect with minimum compiler version. Follow current
[Writing R Extensions](https://cran.r-project.org/doc/manuals/r-devel/R-exts.html#Using-C_002b_002b-code)
and keep declarations consistent, such as `SystemRequirements: C++17` with
`CXX_STD = CXX17`; `R CMD check` gives the DESCRIPTION declaration precedence.

Assess installed headers for downstream `LinkingTo` consumers separately. Check
the declared standard; a newer-dialect lane may test compatibility without
changing the release contract.

## Formatting

- Format hand-maintained C++ files with the repo's `.clang-format`.
- Do not manually format generated `src/RcppExports.cpp` unless the repo has
  explicitly decided to do so.
- Keep generated-file refresh separate from broad formatting commits so review
  can distinguish interface changes from style churn.
- Before synchronizing shared C++ across repositories, resolve the effective
  policy in each one, including explicit configs, inherited parent configs, and
  fallback behavior. Run each repository's ordinary unqualified formatter on
  the shared file, trial candidate common policies, and inspect the wider
  migration surface before selecting one explicit shared policy. Do not use
  formatter-disable markers merely to hide policy drift.
- Synchronize formatter policy and copied source as separate reviewable changes,
  then rerun the ordinary local checks and confirm the policy and shared-source
  checksums agree. When `.clang-format` is a new top-level hidden file in an R
  package, apply the
  [R package hidden-config rule](../../r-package-workflow/SKILL.md#change-discipline)
  and verify that the config is excluded from the source package.
- Use explicit target lists for clang-format when needed:

```sh
clang-format --dry-run --Werror src/distance.h src/random-dist.cpp
```

## Threading

- Use RAII joiners or established local parallel helpers.
- Capture and rethrow worker exceptions.
- Avoid using chunk end offsets as thread IDs.
- Keep RNG contracts explicit in docs/tests: same seed plus same thread count
  should be reproducible unless a different contract is documented.
- Before adding `-pthread` or another thread option, confirm that code constructs
  and joins real threads, inspect both Makevars variants, and distinguish
  compiler from linker placement. Require build evidence that contains the
  threaded implementation across the package's supported platforms; local
  Linux success or a configured but unrun service is not cross-platform proof.
  When the supported matrix already exercises the code successfully, record an
  explicit no-change decision instead of adding speculative flags.

## Mixed Random And Deterministic Routes

For one Rcpp export that combines implicit-random and supplied deterministic
branches, treat the generated wrapper's RNG scope as observable behavior. When
the deterministic route promises no RNG use, generate the export with
`rng = false` and construct `Rcpp::RNGScope` only inside the branch that uses
R's RNG. Test that deterministic calls neither advance an existing
`.Random.seed` nor create one when it is absent, then recheck the implicit
random sequence under its documented seed and thread contract.

## Removing Resource Estimators

Before removing a memory estimator, cap, preflight, or accounting report, trace
its call graph and classify each helper as policy-only or as protection for an
allocation the implementation can still attempt. Map checked addition,
multiplication, index-width, sparse-slot, dimension, and vector-size operations
to the allocation or reduction boundary they protect.

Delete modeled formulas and unused reporting, but relocate surviving overflow
and representability guards to those real boundaries rather than retaining a
dead estimator. Validate public result shape, routing, numerics, and worker
exception behavior through ordinary package paths; do not add test-only exports
merely to preserve removed accounting machinery.

## Registered Native Boundaries

Treat every entry in generated Rcpp registration and every exported
implementation as independently reachable when inventorying the boundary, even
when the public R wrapper already validates its arguments. For each routine,
identify supported public callers, trusted internal producers, deliberately
unsupported direct calls, and any explicit independent safety or threat-model
requirement. Technical callability alone does not require duplicating the
public R semantic contract.

For R-supplied counts, avoid unsigned types such as `std::size_t` in exported
signatures. Receive the value in an R-aware or signed numeric representation
that preserves invalid cases long enough to reject them. Before converting to
an unsigned or narrower internal type, require a scalar, non-missing, finite,
whole, nonnegative value within both the package's supported range and the
destination type's range.

Retain constant-time shape and representability guards before narrowing,
allocation, thread setup, or unchecked access. Before adding an element-wise
native validation pass, ask whether a supported producer can violate the
invariant, whether the package promises an independent memory-safety boundary,
and whether the check adds a pass beyond conversion or traversal the algorithm
must already perform. Fuse required range or indexing guards into that traversal
when practical; do not add an `O(n)` semantic rescan solely for unsupported
private callers.

Keep public semantic tests on exported R APIs. Add narrow direct-wrapper tests
only for retained conversion, allocation, indexing, thread, or
algorithm-integrity guards, and document the safety invariant each test owns.

Generated wrappers convert parameters before the native implementation chooses
a mode. When a public mode makes an argument inactive, normalize it to a valid
placeholder at the R boundary or route that mode to a separate compiled entry;
do not forward an otherwise invalid caller value merely because native code
would ignore it. Protect the contract with an exported regression whose value
is invalid only in the inactive mode.

When a malformed native call may trigger undefined behavior or terminate R,
probe an accepted native-boundary regression in a separate R process before the
guard exists. Move it into the ordinary in-process suite only after the native
guard makes the call safe.

## Vendored Third-Party Code

For vendored C or C++, record upstream project, version, source, and license; compare the tree, identify local
changes, and add artifact- and license-specific notices. Build and inspect the source tarball after
`.Rbuildignore`; require vendored files and applicable license, attribution, notice, and provenance to survive.
Compilation and package checks do not prove redistribution compliance; escalate ambiguous interpretation.

For small downstream changes, keep materialized compiled sources in the repository and apply ordered patches only
in maintainer refresh tooling. Pin the upstream archive and expected file identities; installation performs no
transformation. Reconstruct byte-for-byte and compare the complete namespace, rejecting missing or unexpected
ordinary and hidden files, directories, symlinks, and unsupported entries.

## Tests

- Prefer public R API tests for compiled behavior.
- If an internal compiled helper is necessary for safety coverage, document why
  it remains and remove it before release if public paths become available.
- Include too-small input, invalid metric, tie/edge cases, and thread-count
  coverage when those semantics matter.

## Check Output

Environment-specific `R CMD check` notes still require attribution and the
applicable [restricted-environment rerun](../../r-package-workflow/references/checks.md#restricted-environment-mechanics).
Record the evidence; an unresolved note permits only an incomplete or blocked handoff.
