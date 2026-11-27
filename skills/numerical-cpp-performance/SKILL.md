---
name: numerical-cpp-performance
description: Write or evaluate performance-sensitive numerical C++ loops. Use when reduction order, data layout, SIMD, or GCC and Clang code generation could change correctness or throughput, or when deciding whether a kernel speedup improves the caller.
---

# Numerical C++ Performance

Start with the operation people run. Identify its hot caller, representative input shapes,
and the result that must survive the change. A dot product used to rank nearly tied scores
can meet a distance tolerance while changing the selected item. Choose the relevant test
of success before using timings to choose an implementation.

## Choose a source change

Start with ordinary loops that expose independent work. Interleaving several outputs can
reuse one input load while preserving each output's addition order. Splitting one sum among
lanes changes the reduction tree. Vary one of these decisions at a time. For unrolling,
fusion, FMA, caching, sparse branches, tails, or packed data, choose a diagnostic from
[source constructs](references/source-constructs.md).

For bitwise compatibility, compare baseline and candidate within each supported build mode
that exercises the changed arithmetic. For an accuracy contract, use a reference of suitable
precision and measure the downstream decision or quality. Include inputs that
distinguish the implementations, such as signed cancellation, close ties, short rows and
incomplete batches. Compare intermediate values before normalization or rounding can hide
a difference.

## Explain a compiler difference

Replay the production kernel on the same inputs in the same order. Preserve access locality,
batch fill, tails and output use. Consume and check results outside the timed region, and
verify repeated work survives optimization. A cache-resident replay answers a different
question from a stream of distinct rows.

When GCC and Clang disagree, compare baseline and candidate with each compiler on one CPU.
Match target ISA, optimization and floating-point settings, and record the actual compiler
versions. Then test the release configuration on each deployment target relevant to the
decision. Cross-compilation can explain instruction selection. Translated execution measures
the translation environment. Use [compiler inspection](references/compiler-inspection.md)
to identify the executed loop and interpret the instructions that differ.

## Decide whether to ship

- Estimate the opportunity from the caller's profile. If a serial kernel occupies 20% of
  elapsed time, doubling its speed could save about 10% overall with the same work and all
  other costs fixed. For parallel work, look for time on the critical path. A fraction of
  summed worker cycles can differ substantially from a fraction of elapsed time.
- Time the public operation on clean release builds with representative inputs, worker
  counts and required quality. Include preparation, conversion, allocation and scheduling
  whenever callers pay for them. Warm both variants for steady-state use. Measure first-call
  cost separately if that is the user workload.
- Pair runs by input or seed, alternate or randomize variant order, and use a quiet host.
  Retain paired times and quality, report the typical **absolute** saving and relative change,
  and show spread and consistency. For nondeterministic output, establish baseline repeat
  variation. Distinguish an unresolved difference from a repeatable regression.
- If public and kernel results disagree, count calls or units of work and time the affected
  stage in a separate diagnostic run. A rounded score may change how much work the algorithm
  does. Use uninstrumented wall time for the final comparison.

Give a decision for the measured workloads and targets. State the revisions and settings,
what changed in the machine loop, the numerical or quality result, the paired public effect
and any material gap in coverage. If only the kernel was measured, keep the end-to-end
question open. A compiler-specific path earns its maintenance cost when it adds a repeatable
public benefit over the best simple portable form and its fallback has also been exercised.
