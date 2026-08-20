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

## Conditions And Method Decisions

Name a Boolean for its exact truth set. When a primitive mathematical condition
and method-specific acceptance can diverge, represent and name them separately
rather than naming the composed decision after the primitive condition. Exercise
equality, endpoints, exterior values, extra gates, and policy precedence wherever
they can make the two decisions coincide or diverge.

## Transition Topology And Sharing

Before consolidating related methods behind one engine, inventory callback
cardinality per transition, nested search or repair loops, conditional extra
proposals, endpoint identity, and fallback timing. Share data, evaluators,
policies, and safeguards whose contracts match. Keep a method-specific engine
when strategy callbacks would hide resource ownership or make one logical
update conceal a callback-producing loop.

## State Ownership And Transition Decomposition

Before restructuring a transition, classify each field as canonical state,
derived measure, local proposal metadata, or compatibility-only duplication.
Keep complete records in one canonical mathematical domain and derive reversible
transforms, bounds, and proposal-local measures where they are consumed.

Separate pure case classification and proposal calculation from endpoint or
state mutation and from numerical safeguarding. Join them with a concise
orchestrator only when it makes those boundaries clearer, and keep callback
ownership plus termination precedence visible in the resource-owning loop.
Gate the refactor with transition invariants, exact traces, callback counts, and
the complete owning-algorithm result; structural cleanup alone is not evidence
of behavior neutrality.

## Failure Results Carry State

Treat transition status and transition progress separately. A helper that has
consumed callbacks or completed valid updates must return its latest valid state
on both success and failure, and its caller must adopt that state before
termination. Keep public fallback selection authoritative across all observed
candidates. Pair a narrow transition invariant with an owning-algorithm result,
because central finalization can mask discarded helper state and a helper-only
test can miss stale outer selection.

When a nested helper returns a safe no-op or fallback after non-success,
preserve its termination reason and resource use far enough for the owning loop
to classify the outcome. Do not let an outer tolerance rule relabel a fallback
caused by local exhaustion or recovery failure as ordinary convergence. Test
the accepted state or step, inner reason and callback counts, outer precedence,
and a genuine stationary control together.

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
