# Numerical Callback and Result Contracts

Use this reference for hard callback budgets, runtime callback validation,
bounded candidate searches, and adapters that install backend results.

## Runtime Callback Results

Inventory every direct invocation and alias, then validate an already-required
result at its first point of consumption. Do not coerce, flatten, recycle,
replay, or call a callback solely for validation. Separate type and shape from
numerical usability: a correctly shaped `NA`, `NaN`, or `Inf` belongs to the
algorithm's established non-finite policy.

For combined callback outputs, require the exact components the caller
consumes; allow extras unless the public contract forbids them. Test malformed
shapes and names, integer and double storage, shaped non-finite values, and
independent call counts.

Treat diagnostic completeness as a positive evidence claim. Validate every
required returned metadata field before comparison and derive aggregate
completeness only from affirmative `TRUE` predicates, such as `isTRUE(check)`;
do not promote `NA` merely because it is not `FALSE`. For R scalar numeric
metadata, require numeric storage, no dimensions, length one, finiteness, and
the applicable domain, integrality, and range before coercion. Preserve a valid
primary result separately when corroborating metadata is unavailable or
malformed, but keep accounting, provenance, and aggregate completeness false.
Table-test missing containers and components, dimensioned length-one values,
malformed and mismatched values, and valid zero-work branches.

## Hard Budgets and Accounting

Use independent external counters and cover zero, one, and exact allowance
across initialization, iteration, summaries, diagnostics, logging, finalization,
and stateful branches. Exercise individual and combined callback interfaces.

Select the numerical policy before deriving its evaluation allowance, and give
each policy an explicit callback cost vector. For trial cost
`(fn_cost, gr_cost)`, only nonzero components constrain individual budgets;
when a combined budget counts both callback classes, its trial cost is
`fn_cost + gr_cost`. Take the minimum applicable floored allowance. Thus an
objective-only `(1, 0)` policy is not blocked by zero gradient allowance, while
an objective-plus-gradient `(1, 1)` policy is constrained by objective,
gradient, and half the corresponding combined allowance. Test local and global
limits through the exact final permitted trial.

A cache hit is free only when its parameter and validity markers are current.
Make callback-free fallbacks explicit in the execution path or central wrapper;
do not infer that they are free from their returned value. Audit callers for
immediate value consumption after a blocked call.

Materialize every applicable terminal cause at the owning adjudication point
and choose the winner once. For a valid or otherwise non-failure transition,
classify convergence, non-finiteness, and acceptance before declaring budget
exhaustion. For a provenance-backed failed no-transition result, a reached hard
global callback budget outranks algorithm failure, and algorithm failure
outranks zero-change tolerance. Do not let a later general checker overwrite the
selected cause.

A precedence test must make every competing cause live at that same point. Arm
required history such as a prior objective value, consume the exact final
permitted callback in each relevant lifecycle phase, and cover a valid
transition with convergence and an exhausted budget, a failed zero transition
with a global-budget tie, and the same failure without that tie. Exercise every
equivalent exported workflow. Remove branch-specific production behavior when
no exported path can reach the remaining allowance.

## Budgeted Candidate Searches

Define the allowance as callbacks owned by the search, normally including
candidate evaluation and excluding a valid cached baseline. Trace parameters
and counts, and evaluate the acceptance predicate after every candidate,
including the final permitted one.

Use one validity predicate for direct and fallback candidates, covering the
complete state the algorithm consumes: parameters, objective, derivatives, and
other required metadata. Retain an observed candidate if optional metadata is
absent only when the contract explicitly permits that omission.

Do not replace unavailable numerical metadata with zero, one, infinity, or
another meaningful scalar merely to satisfy a shared interface. Propagate an
explicit unavailable value to each consumer, then disable or reject only the
stopping rule, scale transformation, or other decision that requires the
missing measurement. Pair the missing-metadata path with a supplied-metadata
control through the owning algorithm so safe finalization cannot conceal
premature termination.

Separate the primary acceptance rule from any weaker exhaustion fallback. A
fallback should be finite, actually evaluated, and strictly better when that is
the contract. Reject equality, increase, non-finiteness, unevaluated values,
and status-only success. When no valid transition occurred, return the exact
inactive or starting state and do not cache rejected candidates. A nested helper
that consumed callbacks and produced valid transition state must instead return
that latest state even when its status is failure; callers adopt it before
finalization. See
[state-machine-contracts.md](state-machine-contracts.md#failure-results-carry-state).

## Proposal Generation And Search Liveness

Treat interpolation, extrapolation, and other iterative proposal formulas as
fallible before evaluation. Check algebraic domains directly; do not guard a signed or dimensioned ratio by adding an
absolute epsilon unless a mathematically derived regularizer preserves scale, units, and sign. Require every proposal
to be finite, inside its permitted region, and representably progressive before a callback.

When a separately selected scale such as line-search alpha multiplies a direction, do not infer no progress from its
unscaled norm. Reserve a pre-search shortcut for exact vector zero; let the scaled parameter map decide representability.

Keep invalid public controls distinct from proposals derived from otherwise
valid runtime state. Reject the former at the public boundary; route the latter
through the algorithm's established numerical-failure or recovery policy. A
recovery update must be finite, distinct, and contract its bracket or otherwise advance state. If no representable
progress remains, terminate through the safe fallback rather than looping, even with an unbounded allowance.

In bracketed recovery, keep evaluated condition and fallback endpoints distinct from evolving resolution boundaries.
A failed non-finite trial may block a callback at the same parameter vector, but cannot supply conditions or fallback state.

Regress the owning algorithm rather than only the algebraic helper. Cover the
decisive algebraic degeneracies, signed denominators around zero, exact-zero and
sub-threshold nonzero directions, repeated projected non-finite parameters,
endpoint rounding, and supported unbounded allowance. Assert termination, valid callback parameters, exact counts,
and the final safe result through the exported allowance path.

## Default-Preserving Repair Experiments

Treat an exact predicate mismatch or unsafe finite-arithmetic witness as an
investigation gate, not an automatic default change. When comparison requires a
seam, make it private and default-off, vary only the disputed decision, and
first prove the local divergence.

Then use a bounded predeclared matrix to compare owning-search trajectories,
callback counts, termination and fallback behavior, and representative
optimizer outcomes. Promote a new default only against an explicit safety or
outcome criterion. If the evidence establishes only different trajectories or
occasional callback savings, preserve the supported default and close the
experiment at that narrower conclusion.

## Realized Adapter Results

Reconstruct the complete public result before installing a backend result. A
finite step, scalar summary, or success status is insufficient when the public
object requires additional realized state. Reject incomplete results without
replaying callbacks or discarding callback accounting. Pair a finite success
control with table-driven incomplete and non-finite failures.
