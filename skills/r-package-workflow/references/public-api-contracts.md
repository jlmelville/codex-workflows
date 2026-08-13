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
generated wrappers and help, and filenames unless the public change is
intentional. An internal identifier can share a token with a public field, so
do not treat a global substitution as proof that the boundary stayed stable.

Work in bounded identifier families and do not add compatibility aliases for
genuinely private names. After each family, search for the exact stale token,
separate intentional preserved matches from missed private occurrences, and run
focused tests. For compiled packages, require a zero diff in generated wrappers
unless an exported signature intentionally changed; follow the generated-file
workflow in `$r-rcpp-package` when it did. Close the combined phase with full
tests, language formatters, lint, diff hygiene, and a complete status and diff
review.

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

## Public Diagnostic Value

Before retaining a public diagnostic or detailed result field, require a
recognizable user problem, a concrete action or decision, and a credible
interpretation rule such as a threshold, comparison, example, or precedent.
Default uncertain unreleased diagnostics to removal or internalization. Move
route-only or maintainer-only algebra checks into focused invariants rather than
expanding the supported result schema.

## Runtime Conditions

Emit warnings only for exceptional conditions that callers can act on during
the current call. Put durable resource costs for documented default behavior in
parameter documentation, keep normal default calls silent, and ensure warnings
shown beside errors are causally relevant to those failures.

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
