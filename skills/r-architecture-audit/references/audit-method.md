# R Architecture Audit Method

Use this procedure to turn the mapper's static inventory into a bounded
architecture judgment. The goal is to identify where human review is valuable
and which structural claims survive source confirmation.

## Read The Structural Map

The mapper recognizes conventional top-level assignments in `R/`, obtains
function-aware global references with `codetools` when available, and also
retains references where an internal function is passed as a value. It derives
roots from explicit namespace exports, S3 registrations, export patterns, and
package load hooks. Its report contains:

- `functions.tsv`: active top-level functions, source extent, public-root and
  reachability status, complexity, graph degree, component, and test coupling;
- `edges.tsv`: conservative internal function and higher-order references;
- `file-coupling.tsv`: cross-file edges aggregated by source and target file;
- `sccs.tsv`: recursive components, including the files they cross;
- `private-test-coupling.tsv`: direct parsed references from tests to
  non-exported functions; and
- `diagnostics.tsv`: duplicate definitions and dynamic constructs requiring
  manual review.

Review both extremes: large reachable components may expose responsibility
coupling, while mutually referring unreachable functions may expose an entire
stranded subsystem that a definition-only search misses.

## Confirm Reachability Claims

For each deletion candidate, search its exact definition and references across
the complete repository, including tests, vignettes, scripts, configuration,
generated files, and ignored development material when relevant. Inspect:

- `get()`, `assign()`, `do.call()`, formula or string dispatch, registries, and
  option-driven lookup;
- S3, S4, R6, native registration, package load hooks, and generated wrappers;
- `Collate` or other source-order behavior and duplicate top-level bindings;
- callbacks passed through lists, environments, closures, or external tools;
  and
- documented or supported private entry points used outside the package.

Classify candidates as confirmed unreachable, test-only, dynamically reachable,
or unresolved. Delete only after the supported consumer boundary is clear.

## Trace Boundaries And Values

Choose representative public operations rather than tracing every function.
For each route, record:

| Boundary | Questions |
| --- | --- |
| Input ownership | Is the value user-, package-, callback-, or tool-owned? |
| Validation | Is it validated once at ownership transfer or repeatedly afterward? |
| Persistence | Which values cross files, sessions, caches, or process boundaries? |
| External work | Which function actually launches, queries, or mutates an external system? |
| Consumption | Which branch, output, or side effect changes because of the value? |

Then trace representative modes, fields, and configuration values beyond
function reachability. Distinguish construction, validation, hashing,
serialization, testing, branching, output, and external-effect uses. A mode or
field that is only validated, hashed, serialized, or tested may preserve data
shape without driving production behavior; confirm its consumers before calling
it live or dead.

Repeated validation or hashing of package-owned immutable values is a possible
trust-boundary smell, not automatically wasted work. First establish whether
the value can change, whether corruption must be detected at that boundary, and
whether the consumer is independently supported.

## Interpret Structure Proportionally

Aggregate function count, source extent, complexity, and cross-file edges by
responsibility, not merely by file. Use the results to select reading order:

- a multi-file strongly connected component suggests coupled responsibilities
  worth tracing together;
- a high-complexity validator may be justified by a large public state space;
- many private tests can indicate essential safety coverage or a stranded
  private product surface; and
- a large unreachable component deserves confirmation before any broader
  modularity proposal.

Do not turn thresholds into pass/fail gates. Compare structural cost with the
size of the public API, operator path, supported variants, safety boundaries,
and demonstrated consumers.

## Report Shape

Lead with the owner's architecture question and a compact map of the public
surface. Then report:

1. principal public routes and responsibility boundaries;
2. cross-file components and complexity concentrations;
3. confirmed, test-only, dynamic, and unresolved reachability findings;
4. value-level variants or fields without production consumers;
5. direct private-test coupling and what behavior those tests protect; and
6. recommendations ordered by confidence and reversibility.

Keep deletion candidates separate from design seams. A useful report may
recommend deletion, consolidation, a later bounded refactor, or no structural
change.
