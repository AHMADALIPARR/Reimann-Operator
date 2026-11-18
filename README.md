# Reimann-Operator

The Riemann Hypothesis Formalized as a consequence of Self-Adjoining of a dirac-type operator on the non commutative geometry of the Adele's.

## Lean Formalization

A Lean 4 formalization of the Connes–Berry–Keating approach is in `lean/RiemannDiracOperator.lean`.

### Building

Requires Lean 4 + Lake + Mathlib (pinned to v4.14.0).

```bash
# Install elan if needed, then:
lake update
lake exe cache get   # download prebuilt Mathlib
lake build
```

The project uses `lakefile.toml` and `lean-toolchain`.

## Other Components

- `asp/` — Clingo Answer Set Programming constraints
- `futhark/` — GPU kernels for candidate arrays and pruning
- `torch/` — PyTorch spectral / entropy / candidates
- `owl/` — OWL 2 DL ontology + bridge to ASP
- `dspy/` — DSPy research engine
- `klong/` — Klong SoA interchange
