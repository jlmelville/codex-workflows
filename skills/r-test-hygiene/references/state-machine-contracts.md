# Numerical State-Machine Contracts

Use this reference before restructuring iterative searches, caches, resets, or
private constructors that participate in numerical state transitions.

## Rank the Oracles

Prefer evidence in this order:

1. Public safety, resource, and return-value contracts.
2. Mathematical transition and acceptance invariants.
3. Exact traces for behavior-neutral refactors.
4. Broad golden output only when narrower oracles cannot express the contract.

Capture candidate sequences, relevant scalar state, final selection, and
callback counts. A confirmed bug overrides a legacy trace: update only the bad
expectation and retain unaffected behavior. Test private helpers by invariant,
not merely by replaying their current implementation.

## Tagged Cache Entries

Treat a cached value and its iteration, version, or parameter marker as one
contract. Cover matching, stale, and missing markers, and make fixtures set the
pair together. An invalid marker means the value is unknown; selection or
restoration may therefore require a fresh evaluation.

## Reset and Reinitialization

Partition state into transient, rebuilt, and persistent fields. Cover terminal
causes, algorithm state, counters, and hooks. Compare the first operation after
reset with the same operation on a fresh instance.

## History-Bearing Identity

Preserve stable identity and ordering separately from derived roles such as
low, high, accepted, or rejected. Ties make those roles non-unique, so derive
them from current values and specify the deterministic next transition.

## Authoritative Constructors

A directly tested constructor should be the production construction boundary.
Route production through it, or remove the duplicate helper and test the path
that production actually uses. For hot paths, establish semantic oracles first
and add a benchmark gate when indirection could materially affect cost.
