# Numerical Validation

## Numeric Vector CLIs

For Python CLIs that accept arbitrary numeric vectors, add smoke tests for
negative values and scientific notation, especially when the command is called
from R or shell scripts. Avoid assuming `argparse` vector options with
`nargs="+"` will handle signed numeric tokens robustly; consider a delimiter or
CSV argument, or parse trailing tokens deliberately when the CLI needs raw
numeric vectors.

## Cross-Language Oracles

For cross-language numeric oracle comparisons, such as R/Python, Python/C++,
NumPy/Torch, or autograd checks, report both absolute and relative differences.
Accept either a meaningful absolute tolerance or a tight relative tolerance so
large-scale objectives, gradients, or Hessians do not become false formula
diffs from roundoff alone. For derivative or autograd checks, make the scalar
objective or function value match the oracle first; only interpret gradient or
Hessian diffs as derivative bugs after the scalar agrees. Keep absolute
tolerances for small or near-zero reference values.
