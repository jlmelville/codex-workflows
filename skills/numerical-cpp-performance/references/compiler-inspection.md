# Inspect the code that ran

Locate the hot caller in a release profile or the runtime dispatch path. For an inlined
template, find the caller containing the instructions. Record the binary, revision, compiler
identity (`--version`), target, feature macros and effective flags. On macOS a command named
`g++` can invoke Apple Clang. Check the invoked driver.

## Get comparable reports

Start with the actual compile command from a verbose build or compilation database. Use its
working directory, includes, defines, C++ standard, ISA and floating-point flags. Add the
diagnostic options for the translation unit that instantiates the hot path. Use separate
outputs for each compiler and variant. These example commands assume the build's compile
flags are in a response file named `release.rsp`, and `kernel.cpp` instantiates the kernel.
Substitute the project's arguments or the compiler's equivalent flags.

```sh
g++ @release.rsp -fopt-info-vec-all -S kernel.cpp -o gcc.s 2>gcc.vec
clang++ @release.rsp -Rpass='(loop-vectorize|slp-vectorizer)' \
  -Rpass-missed='(loop-vectorize|slp-vectorizer)' \
  -Rpass-analysis='(loop-vectorize|slp-vectorizer)' \
  -S kernel.cpp -o clang.s 2>clang.vec
```

Find the source location in the report and match it to the loop in assembly. Loop
vectorization can pack successive iterations. Superword-level parallelism (SLP) can pack
independent straight-line expressions even after unrolling. Different loops and clones in
the same function may receive different remarks. [GCC optimization reports](https://gcc.gnu.org/onlinedocs/gcc/Developer-Options.html) · [LLVM vectorizers](https://llvm.org/docs/Vectorizers.html)

## Read the release binary

Inspect the linked library or executable used for timing, especially with link-time
optimization, inlining or runtime ISA dispatch. Set `binary` to its path and choose the
command for the host. If symbols were stripped, use matching debug symbols or the sampled
module-relative address. A standalone wrapper is a useful probe after confirming it emits
the same hot loop. [LLVM disassembly options](https://llvm.org/docs/CommandGuide/llvm-objdump.html)

```sh
# GNU binutils on Linux
objdump -d -C "$binary" > linked.asm

# Apple command-line tools on macOS
xcrun llvm-objdump --disassemble --demangle "$binary" > linked.asm
```

Read from the loop header through the branch back to it, then inspect the reduction and
cleanup. Compare baseline and candidate for the compiler where timing changed.

| Question | Evidence in the executed loop |
| --- | --- |
| How many elements does each instruction process? | On x86, distinguish `mulps` / `vmulps` from `mulss` / `vmulss`. Scalar instructions also use vector registers. On AArch64, distinguish `fmla v0.4s, ...` from scalar `fmadd s0, ...`. |
| What lives across iterations? | Follow the accumulator through one back edge. Check for stack loads/stores inside that loop, repeated row-pointer loads, and register-to-register updates. Stack traffic confined to the prologue has a different cost. |
| Where is the dependency chain? | Follow the adds and horizontal reduction. Packed multiplies can feed a serial scalar sum. Check which operations fuse in the body and the epilogue. |
| Which path handles the actual inputs? | Find runtime alias or length checks, scalar cleanup, early exits and calls such as `fmaf`. Use the input widths, addresses or sampled instruction locations to identify the path taken. |

Tie the observed instruction change to a fixed-input timing. If several explanations fit,
try one diagnostic change, such as loop peeling alone, on the same input. Record the loop
excerpt and build flags alongside the timings so another reviewer can test the explanation.
