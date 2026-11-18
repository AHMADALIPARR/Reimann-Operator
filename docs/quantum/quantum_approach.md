Quantum hybrid circuits in OpenQASM 3.0 and the hand-written structural & epistemic lemmas in pure Lean 4 are now collected in a single organized file:

**`quantum/sovereign_rh_quantum_encodings_and_lemmas.lean`**

That file contains:
1. Circulant–QFT block encoding (Berry–Keating stencil)
2. Periodic-diagonal LCU block encoding
3. The full set of hand-written lemmas (`SovereignRHLock` namespace) — zero `sorry`, zero custom axioms, Lean 4 core only

The individual OpenQASM sources remain in `openqasm/` for direct circuit execution, and the pure Lean lemmas also remain in `lean/SovereignRHLock.lean` for the checked build.

**Authors:** Ahmad Ali Parr and Jessica Westerhoff, SnapKitty Collective Research Team.
