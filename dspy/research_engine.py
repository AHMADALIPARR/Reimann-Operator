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

"""DSPy Research Engine with Provider Temperature Validation, Provenance DAG,
and Bounded Recursive Branching.
"""

from __future__ import annotations

import hashlib
import json
import os
from dataclasses import asdict, dataclass, field
from typing import Dict, List, Optional, Set, Tuple

try:
    import dspy as _dspy  # type: ignore

    HAS_DSPY = True
except ImportError:
    _dspy = None  # type: ignore
    HAS_DSPY = False


# Explicit provider temperature limits; unsupported temperatures are REJECTED, never silently clamped.
PROVIDER_MAX_TEMPERATURE: Dict[str, float] = {
    "openai": 2.0,
    "anthropic": 1.0,
    "gemini": 2.0,
    "vertex_ai": 2.0,
    "mistral": 1.5,
    "local": 2.0,
}


def detect_provider(model_name: str) -> str:
    prefix = model_name.split("/", 1)[0].lower() if "/" in model_name else "openai"
    if prefix not in PROVIDER_MAX_TEMPERATURE:
        raise ValueError(
            f"Unsupported or unknown provider '{prefix}' in model '{model_name}'. "
            f"Supported providers: {sorted(PROVIDER_MAX_TEMPERATURE)}"
        )
    return prefix


def validate_temperature(model_name: str, temperature: float) -> float:
    """Strictly validate temperature against provider limits; reject unsupported values."""
    if not (0.0 <= temperature):
        raise ValueError(f"Temperature must be >= 0.0, got {temperature}")
    provider = detect_provider(model_name)
    max_temp = PROVIDER_MAX_TEMPERATURE[provider]
    if temperature > max_temp:
        raise ValueError(
            f"Requested temperature {temperature} exceeds max supported temperature "
            f"{max_temp} for provider '{provider}'. Rejecting rather than silently substituting."
        )
    return temperature


def configure_dspy_lm() -> Tuple[object, object]:
    """Configure high-temperature exploratory LM and deterministic verdict LM."""
    if not HAS_DSPY:
        raise RuntimeError("dspy is not installed in this environment")
    model = os.environ["SOVEREIGN_MODEL"]
    temp = float(os.environ.get("SOVEREIGN_TEMPERATURE", "1.0"))
    max_tokens = int(os.environ.get("SOVEREIGN_MAX_TOKENS", "16000"))
    validate_temperature(model, temp)

    exploratory_lm = _dspy.LM(model, temperature=temp, max_tokens=max_tokens)
    verdict_lm = _dspy.LM(model, temperature=0.0, max_tokens=max_tokens)
    _dspy.configure(lm=exploratory_lm)
    return exploratory_lm, verdict_lm


@dataclass
class CandidateRecord:
    hypothesis_id: str
    parent_hypothesis_ids: List[str]
    mathematical_statement: str
    assumptions: List[str]
    claimed_derivation: str
    spectral_evidence: Dict[str, float]
    entropy_score: float
    counterexample_search_result: str
    formal_verification_status: str  # UNRESOLVED_CONJECTURE | NUMERICALLY_SUPPORTED | VERIFIED_LEMMA | REFUTED
    provenance_hash: str = ""

    def compute_provenance_hash(self) -> str:
        data = asdict(self)
        data.pop("provenance_hash", None)
        canonical = json.dumps(data, sort_keys=True, separators=(",", ":")).encode("utf-8")
        self.provenance_hash = hashlib.sha256(canonical).hexdigest()
        return self.provenance_hash


def canonicalize_statement(statement: str) -> str:
    return " ".join(statement.strip().lower().split())


@dataclass
class BoundedResearchDAG:
    """Finite, provably terminating recursive branching DAG with deduplication."""

    max_depth: int = 4
    max_branching: int = 3
    max_total_candidates: int = 64
    nodes: Dict[str, CandidateRecord] = field(default_factory=dict)
    seen_statements: Set[str] = field(default_factory=set)
    processed_ids: List[str] = field(default_factory=list)

    def add_candidate(self, record: CandidateRecord, depth: int) -> bool:
        if depth > self.max_depth:
            return False
        if len(self.nodes) >= self.max_total_candidates:
            return False
        canon = canonicalize_statement(record.mathematical_statement)
        if canon in self.seen_statements:
            return False
        # Verify parent references exist (DAG acyclicity)
        for pid in record.parent_hypothesis_ids:
            if pid not in self.nodes:
                raise ValueError(f"Missing parent hypothesis ID: {pid}")
        record.compute_provenance_hash()
        self.nodes[record.hypothesis_id] = record
        self.seen_statements.add(canon)
        self.processed_ids.append(record.hypothesis_id)
        return True
