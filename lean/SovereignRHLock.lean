/-
  SOVEREIGN-RH-LOCK Formal Structural & Epistemic Lemmas in Pure Lean 4.
  Constraints:
  - ZERO `sorry`
  - ZERO custom `axiom` declarations
  - Uses only Lean 4 core (`Init`) with hand-written proofs.
-/

namespace SovereignRHLock

/-- Five mutually distinct epistemic states enforced by ASP & OWL. -/
inductive EpistemicState where
  | candidate
  | numericallySupported
  | formallyVerifiedLemma
  | refuted
  | unresolvedConjecture
  deriving DecidableEq, Repr

/-- Status of an analytic proof obligation. -/
inductive ObligationStatus where
  | openObl
  | partialObl
  | dischargedObl
  deriving DecidableEq, Repr

/-- Structured proof-obligation ledger for Gate 9 and Gate 10. -/
structure ProofLedger where
  obl01HilbertSpace : ObligationStatus
  obl02DenseDomain : ObligationStatus
  obl03Symmetry : ObligationStatus
  obl04SelfAdjoint : ObligationStatus
  obl05TraceFormula : ObligationStatus
  obl06Completeness : ObligationStatus
  obl07Multiplicity : ObligationStatus
  obl08CriticalLine : ObligationStatus
  oblBridge01 : ObligationStatus
  deriving DecidableEq, Repr

/-- Gate 9 closes iff self-adjointness, trace formula, completeness, and multiplicity are all discharged. -/
def gate9Closed (L : ProofLedger) : Bool :=
  (L.obl04SelfAdjoint == ObligationStatus.dischargedObl) &&
  (L.obl05TraceFormula == ObligationStatus.dischargedObl) &&
  (L.obl06Completeness == ObligationStatus.dischargedObl) &&
  (L.obl07Multiplicity == ObligationStatus.dischargedObl)

/-- Gate 10 (RH Proof Admission) requires Gate 9 closed AND critical-line derivation discharged. -/
def gate10RHAdmitted (L : ProofLedger) : Bool :=
  gate9Closed L && (L.obl08CriticalLine == ObligationStatus.dischargedObl)

/-- Lemma 1: If Gate 9 is open, Gate 10 cannot admit an RH proof. -/
theorem gate10_blocked_when_gate9_open (L : ProofLedger) (h : gate9Closed L = false) :
    gate10RHAdmitted L = false := by
  unfold gate10RHAdmitted
  rw [h]
  rfl

/-- Lemma 2: An open completeness obligation (OBL-06) blocks Gate 9 and Gate 10. -/
theorem open_completeness_blocks_rh (L : ProofLedger)
    (h : L.obl06Completeness = ObligationStatus.openObl) :
    gate10RHAdmitted L = false := by
  apply gate10_blocked_when_gate9_open
  unfold gate9Closed
  rw [h]
  simp

/-- Lemma 3: Epistemic separation — numerical support is strictly distinct from a formal lemma. -/
theorem numeric_support_not_formal_lemma :
    EpistemicState.numericallySupported ≠ EpistemicState.formallyVerifiedLemma := by
  intro h
  cases h

/-- Candidate admissibility record mirroring ASP `proof_admission.lp`. -/
structure CandidateAdmission where
  hasMissingObligation : Bool
  hasRefutedEvidence : Bool
  hasFormalEvidence : Bool

def aspRetained (c : CandidateAdmission) : Bool :=
  (!c.hasMissingObligation) && (!c.hasRefutedEvidence)

def aspFormallyAdmissible (c : CandidateAdmission) : Bool :=
  aspRetained c && c.hasFormalEvidence

/-- Lemma 4: A candidate with a missing obligation is never retained and never formally admissible. -/
theorem missing_obligation_blocks_admission (c : CandidateAdmission)
    (h : c.hasMissingObligation = true) :
    aspRetained c = false ∧ aspFormallyAdmissible c = false := by
  unfold aspFormallyAdmissible aspRetained
  rw [h]
  simp

/-- Lemma 5: Block-encoding boundedness obstruction.
    If a block encoding requires `normSq <= alphaSq`, any operator with `alphaSq < normSq`
    cannot be block-encoded with subnormalization `alphaSq`. -/
theorem block_encoding_boundedness_obstruction (normSq alphaSq : Nat)
    (h_unbounded : alphaSq < normSq) :
    ¬ (normSq ≤ alphaSq) := by
  omega

/-- Lemma 6: Klong 64-bit SoA binary layout byte-length invariant:
    32-byte header + 9 columns * 8 bytes/element * n = 32 + 72 * n. -/
theorem klong_abi_byte_length (n : Nat) :
    32 + 9 * (8 * n) = 32 + 72 * n := by
  omega

/-- Lemma 7: Bounded recursive search termination measure.
    Every accepted node strictly reduces remaining node budget `budget - count`. -/
theorem bounded_search_measure_decreases (budget count : Nat) (h : count < budget) :
    budget - (count + 1) < budget - count := by
  omega

end SovereignRHLock
