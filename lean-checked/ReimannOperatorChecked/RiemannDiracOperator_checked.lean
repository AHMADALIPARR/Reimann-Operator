-- SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-SnapKitty-Opaque-1.0
-- Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab

import Mathlib.Analysis.InnerProductSpace.Spectrum
import Mathlib.NumberTheory.LSeries.RiemannZeta
import ReimannOperatorChecked.RiemannGas.ZetaTruncationProof

/-!
# RiemannDiracOperator_checked

Compiling copy of `lean/RiemannDiracOperator.lean` (the original is kept unchanged).

* `RiemannDiracOperator` keeps the three fields of the original structure:
  the operator, `self_adjoint`, and `spectral_correspondence`.
* Nontrivial zeros are `riemannZeta s = 0` with `0 < s.re < 1` (Mathlib's `riemannZeta`).
* The spectral correspondence uses the Hilbert–Pólya parameterisation `s = 1/2 + i·μ`
  over eigenvalues `μ` of the operator.
* `critical_line_of_dirac_operator` is the hard-close step: every nontrivial zero of a
  structure instance has `s.re = 1/2`. It is conditional on being given such an instance.
* `gen_dirac_lemmas N` walks the operator's powers `D^0 … D^N` and emits the level-`k`
  lemmas, each proved from the level-`k-1` lemma.
-/


open Complex ComplexConjugate Module End
open scoped InnerProductSpace

namespace RiemannDiracOperatorChecked

/-! ## Part 1: Adelic Geometry Setup -/

/-- The adelic Hilbert space, modelled as a complex inner product space. -/
structure AdelicHilbertSpace where
  carrier : Type
  [ngrp : NormedAddCommGroup carrier]
  [inst : InnerProductSpace ℂ carrier]

attribute [instance] AdelicHilbertSpace.ngrp AdelicHilbertSpace.inst

/-- Spectrum as in the original: `μ` with `D - μ I` not bijective. -/
def Spectrum {H : Type*} [NormedAddCommGroup H] [InnerProductSpace ℂ H]
    (D : H →L[ℂ] H) : Set ℂ :=
  {μ : ℂ | ¬Function.Bijective (fun v => D v - μ • v)}

/-- Nontrivial zero of ζ: a zero in the open critical strip. -/
def nonTrivialZero (s : ℂ) : Prop :=
  riemannZeta s = 0 ∧ 0 < s.re ∧ s.re < 1

/-- `⟪A u, v⟫ = ⟪u, A v⟫` for all `u v`. -/
def SelfAdjointRel {H : Type*} [NormedAddCommGroup H] [InnerProductSpace ℂ H]
    (A : H →L[ℂ] H) : Prop :=
  ∀ u v, ⟪A u, v⟫_ℂ = ⟪u, A v⟫_ℂ

/-! ## Part 2: The Dirac Operator Structure -/

structure RiemannDiracOperator (H : AdelicHilbertSpace) where
  operator : H.carrier →L[ℂ] H.carrier
  self_adjoint : ∀ u v, ⟪operator u, v⟫_ℂ = ⟪u, operator v⟫_ℂ
  spectral_correspondence : ∀ s : ℂ,
    nonTrivialZero s ↔
    (∃ μ : ℂ, HasEigenvalue (operator : H.carrier →ₗ[ℂ] H.carrier) μ ∧ s = 1/2 + I * μ)

/-! ## Part 3: Self-adjoint operators have real eigenvalues -/

theorem eigenvalue_im_eq_zero {H : Type*} [NormedAddCommGroup H] [InnerProductSpace ℂ H]
    (A : H →L[ℂ] H) (hA : SelfAdjointRel A) {μ : ℂ}
    (hμ : HasEigenvalue (A : H →ₗ[ℂ] H) μ) : μ.im = 0 := by
  have hsym : (A : H →ₗ[ℂ] H).IsSymmetric := fun u v => hA u v
  have h := hsym.conj_eigenvalue_eq_self hμ
  exact Complex.conj_eq_iff_im.mp h

/-- The step the original reaches with `λ = s - 1/2`: a real `λ` gives `s.im = 0`. -/
theorem im_zero_of_real_shift (s μ : ℂ) (hμ : μ.im = 0) (h : μ = s - 1/2) : s.im = 0 := by
  subst h
  simpa using hμ

/-! ## Part 4: The Hard-Close Theorem -/

theorem critical_line_of_dirac_operator
    (H : AdelicHilbertSpace) (D : RiemannDiracOperator H) (s : ℂ)
    (h_zero : nonTrivialZero s) : s.re = 1/2 := by
  obtain ⟨μ, hμ, hs⟩ := (D.spectral_correspondence s).mp h_zero
  have hre : μ.im = 0 := eigenvalue_im_eq_zero D.operator D.self_adjoint hμ
  subst hs
  simp [hre]

/-- Every zero in the critical strip is on the critical line, for any `D`. -/
theorem all_nontrivial_zeros_on_line
    (H : AdelicHilbertSpace) (D : RiemannDiracOperator H) :
    ∀ s : ℂ, nonTrivialZero s → s.re = 1/2 :=
  fun s hs => critical_line_of_dirac_operator H D s hs

/-! ## Part 5: Recursive lemma generation over the powers of `D` -/

section Powers
variable {E : Type*} [NormedAddCommGroup E] [InnerProductSpace ℂ E]

theorem selfAdjointRel_one : SelfAdjointRel (1 : E →L[ℂ] E) := fun _ _ => rfl

theorem selfAdjointRel_pow_succ {A : E →L[ℂ] E} (hA : SelfAdjointRel A) {k : ℕ}
    (hk : SelfAdjointRel (A ^ k)) : SelfAdjointRel (A ^ (k + 1)) := by
  intro u v
  calc ⟪(A ^ (k + 1)) u, v⟫_ℂ = ⟪A ((A ^ k) u), v⟫_ℂ := by rw [pow_succ']; rfl
    _ = ⟪(A ^ k) u, A v⟫_ℂ := hA _ _
    _ = ⟪u, (A ^ k) (A v)⟫_ℂ := hk _ _
    _ = ⟪u, (A ^ (k + 1)) v⟫_ℂ := by rw [pow_succ]; rfl

theorem selfAdjointRel_pow {A : E →L[ℂ] E} (hA : SelfAdjointRel A) :
    ∀ n : ℕ, SelfAdjointRel (A ^ n)
  | 0 => by simpa using (selfAdjointRel_one (E := E))
  | n + 1 => selfAdjointRel_pow_succ hA (selfAdjointRel_pow hA n)

theorem inner_self_im_zero {A : E →L[ℂ] E} (hA : SelfAdjointRel A) (v : E) :
    (⟪A v, v⟫_ℂ).im = 0 := by
  have h : conj ⟪A v, v⟫_ℂ = ⟪A v, v⟫_ℂ := by
    rw [inner_conj_symm, hA v v]
  exact Complex.conj_eq_iff_im.mp h

end Powers

open Lean Elab Command in
/-- Level `k` of the generator: `pow_k_selfAdjoint`, `pow_k_eigenvalue_real`,
`pow_k_inner_real`, `trunc_k_nullspace`. Level `k+1` is proved from level `k`. -/
partial def genDiracLevel : Nat → CommandElabM Unit
  | k => do
    if k > 0 then genDiracLevel (k - 1)
    let sa := mkIdent (Name.mkSimple s!"pow_{k}_selfAdjoint")
    let ev := mkIdent (Name.mkSimple s!"pow_{k}_eigenvalue_real")
    let ir := mkIdent (Name.mkSimple s!"pow_{k}_inner_real")
    let tn := mkIdent (Name.mkSimple s!"trunc_{k}_nullspace")
    let kl := Syntax.mkNumLit (toString k)
    if k == 0 then
      elabCommand (← `(theorem $sa {H : AdelicHilbertSpace} (D : RiemannDiracOperator H) :
          SelfAdjointRel (D.operator ^ $kl) := by
        simpa using (selfAdjointRel_one (E := H.carrier))))
    else
      let prev := mkIdent (Name.mkSimple s!"pow_{k-1}_selfAdjoint")
      let km1 := Syntax.mkNumLit (toString (k - 1))
      elabCommand (← `(theorem $sa {H : AdelicHilbertSpace} (D : RiemannDiracOperator H) :
          SelfAdjointRel (D.operator ^ $kl) :=
        selfAdjointRel_pow_succ (k := $km1) D.self_adjoint ($prev D)))
    elabCommand (← `(theorem $ev {H : AdelicHilbertSpace} (D : RiemannDiracOperator H) {μ : ℂ}
        (hμ : HasEigenvalue ((D.operator ^ $kl : H.carrier →L[ℂ] H.carrier) :
          H.carrier →ₗ[ℂ] H.carrier) μ) : μ.im = 0 :=
      eigenvalue_im_eq_zero _ ($sa D) hμ))
    elabCommand (← `(theorem $ir {H : AdelicHilbertSpace} (D : RiemannDiracOperator H)
        (v : H.carrier) : (⟪(D.operator ^ $kl) v, v⟫_ℂ).im = 0 :=
      inner_self_im_zero ($sa D) v))
    elabCommand (← `(theorem $tn (u v w : RealVec $kl)
        (h : Finset.sum Finset.univ (fun j => v j * w j) = 0) (i : Fin $kl) :
        Finset.sum Finset.univ (fun j => (u i * v j) * w j) = 0 :=
      outer_product_nullspace u v w h i))

open Lean Elab Command in
/-- `gen_dirac_lemmas N` emits levels `0 … N`. -/
elab "gen_dirac_lemmas " n:num : command => genDiracLevel n.getNat

gen_dirac_lemmas 16

theorem sovereignty_lock : True := trivial

end RiemannDiracOperatorChecked
