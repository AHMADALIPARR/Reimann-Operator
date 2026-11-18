# Copyright (C) 2026 Ahmad Ali Parr / SnapKitty Research Lab
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

"""Candidate verification metric and DSPy optimizer integration.

Policy:
- No majority-vote promotion of a conjecture into a theorem.
- No use of agent confidence as proof.
"""

from __future__ import annotations

from typing import Sequence

from .research_engine import CandidateRecord


def explicit_verification_metric(record: CandidateRecord) -> float:
    """Score a candidate strictly on structural & mathematical verifiability (0.0 to 1.0).

    Never promotes a conjecture to a theorem; penalizes missing obligations,
    counterexamples, or ungrounded claims.
    """
    score = 0.0
    if record.mathematical_statement.strip():
        score += 0.15
    if record.assumptions:
        score += 0.15
    if record.provenance_hash and len(record.provenance_hash) == 64:
        score += 0.10
    if "REFUTED" in record.counterexample_search_result.upper():
        return 0.0
    if record.counterexample_search_result.strip():
        score += 0.20
    if record.formal_verification_status == "VERIFIED_LEMMA":
        score += 0.40
    elif record.formal_verification_status == "NUMERICALLY_SUPPORTED":
        score += 0.15
    return round(min(score, 1.0), 6)


def select_best_candidates(
    records: Sequence[CandidateRecord], top_k: int = 5
) -> list[CandidateRecord]:
    """Deterministically rank by verification metric, never by agent confidence."""
    ranked = sorted(
        records,
        key=lambda r: (-explicit_verification_metric(r), r.hypothesis_id),
    )
    return list(ranked[:top_k])
