# Distinguishing Acceptance Evidence

Use these cases with the [acceptance guidance](../SKILL.md#proportionality-and-acceptance)
when a proposed check could succeed despite a plausible mistake.
Choose a fixture that distinguishes the intended behavior from that mistake.
When the distinction is non-obvious, demonstrate that the test fails for the
mistake it guards against; attribute the failure to the assertion, not broken
setup or an unavailable dependency. An ordinary test edit does not require a
staged mutation experiment or retained red transcript.

## Reported Failures

**Reported failure versus another defect:** When using a reduced or synthetic
reproducer to establish that a reported issue is resolved, check that it
preserves the conditions and distinguishing observations relevant to the
diagnosis, rather than only the symptom. Fixing a different reproducible defect
does not establish resolution of the reported issue. If the connection remains
uncertain, state what was verified and what remains unverified. Running the
supplied reproducer before and after the patch may establish the connection
directly.

## Selection And Identity

- **Current versus first:** put a stale item before the intended current item,
  and assert the selected identity. A current-first fixture lets a first-item
  implementation pass without testing freshness.
- **Related identifiers:** give an operation and its resulting resource
  deliberately unequal IDs; assert the ID appropriate to the public result.
  Equal IDs conceal a swapped field or wrong object lookup.
- **Preserved state:** seed a known-present baseline member and establish its
  presence before comparing before/after state. Two empty reads can agree even
  when discovery failed or state was lost.

## Effects And Execution

- **Forbidden work:** observe the boundary that owns the side effect. Make an
  unexpected write, network call, expensive operation, or allocation raise, or
  record calls and assert the allowed budget. Equal output cannot establish that
  forbidden work never happened. Cover every target the prohibition protects,
  including pre-existing destinations when preservation is the contract.
- **Exercised change:** pair result equality with evidence that the changed path
  ran, such as a targeted input, operation counter, or path marker. A correct
  refactor can preserve intermediate values too; numerical differences are not
  required to prove execution.

## Persistence And Recovery

Match recovery evidence to the promised boundary. Persisted progress, execution success, and domain
success are separate claims.

For resumable or checkpointed runners, cross outer process outcome, persisted completeness, and
domain status so complete rows cannot mask a failed execution. Inventory every execution-determining
input consumed after resume; mutate one representative per input class after serialization and
require incompatible state to be rejected before workers start.

When process-death recovery is promised, synchronize on a persisted completion marker, terminate
the actual child before its owning operation returns, and restart the public workflow in a fresh
process. Use execution markers to distinguish retained complete domain units from unfinished units
that may repeat. When cleanup survival is promised, remove exactly the advertised disposable state
and repeat the recovery check. Caught errors and successful serialization alone do not exercise
abrupt death; retained progress does not imply exactly-once execution.

These cases do not require resume checks for non-resumable operations with no persisted status or
post-serialization execution inputs. Ordinary error-return or save/load contracts need evidence at
those boundaries; they do not require process termination or cleanup deletion unless those recovery
guarantees are promised.

## Doubles And Real Boundaries

Install a double at the binding production code actually uses, and verify that
the intended call reached it. Pair a fast behavior matrix with a small contract
check through the real adapter or installed command when signature, option,
serialization, or dependency behavior is at risk. A permissive fake can accept
an interface the dependency rejects.

When a threshold's real inputs are impractically large, exercise `K - 1`, `K`,
and `K + 1` with cheap counts or shapes at the decision boundary. Pair that
matrix with a small real-adapter check that receives the resolved decision and
deliberately distinct arguments. Extract a pure decision helper only when scale
prevents a practical direct test.

Use the real producer when its output contract is the risk, while retaining
independently specified inputs or an independent oracle when producer and
consumer could share the same mistake. Parser and compatibility checks still
need known-good and malformed inputs independent of the implementation.

## Selection Versus Execution

When coverage depends on a runner or CI boundary, distinguish discovery,
selection, actual execution, and terminal outcome at the boundary in doubt.
A passing focused test does not prove the CI command selects it; a selected but
skipped test does not establish its behavior. Inspect the runner's report and
exit conventions rather than assuming every empty or all-skipped suite fails.
For workflow commands, conditions, and production-path triggers, use the
[CI selection check](../../github-actions-hardening/SKILL.md#ci-test-selection).
