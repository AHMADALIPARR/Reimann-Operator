# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

"""DSPy Signatures for SOVEREIGN-RH-LOCK Conjecture & Proof-Audit Engine."""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict

_REPO_ROOT = str(Path(__file__).resolve().parents[1])
_saved_path = list(sys.path)
try:
    sys.path = [p for p in sys.path if p not in ("", _REPO_ROOT)]
    import dspy as _dspy  # type: ignore

    if hasattr(_dspy, "Signature") and hasattr(_dspy, "LM"):
        HAS_DSPY = True
    else:
        _dspy = None  # type: ignore
        HAS_DSPY = False
except ImportError:
    _dspy = None  # type: ignore
    HAS_DSPY = False
finally:
    sys.path = _saved_path


@dataclass(frozen=True)
class SignatureSpec:
    name: str
    inputs: tuple[str, ...]
    outputs: tuple[str, ...]
    role: str


SIGNATURE_SPECS: Dict[str, SignatureSpec] = {
    "GenerateSpectralHypothesis": SignatureSpec(
        name="GenerateSpectralHypothesis",
        inputs=("parent_hypotheses", "open_obligations", "entropy_summary"),
        outputs=("mathematical_statement", "assumptions", "claimed_derivation", "target_obligations"),
        role="exploratory_high_temp",
    ),
    "ConstructAdelicOperator": SignatureSpec(
        name="ConstructAdelicOperator",
        inputs=("hilbert_space_spec", "scaling_action", "cutoff_parameter"),
        outputs=("operator_definition", "dense_domain", "symmetry_argument"),
        role="exploratory_high_temp",
    ),
    "AnalyzeSelfAdjointness": SignatureSpec(
        name="AnalyzeSelfAdjointness",
        inputs=("operator_definition", "dense_domain"),
        outputs=("deficiency_indices", "extension_family", "self_adjoint_verdict"),
        role="deterministic_verdict",
    ),
    "GenerateZetaZeroCandidate": SignatureSpec(
        name="GenerateZetaZeroCandidate",
        inputs=("spectral_interval", "operator_eigenvalues"),
        outputs=("candidate_real", "candidate_imag", "correspondence_rationale"),
        role="exploratory_high_temp",
    ),
    "DeriveEntropyFeatures": SignatureSpec(
        name="DeriveEntropyFeatures",
        inputs=("density_spectrum", "hypothesis_distribution"),
        outputs=("von_neumann_note", "shannon_note", "priority_features"),
        role="deterministic_verdict",
    ),
    "ProposeSpectralPruningRule": SignatureSpec(
        name="ProposeSpectralPruningRule",
        inputs=("residual_threshold", "entropy_threshold", "generation"),
        outputs=("pruning_predicate", "provenance_preservation_note"),
        role="exploratory_high_temp",
    ),
    "ConstructASPConstraint": SignatureSpec(
        name="ConstructASPConstraint",
        inputs=("obligation_id", "domain_rule", "rejection_condition"),
        outputs=("clingo_rule", "integrity_constraint"),
        role="deterministic_verdict",
    ),
    "ConstructOWLClassification": SignatureSpec(
        name="ConstructOWLClassification",
        inputs=("entity_name", "mathematical_role", "evidence_type"),
        outputs=("owl_classes", "object_properties", "open_world_note"),
        role="deterministic_verdict",
    ),
    "SearchForCounterexample": SignatureSpec(
        name="SearchForCounterexample",
        inputs=("mathematical_statement", "assumptions", "spectral_evidence"),
        outputs=("counterexample_found", "counterexample_witness", "refutation_reason"),
        role="deterministic_verdict",
    ),
    "AuditMathematicalProof": SignatureSpec(
        name="AuditMathematicalProof",
        inputs=("mathematical_statement", "claimed_derivation", "discharged_obligations"),
        outputs=("missing_obligations", "circularity_detected", "formal_verdict"),
        role="deterministic_verdict",
    ),
}
