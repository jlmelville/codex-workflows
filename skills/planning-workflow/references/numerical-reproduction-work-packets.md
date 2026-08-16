# Numerical Reproduction Work Packets

Use this reference when reproducing a layered numerical research method whose
failure could arise from transcription, solver algebra, operators, geometry,
regularization, estimated intermediate fields, or the published finite model.

## Decompose Before Tuning

Inventory the defining equations, solver, kernel scale, graph topology,
regularization, intermediate-field estimator, sampling and noise regime, and
finite objective. Give each phase one causal question, hold every other layer
fixed, name the local invariant that answers it, and predeclare its stop gate.
Plots and global association are supporting evidence, not substitutes for
local residuals or compatibility conditions.

## Oracle Ladder

Move from the most algebraic component outward:

| Phase | Controlled witness | Gate |
| --- | --- | --- |
| Equation equivalence | Independent transcription or residual identity | Stop on algebra mismatch |
| Minimal one-dimensional oracle | Exact geometry and intermediate fields | Stop on solver or sign failure |
| Structured multidimensional oracle | Exact grid, graph, and fields | Local invariants must survive dimension |
| Kernel and regularization controls | One parameter family at a time | Continue only after scale is identified |
| Unstructured oracle | Exact fields on irregular samples | Separate geometry from estimation |
| Graph corruption | Controlled topology defects | Attribute sensitivity before repair |
| Estimated intermediate fields | Fixed verified downstream pipeline | Stop if the estimator violates its own preconditions |
| Sample and noise scaling | Predeclared bounded matrix | Limit claims to the exercised regime |

Record negative results in the active plan so later work cannot reopen a ruled-
out cause without new evidence. An outcome-dependent gate should say whether to
repair the current reproduction, stop because an upstream precondition failed,
or start a separately identified method-development decision.

## Hard-to-Soft Constraint Closure

When a finite method replaces a hard constraint with a quadratic penalty,
construct or characterize the constrained limit before tuning the multiplier.
First validate that the constraint operator represents the intended continuum
object; a finite stencil's exact nullspace may be smaller than the continuum
kernel.

Diagnose the penalty where the optimizer is decided. Track overlap with the
constrained solution, constraint and base energies, the relevant eigengap,
smallest positive penalty modes, and low-mode Rayleigh-quotient crossings.
Whole-operator norm matching does not prove that the constraint is active in
the low spectrum.

Use this outcome table:

| Observation | Decision |
| --- | --- |
| Constrained limit fails | Stop; repair algebra, operator, or upstream geometry |
| Constraint operator violates its oracle | Stop before stronger enforcement |
| Constrained limit works but finite penalty does not | Run a bounded diagnostic continuation |
| Only an isolated large multiplier works | Do not promote it as a default |
| A predeclared finite regime matches the limit | Continue to downstream robustness checks |

Label continuation explicitly as diagnosis or parameter selection. Do not turn
an unsuccessful reproduction into a newly invented method without opening a
separate decision, evidence question, and plan boundary.
