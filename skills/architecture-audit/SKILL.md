---
name: architecture-audit
description: Audit code architecture or review a diff for simplification, modularity, bloat, dead code, and coupling. Use for structural reviews before cleanup; skip routine implementation and correctness-only reviews.
---

# Architecture Audit

Produce an evidence-backed architecture judgment and the smallest useful simplifications. Static
metrics guide investigation; they are not quality scores or automatic refactoring verdicts.

For R packages, also read [r-architecture-audit](../r-architecture-audit/SKILL.md) for package roots,
dynamic consumers, and mapping tools. That extension uses this shared contract; read each once.

## Scope And Authority

Start from the owner's question, supported public surface, revision, and worktree state. Choose the
requested scope:

- **Diff review:** inspect the change against its stated base, then follow affected callers,
  contracts, and dependencies far enough to assess it. Separate pre-existing debt from new burden.
- **Repository audit:** map public entry points and representative operations across responsibility,
  state ownership, persistence, and external-process boundaries. Include tests, documentation,
  configuration, generated code, scripts, and active plans where they establish consumers or intent.

An audit request authorizes inspection and reporting. Apply changes only when implementation is
also requested; honor implementation authority already given in the conversation. Hand a broad
accepted refactor to `$planning-workflow` and the relevant implementation workflow.

## Confirm Consumers

Cross-check function-aware references with repository-wide search. Static absence is a deletion
candidate, never proof of dead code. Inspect dynamic dispatch, reflection, registries, callbacks,
load hooks, generated calls, native entry points, configuration lookup, and supported external use.
Classify candidates as confirmed unreachable, test-only, dynamically reachable, or unresolved;
state the consumer boundary that supports the classification.

Trace values as well as functions: construction, validation, hashing, serialization, and tests do
not by themselves establish a production consumer. Read
[boundary-and-value-tracing.md](references/boundary-and-value-tracing.md) when modes, fields, repeated
validation, or persistence complicate the judgment.

## Judge Simplifications

- Compare structural cost with supported operations, variants, ownership boundaries, and demonstrated
  consumers. A large validator may reflect a large public state space. Cycles, one-caller layers,
  single-implementation interfaces, and private-test coupling identify reading targets; each may
  still protect a meaningful responsibility or contract.
- Look for confirmed stranded branches, behaviorless variants, duplicate implementations, and unused
  flexibility before proposing a new abstraction. Separate responsibilities from filenames: a file
  split alone does not reduce coupling.
- Before retaining bespoke machinery or adding a dependency, inspect existing project facilities,
  standard libraries, and platform features. A replacement qualifies only if it satisfies the
  required behavior on supported runtimes, including error handling, state ownership and independence
  between instances, persistence, resource costs, and applicable accessibility or numerical contracts.
  Fewer lines or dependencies are not evidence of equivalence.
- Recommend focused behavior checks for a proposed replacement using the project's validation tools.
  If equivalence remains unproven, identify the missing witness and label the proposal conditional.
  Do not report hypothetical savings as verified outcomes.
- Prefer the smallest change that removes a demonstrated maintenance burden. A small adapter can
  preserve a useful contract; deletion, consolidation, deferral, and no change are all valid outcomes.
  When a bounded shortcut is justified, state its supported limit and observable revisit condition
  in the relevant contract comment or existing plan if implementation is requested.

## Report

Lead with the owner's question and the supported conclusion. For a repository audit, include a
compact map of public routes, responsibilities, coupled components, and complexity concentrations.
For a diff, focus the map on affected boundaries.

For each actionable finding, give the location, consumer evidence, proposed simplification,
behavior that must survive, confidence, and necessary verification. Separate confirmed deletion
candidates, design questions, and justified existing complexity. Explain what private tests protect
before recommending changes to their targets. Rank actions by maintenance burden removed,
confidence, and reversibility, and state unresolved consumers and inspection limits.
