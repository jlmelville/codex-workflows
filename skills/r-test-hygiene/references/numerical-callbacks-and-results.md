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
immediate value consumption after a blocked call. After a permitted callback,
classify convergence, non-finiteness, and acceptance before declaring budget
exhaustion. Remove branch-specific production behavior when no exported path
can reach the remaining allowance.

## Budgeted Candidate Searches

Define the allowance as callbacks owned by the search, normally including
candidate evaluation and excluding a valid cached baseline. Trace parameters
and counts, and evaluate the acceptance predicate after every candidate,
including the final permitted one.

Use one validity predicate for direct and fallback candidates, covering the
complete state the algorithm consumes: parameters, objective, derivatives, and
other required metadata. Retain an observed candidate if optional metadata is
absent only when the contract explicitly permits that omission.

Separate the primary acceptance rule from any weaker exhaustion fallback. A
fallback should be finite, actually evaluated, and strictly better when that is
the contract. Reject equality, increase, non-finiteness, unevaluated values,
and status-only success. On failure, return the exact inactive or starting
state and do not cache rejected candidates.

## Proposal Generation And Search Liveness

Treat interpolation, extrapolation, and other iterative proposal formulas as
fallible before evaluation, even when every input is finite. Check required
algebraic domains such as nonzero denominators or admissible discriminants,
then require the proposed scalar to be finite, inside the permitted region,
and representably different from the current state or relevant endpoint in the
direction the algorithm needs. Never pass an invalid or nonprogressing proposal
to a callback.

Keep invalid public controls distinct from proposals derived from otherwise
valid runtime state. Reject the former at the public boundary; route the latter
through the algorithm's established numerical-failure or recovery policy. A
recovery update must itself be finite, distinct, and strictly contract its
bracket or otherwise advance the search state. If no representable progress is
available, terminate through the safe fallback rather than looping, even when
the evaluation allowance is unbounded.

Regress the owning algorithm rather than only the algebraic helper. Cover the
decisive algebraic degeneracies, overflow-derived proposals, endpoint rounding
with no representable interior, and a supported unbounded allowance when one
exists. Assert termination, absence of invalid callback parameters, exact
callback counts, and the final safe result. Trace the effective allowance from
the exported path instead of inferring it from private defaults.

## Realized Adapter Results

Reconstruct the complete public result before installing a backend result. A
finite step, scalar summary, or success status is insufficient when the public
object requires additional realized state. Reject incomplete results without
replaying callbacks or discarding callback accounting. Pair a finite success
control with table-driven incomplete and non-finite failures.
