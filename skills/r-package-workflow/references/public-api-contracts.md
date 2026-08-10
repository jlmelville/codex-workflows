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
