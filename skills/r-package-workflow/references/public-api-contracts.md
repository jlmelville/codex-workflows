# Public API Contracts

Use this when an R package change affects API naming, public diagnostics,
runtime conditions, or progress messages.

## Names At The Call Site

Before finalizing new or renamed functions, helpers, metrics, or result fields,
review each name at its call site without opening the definition and read public
fields as a consumer would. Keep names literal and discoverable, let verbs reveal
side effects such as signaling, preserve contract-relevant qualifiers, and
retain package or subsystem prefixes only when they improve disambiguation or
searchability.

## Behavior-Neutral Private Renames

Before renaming a private identifier, classify every matching occurrence by
contract. Rename private definitions, locals, and mechanical call sites;
preserve exported signatures and formals, public result or list fields,
and generated help. Classify generated wrappers and filenames separately rather
than assuming every change to either surface is public. An internal identifier
can share a token with a public field, so do not treat a global substitution as
proof that the boundary stayed stable.

For a Boolean rename, compare the proposed name with the exact predicate rather
than one recognizable term inside it. Use a truth table or a counterexample at
equality, endpoint, and additional-gate boundaries when those cases can change
the result. For a shared private prefix, mechanically inventory every anchored
definition first, then classify each returned abstraction and side effect—for
example factory, policy builder, state initializer, predicate, or mutator—before
choosing common vocabulary.

An intentional rename of a registered but unexported native entry point may
change generated wrappers and registration symbols without a compatibility
alias when package policy explicitly treats direct access as unsupported and a
consumer search finds no contrary evidence. Regenerate twice, inspect the diff
for the intended names with unchanged arities and signatures, and verify the
loaded public exports, formals, result fields, and diagnostics.

Classify source filenames by how they are addressed. Preserve generated and
conventional package files and paths named by `Collate`, tooling, source calls,
documentation workflows, or external consumers. An ordinary internal R source
file may be renamed after those checks, but reload the package and run its tests
because a content-identical rename can still change alphabetical collation.

Work in bounded identifier families and do not add compatibility aliases for
genuinely private names. After each family, search for the exact stale token,
separate intentional preserved matches from missed private occurrences, and run
focused tests. For compiled packages, follow the generated-file workflow in
`$r-rcpp-package` whenever wrappers change. Close the combined phase with full
tests, language formatters, lint, diff hygiene, and a complete status and diff
review.

## Compatibility Baseline

Before classifying a public argument or result field as pushed, local-only, or
unreleased, resolve the actual pushed baseline and trace that field's complete
construction path there. Follow exported returns through helper-produced lists,
list merges, compiled named results, and generated boundaries; presence or
absence in the current worktree alone does not establish user availability.

When provenance changes the compatibility decision, use bounded history such
as `git log -S` or `git blame` to locate the field's introduction or prior
meaning. Assign the compatibility strategy field by field, and do not call an
indirectly assembled field local-only while any producer on the pushed baseline
remains unexamined.

## End-To-End Explainability Audit

Before declaring an exported surface coherent, reconstruct the shortest
credible beginner task from input to useful output. Before opening the
implementations, use names and formals to predict the major return shapes,
classes, side effects, and conditions, then compare those predictions with the
actual contract.

For a function whose mode selector changes behavior, make a compact matrix of
each mode's active and inactive arguments, return class, signaling, and runtime
conditions. Classify every caveat needed to keep the task narrative coherent as
a documentation gap, an API design seam, or explicitly accepted compatibility
debt. Consult recorded compatibility decisions before treating an awkward
surface as accidental or prescribing a rename.

## Equivalent Exported Workflows

When a high-level convenience loop and exported step, state, summary, or check
primitives let users perform the same operation, treat their termination cause,
status, message, runtime conditions, diagnostics, and resource accounting as a
paired public contract. Inventory both routes whenever one changes
classification or precedence, and run them from equivalent state in paired
public regressions. Any intentional divergence needs its own user-facing
contract rather than being left as an implementation accident.

## Result Identity And Diagnostic Value

When an optimizer tracks the best objective independently of the termination witness, do not assume status must redefine
the primary result. Preserve the established contract, expose explicit best and terminal identities when users need both,
and bind every value, gradient, criterion, and reason to its point. Reuse fields rather than replaying callbacks for
redundant summaries; prefer `terminal` to `convergence` when the same path represents budgets or failures.

Before retaining any public diagnostic, require a recognizable user problem, action, and interpretation rule. Default
uncertain unreleased fields to removal or internalization, and keep route-only algebra checks in focused invariants.

## Runtime Conditions

Emit warnings only for exceptional conditions that callers can act on during
the current call. Put durable resource costs for documented default behavior in
parameter documentation, keep normal default calls silent, and ensure warnings
shown beside errors are causally relevant to those failures.

## Recoverable Outcomes

When an internal typed failure may be a documented, expected public outcome,
decide explicitly whether the public boundary should propagate it or catch and
return it as a clearly typed recovery object. Return it only when callers can
inspect and resume the operation; continue to signal conditions outside that
documented recovery contract. Establish stable recovery state before starting
the fallible operation. Do not require advance opt-in solely to make an
unpredictable same-session failure recoverable; reserve explicit caller-owned
state for a longer lifecycle.

Keep the exceptional recovery shape independent of selectors for completed
domain results. Test the public paths separately:

| Path | Public result | Required witness |
| --- | --- | --- |
| Completed operation | Established successful result mode | Every supported mode retains its class and fields |
| Documented recoverable interruption | Typed recovery object independent of successful mode | Stable token or path, progress, resumability, lifecycle, and cleanup ownership |
| Other failure | Propagated condition | The boundary does not catch unrelated failures broadly |

Exercise fresh failure and rerun behavior through every successful mode
selector, including default session state and explicit caller-owned state when
both lifecycles are supported.

## Integer-Valued Controls

Before calling `as.integer()` on a public control, validate the original value
as non-complex numeric, non-missing, finite, whole, within the supported sign
contract, and no greater than `.Machine$integer.max`. Reject unsupported values
with the direct range diagnostic rather than letting coercion produce `NA`, a
warning, or an unrelated downstream failure. Exercise shared scalar, vector,
and count paths through exported APIs, asserting both the intended condition
and the absence of a coercion warning.

## Shared Controls at Consumer Boundaries

When one control appears at multiple exported boundaries, inventory each entry
point, stored configuration, and actual consumer before centralizing its
validator. Let shared storage represent the broadest intentional domain,
including documented sentinels, and enforce narrower finite or range rules at
the consumer that requires them. Treat established positive compatibility
tests as contract evidence; do not rewrite them into sentinel workarounds merely
to satisfy a newly shared validator without an explicit compatibility decision.

Classify validation by data ownership and independent support. Validate user
values once at the supported entry or first consuming boundary and validate
external callback results at first consumption. A private helper reached only
with normalized package-owned state may trust that invariant; do not preserve
malformed direct-call tests as a contract unless the helper is independently
supported. Keep non-finiteness, liveness, and recovery checks that describe
algorithm state rather than malformed input.

## Progress Messages

When progress messages are controlled by a `verbose` flag, pass the validated
value explicitly to the helpers that emit them; do not recover it from caller
frames or ambient state. Keep exported defaults silent. Capture public messages
for each interchangeable backend or input route whose diagnostic contract should
match, including suppression of ignored-default chatter.

For a wrapper-owned timestamped message contract, use a public precomputed or
cached input route when available so a chatty interchangeable backend does not
pollute the captured sequence. Remove only the known volatile prefix, then
compare the complete stable message text and ordering exactly. Keep separate
route-level tests when backend diagnostics are also part of the public contract.
