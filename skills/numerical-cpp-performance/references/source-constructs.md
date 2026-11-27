# Source constructs worth investigating

Pick the row that explains the suspected bottleneck. Freeze the other choices while testing it.

| Construct | Small comparison | What to check |
| --- | --- | --- |
| Nested loops, fixed arrays, unrolling and template expansion | Hold the lane sums and final reduction fixed. Compare a counted feature loop, named output updates sharing one load, and explicit expansion of the features as separate changes. | Which dimension was vectorized? Do partial sums stay in registers across blocks? Does the source help both compilers on the same CPU? Repeat for the actual operator. A squared difference needs different temporaries from a product. |
| Multiple accumulators and remainder paths | Compare an ordered sum with independent lane sums only if reassociation is allowed. Vary feature width around the block size and the number of outputs around the batch size independently. | Check the horizontal reduction, scalar epilogue and leftover-output callback. Test widths below, at and just above a full block, with mixed signs. Short inputs may spend all their time in cleanup. |
| Multiply-add and contraction | Compare ordinary multiply/add under release contraction settings with explicit `std::fma` when its single rounding is acceptable. Change ISA, contraction and broader fast-math flags independently. | Look for packed or scalar fused instructions, separate operations, or a math-library call in the loop. Check cancellation and near ties. Turning contraction off for ordinary expressions still leaves the fused semantics of `std::fma`. |
| Fused passes and cached norms | Compare shared loads with the original arithmetic first. Add changed arithmetic separately. For checked copies, include a baseline that performs the same validation and preserves observable failure behavior. | An early exit can scalarize a previously packed copy. A cached norm can differ from the old value when rounding depends on the partner's sparse merge or on the scalar tail. Check stored scores, split points or selected IDs. |
| Sparse merges and conditional selection | Compare branch, conditional update and run-grouping forms on realistic overlap and run lengths. Preserve match order and the treatment of zeros and exceptional values required by the API. | A ternary can still generate a jump. Read the inner branch and measure cycles with branch misses and retired instructions. Fewer mispredictions can come with much more work. |
| Packing, quantization and ISA-specific operations | Compare the proposed representation with a well-optimized implementation at the original precision. Include packing in the timed call or amortize it over a measured reuse count. | Test partial words, accumulator range and any quality loss. Compare at matched accuracy, including extra queries or candidates needed to recover quality. |

Two measured comparisons illustrate where to draw conclusions.

- **One CPU, two compilers.** Fully expanding four dot products and eight feature lanes on
  the same x86-64 inputs took GCC 15 from 73.47 to 38.46 ms and Clang 21 from 38.16 to
  140.47 ms. Both preserved the scores. GCC kept packed accumulators in registers and Clang
  emitted scalar arithmetic. Keeping the feature loop and naming only the four output updates
  was a separate candidate worth testing.
- **One compiler comparison, two timing boundaries.** With identical source on the same
  Intel CPU, 100-feature fixed groups took 5.96 ms with GCC and 3.34 ms with Clang. Median
  one-worker graph builds took 1.953 s and 2.081 s respectively, with Clang faster on two
  of six paired seeds. Switching the compiler changed the entire binary. The kernel advantage
  was real on the replay and the public measurement gave no basis to promise it to users.
